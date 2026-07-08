# syntax=docker/dockerfile:1
FROM kasmweb/fedora-43-desktop:1.19.0-rolling-daily

LABEL org.opencontainers.image.source=https://github.com/irisdotsh/kasm-fedora-lab

USER root
ENV HOME=/home/kasm-default-profile
ENV STARTUPDIR=/dockerstartup
WORKDIR $HOME

# Check https://mikrotik.com/download/winbox for current version
ARG WINBOX_VERSION=4.1

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
      sudo procps-ng iptables-nft fuse-overlayfs \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
      libxkbcommon-x11 xcb-util-wm xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-cursor \
      libXScrnSaver xdg-utils && \
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
# WinBox 4 (native Linux) -> /opt/winbox
# ---------------------------------------------------------------------------
RUN curl -fsSL "https://download.mikrotik.com/routeros/winbox/${WINBOX_VERSION}/WinBox_Linux.zip" \
      -o /tmp/winbox.zip && \
    mkdir -p /opt/winbox && \
    unzip -q /tmp/winbox.zip -d /opt/winbox && \
    chmod +x /opt/winbox/WinBox && \
    rm /tmp/winbox.zip

COPY <<'EOF' /usr/share/applications/winbox4.desktop
[Desktop Entry]
Type=Application
Name=WinBox 4
Exec=/opt/winbox/WinBox
Icon=/opt/winbox/assets/img/winbox.png
Terminal=false
Categories=Network;
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
# Dark mode: XFCE GTK theme + VS Code (Firefox Dev Edition is dark by default)
# ---------------------------------------------------------------------------
COPY <<'EOF' /home/kasm-default-profile/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
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
# Finalize: fix default-profile ownership, drop back to kasm-user
# ---------------------------------------------------------------------------
RUN chown -R 1000:0 /home/kasm-default-profile && \
    if [ -f $STARTUPDIR/set_user_permission.sh ]; then \
      $STARTUPDIR/set_user_permission.sh $HOME; \
    fi

ENV HOME=/home/kasm-user
WORKDIR $HOME
USER 1000
