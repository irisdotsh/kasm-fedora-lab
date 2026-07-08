# syntax=docker/dockerfile:1
FROM kasmweb/fedora-43-desktop:1.19.0-rolling-daily

LABEL org.opencontainers.image.source=https://git.irisblankenship.me/iris/kasm-fedora-lab

USER root
ENV HOME=/home/kasm-default-profile
ENV STARTUPDIR=/dockerstartup
WORKDIR $HOME

# ---------------------------------------------------------------------------
# Repos: VS Code (Microsoft) + Docker CE
# ---------------------------------------------------------------------------
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc && \
    printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' \
      > /etc/yum.repos.d/vscode.repo && \
    curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
      -o /etc/yum.repos.d/docker-ce.repo

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
RUN dnf -y install \
      code \
      python3 python3-pip \
      ansible \
      unzip xz \
      openssh-clients vim-enhanced curl wget git \
      wireshark \
      xfce4-terminal \
      greybird-dark-theme greybird-xfwm4-theme \
      sudo procps-ng iptables-nft fuse-overlayfs \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
      libxkbcommon-x11 xcb-util-wm xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-cursor \
      libXScrnSaver xdg-utils && \
    dnf clean all

# ---------------------------------------------------------------------------
# Remove base-image apps we don't want (their desktop icons are rebuilt at the
# end of this file). Telegram is a /opt tarball; the rest are packages, and
# Sublime also leaves a repo file behind. `|| true` so a future base image that
# drops one of these doesn't break the build.
# ---------------------------------------------------------------------------
RUN for pkg in firefox gimp zoom slack sublime-text; do dnf -y remove "$pkg" || true; done && \
    rm -f /etc/yum.repos.d/sublime-text.repo && \
    rm -rf /opt/Telegram /usr/share/applications/telegram.desktop && \
    dnf clean all

# ---------------------------------------------------------------------------
# Firefox Developer Edition -> /opt/firefox-dev
# ---------------------------------------------------------------------------
RUN curl -fsSL "https://download.mozilla.org/?product=firefox-devedition-latest-ssl&os=linux64&lang=en-US" \
      -o /tmp/ffdev.tar.xz && \
    tar -xJf /tmp/ffdev.tar.xz -C /opt && \
    mv /opt/firefox /opt/firefox-dev && \
    rm /tmp/ffdev.tar.xz

# Bitwarden + uBlock Origin force-installed via enterprise policy;
# in-app updater disabled (updates come from image rebuilds)
COPY <<'EOF' /opt/firefox-dev/distribution/policies.json
{
  "policies": {
    "DisableAppUpdate": true,
    "ExtensionSettings": {
      "{446900e4-71c2-419f-a6a7-df9c091e268b}": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi"
      },
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      }
    }
  }
}
EOF

COPY <<'EOF' /usr/share/applications/firefox-dev.desktop
[Desktop Entry]
Type=Application
Name=Firefox Developer Edition
Exec=/opt/firefox-dev/firefox %u
Icon=/opt/firefox-dev/browser/chrome/icons/default/default128.png
Terminal=false
Categories=Network;WebBrowser;
StartupWMClass=firefox-aurora
EOF

# ---------------------------------------------------------------------------
# Postman -> /opt/Postman
# ---------------------------------------------------------------------------
RUN curl -fsSL https://dl.pstmn.io/download/latest/linux_64 -o /tmp/postman.tar.gz && \
    tar -xzf /tmp/postman.tar.gz -C /opt && \
    rm /tmp/postman.tar.gz

COPY <<'EOF' /usr/share/applications/postman.desktop
[Desktop Entry]
Type=Application
Name=Postman
Exec=/opt/Postman/Postman
Icon=/opt/Postman/app/icons/icon_128x128.png
Terminal=false
Categories=Development;
EOF

# ---------------------------------------------------------------------------
# Bitwarden desktop (AppImage, extracted -- no FUSE needed) -> /opt/bitwarden
# ---------------------------------------------------------------------------
RUN curl -fsSL "https://vault.bitwarden.com/download/?app=desktop&platform=linux" \
      -o /tmp/bitwarden.AppImage && \
    chmod +x /tmp/bitwarden.AppImage && \
    cd /tmp && ./bitwarden.AppImage --appimage-extract >/dev/null && \
    mv /tmp/squashfs-root /opt/bitwarden && \
    chmod -R a+rX /opt/bitwarden && \
    chown root:root /opt/bitwarden/chrome-sandbox && \
    chmod 4755 /opt/bitwarden/chrome-sandbox && \
    rm /tmp/bitwarden.AppImage

