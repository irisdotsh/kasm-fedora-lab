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

COPY <<'EOF' /etc/yum.repos.d/opentofu.repo
[opentofu]
name=OpenTofu
baseurl=https://packages.opentofu.org/opentofu/tofu/rpm_any/rpm_any/$basearch
repo_gpgcheck=0
gpgcheck=1
enabled=1
gpgkey=https://get.opentofu.org/opentofu.gpg
       https://packages.opentofu.org/opentofu/tofu/gpgkey
EOF

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
# Fedora's `ansible` is the community bundle -- network collections
# (ansible.netcommon, community.routeros, cisco.ios, ...) ship inside it;
# paramiko/pylibssh below are the connection libs network_cli needs.
RUN dnf -y install \
      code \
      python3 python3-pip \
      ansible ansible-lint python3-paramiko python3-ansible-pylibssh \
      tofu \
      unzip xz jq \
      openssh-clients vim-enhanced curl wget git tmux \
      wireshark \
      nmap nmap-ncat tcpdump mtr traceroute iperf3 socat \
      bind-utils whois fping net-snmp-utils ethtool ipcalc telnet minicom \
      wireguard-tools openconnect openvpn \
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
# yq (mikefarah/Go version -- Fedora's yq is the incompatible jq-wrapper).
# amd64-only, like the other /opt downloads in this image.
# ---------------------------------------------------------------------------
RUN curl -fsSL -o /usr/local/bin/yq \
      https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    chmod +x /usr/local/bin/yq

# ---------------------------------------------------------------------------
# containerlab -- RPM straight from GitHub releases. Its yum repo (Gemfury)
# is too slow/rate-limited from CI: metadata at ~17 KiB/s and the 41MB RPM
# times dnf out. Asset names embed the version, so resolve it from the
# /releases/latest redirect first.
# ---------------------------------------------------------------------------
RUN ver=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
        https://github.com/srl-labs/containerlab/releases/latest) && \
    ver="${ver##*/v}" && \
    curl -fsSL -o /tmp/containerlab.rpm \
      "https://github.com/srl-labs/containerlab/releases/download/v${ver}/containerlab_${ver}_linux_amd64.rpm" && \
    dnf -y install /tmp/containerlab.rpm && \
    rm /tmp/containerlab.rpm && \
    dnf clean all

# ---------------------------------------------------------------------------
# Twingate client (CLI + notifier -- Twingate ships no Linux GUI). Installed
# via their documented script, which adds their rpm repo; its systemctl calls
# may fail here (no systemd in Kasm containers), so tolerate script errors
# and assert the package actually landed. The daemon is started by the
# custom_startup hook below once `sudo twingate setup` has been run; config
# in /etc/twingate is volume-persisted via compose.
# ---------------------------------------------------------------------------
RUN (curl -fsSL https://binaries.twingate.com/client/linux/install.sh | bash) || true && \
    rpm -q twingate && \
    dnf clean all

# ---------------------------------------------------------------------------
# Python network-automation stack in a venv (Fedora's system python is
# PEP 668-managed, so no system-wide pip installs). PATH hook appends the
# venv bin dir so the system python/pip stay first.
# ---------------------------------------------------------------------------
RUN python3 -m venv /opt/netauto && \
    /opt/netauto/bin/pip install --no-cache-dir \
      netmiko napalm nornir nornir-netmiko nornir-napalm nornir-utils \
      scrapli pynetbox ciscoconfparse2 ttp textfsm pyang rich

COPY <<'EOF' /etc/profile.d/netauto.sh
# Network-automation venv CLIs (napalm, nornir, pyang, ...).
# Appended, not prepended: the system python/pip must stay first on PATH.
export PATH="$PATH:/opt/netauto/bin"
EOF

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
# The icon's location inside the tarball moves between releases (currently
# app/resources/app/assets/icon.png, formerly app/icons/icon_128x128.png),
# so find it and copy to a stable path the launcher can rely on. `test -n`
# fails the build loudly if a future layout hides it somewhere new.
RUN curl -fsSL https://dl.pstmn.io/download/latest/linux_64 -o /tmp/postman.tar.gz && \
    tar -xzf /tmp/postman.tar.gz -C /opt && \
    rm /tmp/postman.tar.gz && \
    icon=$(find /opt/Postman -type f \( -name 'icon.png' -o -name 'icon_128x128.png' \) | head -1) && \
    test -n "$icon" && \
    cp "$icon" /opt/Postman/postman-icon.png

COPY <<'EOF' /usr/share/applications/postman.desktop
[Desktop Entry]
Type=Application
Name=Postman
Exec=/opt/Postman/Postman
Icon=/opt/Postman/postman-icon.png
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
# containerlab also needs root (netns wiring), so allow it too -- both the
# full name and the `clab` symlink its package ships.
# ---------------------------------------------------------------------------
# Twingate paths are listed for both bin/sbin -- entries for a path that
# doesn't exist are inert, and the smoke test pins down the real one.
RUN usermod -aG docker,wireshark kasm-user && \
    echo 'kasm-user ALL=(ALL) NOPASSWD: /usr/bin/dockerd, /usr/bin/containerlab, /usr/bin/clab, /usr/bin/twingate, /usr/sbin/twingate, /usr/bin/twingated, /usr/sbin/twingated' > /etc/sudoers.d/dockerd && \
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

# Twingate: no systemd here, so start twingated ourselves -- but only once
# the client has been configured (sudo twingate setup writes /etc/twingate).
tgd=$(command -v twingated || true)
if [ -n "$tgd" ] && [ -n "$(ls -A /etc/twingate 2>/dev/null)" ] && \
   ! pgrep -x twingated >/dev/null 2>&1; then
    sudo "$tgd" /etc/twingate >/tmp/twingated.log 2>&1 &
fi
EOF
RUN chmod +x /dockerstartup/custom_startup.sh

# ---------------------------------------------------------------------------
# Twingate desktop entry point: opens a terminal that walks through setup on
# first use (auth link opens in the browser), starts the daemon, and shows
# status. This stands in for the GUI Twingate doesn't ship on Linux.
# ---------------------------------------------------------------------------
COPY <<'EOF' /usr/local/bin/twingate-desktop
#!/usr/bin/env bash
echo "=== Twingate ==="
if [ -z "$(ls -A /etc/twingate 2>/dev/null)" ]; then
    echo "Not configured yet -- running setup (open the auth link in Firefox):"
    sudo twingate setup
fi
if ! pgrep -x twingated >/dev/null 2>&1; then
    echo "Starting twingated..."
    sudo "$(command -v twingated)" /etc/twingate >/tmp/twingated.log 2>&1 &
    sleep 2
fi
twingate status 2>/dev/null || sudo twingate status || true
echo
echo "Useful: twingate status | twingate resources | sudo twingate setup"
exec bash
EOF
RUN chmod +x /usr/local/bin/twingate-desktop

COPY <<'EOF' /usr/share/applications/twingate.desktop
[Desktop Entry]
Type=Application
Name=Twingate
Exec=xfce4-terminal --title=Twingate -e /usr/local/bin/twingate-desktop
Icon=network-vpn
Terminal=false
Categories=Network;
EOF

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
  "telemetry.telemetryLevel": "off",
  "python.defaultInterpreterPath": "/opt/netauto/bin/python"
}
EOF

# ---------------------------------------------------------------------------
# VS Code extensions baked into the default profile (ansible, yaml, python,
# jinja, terraform/tofu). --no-sandbox/--user-data-dir let the CLI run as root.
# ---------------------------------------------------------------------------
RUN HOME=/home/kasm-default-profile \
    code --no-sandbox \
         --user-data-dir /home/kasm-default-profile/.config/Code \
         --extensions-dir /home/kasm-default-profile/.vscode/extensions \
         --install-extension redhat.ansible \
         --install-extension redhat.vscode-yaml \
         --install-extension ms-python.python \
         --install-extension samuelcolvin.jinjahtml \
         --install-extension hashicorp.terraform

# ---------------------------------------------------------------------------
# SSH client defaults for lab gear: keepalives, TOFU host keys, and
# commented-out legacy-crypto knobs to uncomment per-host as needed.
# ---------------------------------------------------------------------------
COPY <<'EOF' /home/kasm-default-profile/.ssh/config
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    StrictHostKeyChecking accept-new
    # Old network gear often needs legacy crypto -- enable per-host:
    # KexAlgorithms +diffie-hellman-group14-sha1
    # HostKeyAlgorithms +ssh-rsa
    # PubkeyAcceptedAlgorithms +ssh-rsa
EOF
RUN chmod 700 /home/kasm-default-profile/.ssh && \
    chmod 600 /home/kasm-default-profile/.ssh/config

# ---------------------------------------------------------------------------
# Desktop icons: exactly the seven we want. The base image drops one .desktop
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
    cp /usr/share/applications/twingate.desktop                    /home/kasm-default-profile/Desktop/twingate.desktop && \
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