COPY <<'EOF' /usr/share/applications/bitwarden.desktop
[Desktop Entry]
Type=Application
Name=Bitwarden
Exec=/opt/bitwarden/bitwarden %U
Icon=/opt/bitwarden/bitwarden.png
Terminal=false
Categories=Utility;Security;
EOF

# ---------------------------------------------------------------------------
# Docker-in-Docker: kasm-user may start dockerd via sudo; CLI access via
# docker group. Daemon launched by Kasm's custom_startup hook at session start.
# Requires the container to run with --privileged.
# ---------------------------------------------------------------------------
RUN usermod -aG docker,wireshark kasm-user && \
    echo 'kasm-user ALL=(ALL) NOPASSWD: /usr/bin/dockerd' > /etc/sudoers.d/dockerd && \
    chmod 0440 /etc/sudoers.d/dockerd

# Fedora's stock sudo PAM stack includes system-auth (pam_sss), which fails
# its account phase inside a container with no sssd daemon running:
#   "PAM account management error: Authentication service cannot retrieve
#    authentication info"
# Authorization is enforced by the sudoers rule above; make PAM a no-op here.
COPY <<'EOF' /etc/pam.d/sudo
auth       sufficient   pam_permit.so
account    sufficient   pam_permit.so
password   required     pam_deny.so
session    optional     pam_keyinit.so revoke
session    required     pam_limits.so
EOF

COPY <<'EOF' /dockerstartup/custom_startup.sh
#!/usr/bin/env bash
set -e
if ! pgrep -x dockerd >/dev/null 2>&1; then
    sudo /usr/bin/dockerd >/tmp/dockerd.log 2>&1 &
fi
EOF
RUN chmod +x /dockerstartup/custom_startup.sh

# ---------------------------------------------------------------------------
# Theme: Greybird-dark GTK theme + matching Greybird-dark xfwm4 window
# decorations. VS Code dark below; Firefox Dev Edition is dark by default.
# ---------------------------------------------------------------------------
COPY <<'EOF' /home/kasm-default-profile/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Greybird-dark"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
  </property>
</channel>
EOF

COPY <<'EOF' /home/kasm-default-profile/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Greybird-dark"/>
  </property>
</channel>
EOF

COPY <<'EOF' /home/kasm-default-profile/.config/Code/User/settings.json
{
  "workbench.colorTheme": "Default Dark Modern",
  "telemetry.telemetryLevel": "off"
}
EOF

# ---------------------------------------------------------------------------
# Desktop icons: exactly the six we want. The base image drops one .desktop
# per app into ~/Desktop; wipe it and lay down only these, +x so XFCE treats
# them as trusted launchers.
# ---------------------------------------------------------------------------
RUN mkdir -p /home/kasm-default-profile/Desktop && \
    rm -f /home/kasm-default-profile/Desktop/*.desktop && \
    cp /usr/share/applications/firefox-dev.desktop                 /home/kasm-default-profile/Desktop/firefox-dev.desktop && \
    cp /usr/share/applications/code.desktop                        /home/kasm-default-profile/Desktop/code.desktop && \
    cp /usr/share/applications/xfce4-terminal.desktop              /home/kasm-default-profile/Desktop/xfce4-terminal.desktop && \
    cp /usr/share/applications/postman.desktop                     /home/kasm-default-profile/Desktop/postman.desktop && \
    cp /usr/share/applications/net.thunderbird.Thunderbird.desktop /home/kasm-default-profile/Desktop/thunderbird.desktop && \
    find /usr/share/applications -iname '*wireshark*.desktop' -exec cp {} /home/kasm-default-profile/Desktop/wireshark.desktop \; && \
    chmod +x /home/kasm-default-profile/Desktop/*.desktop

# ---------------------------------------------------------------------------
# Finalize: fix default-profile ownership, drop back to kasm-user
# ---------------------------------------------------------------------------
RUN chown -R 1000:0 /home/kasm-default-profile && \
    if [ -f $STARTUPDIR/set_user_permission.sh ]; then \
      $STARTUPDIR/set_user_permission.sh $HOME; \
    fi

ENV HOME=/home/kasm-user
WORKDIR $HOME
USER 1000
