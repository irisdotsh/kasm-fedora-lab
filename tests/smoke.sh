#!/usr/bin/env bash
# Smoke test: run inside the image as kasm-user (uid 1000).
# Locally: docker run --rm --entrypoint bash -v "$PWD/tests:/tests:ro" <image> /tests/smoke.sh
set -uo pipefail

fail=0
check() {
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then
        echo "ok    $desc"
    else
        echo "FAIL  $desc"
        fail=1
    fi
}

# CLI tooling
check "vscode"              code --version
check "python3"             python3 --version
check "pip"                 pip3 --version
check "unzip"               unzip -v
check "openssh client"      ssh -V
check "vim"                 vim --version
check "curl"                curl --version
check "wget"                wget --version
check "git"                 git --version
check "ansible"             ansible --version
check "wireshark"           wireshark --version

# Docker-in-Docker plumbing
check "docker cli"          docker --version
check "docker compose"      docker compose version
check "dockerd present"     test -x /usr/bin/dockerd
check "sudoers dockerd"     sudo -n /usr/bin/dockerd --version
check "docker group"        bash -c 'id -nG | grep -qw docker'
check "wireshark group"     bash -c 'id -nG | grep -qw wireshark'
check "custom_startup"      test -x /dockerstartup/custom_startup.sh

# Network automation toolchain
check "containerlab"         containerlab version
check "sudoers containerlab" sudo -n /usr/bin/containerlab version
check "opentofu"             tofu version
check "jq"                   jq --version
check "yq"                   yq --version
check "tmux"                 tmux -V
check "ansible-lint"         ansible-lint --version
check "paramiko"             python3 -c 'import paramiko'
check "ansible-pylibssh"     python3 -c 'import pylibsshext'
check "netcommon collection" bash -c 'ansible-galaxy collection list 2>/dev/null | grep -q ansible.netcommon'
check "routeros collection"  bash -c 'ansible-galaxy collection list 2>/dev/null | grep -q community.routeros'

# Python network-automation venv
check "venv netmiko"    /opt/netauto/bin/python -c 'import netmiko'
check "venv napalm"     /opt/netauto/bin/python -c 'import napalm'
check "venv nornir"     /opt/netauto/bin/python -c 'import nornir'
check "venv scrapli"    /opt/netauto/bin/python -c 'import scrapli'
check "venv pynetbox"   /opt/netauto/bin/python -c 'import pynetbox'
check "venv pyang"      /opt/netauto/bin/pyang --version
check "venv PATH hook"  grep -q '/opt/netauto/bin' /etc/profile.d/netauto.sh

# Network CLI tools
check "nmap"        nmap --version
check "ncat"        ncat --version
check "tcpdump"     tcpdump --version
check "tshark"      tshark --version
check "mtr"         mtr --version
check "traceroute"  bash -c 'command -v traceroute'
check "iperf3"      iperf3 --version
check "socat"       socat -V
check "dig"         dig -v
check "whois"       bash -c 'command -v whois'
check "fping"       fping -v
check "snmpwalk"    snmpwalk -V
check "ethtool"     ethtool --version
check "ipcalc"      bash -c 'command -v ipcalc'
check "telnet"      bash -c 'command -v telnet'
check "minicom"     minicom --version
check "wireguard"   wg --version
check "openconnect" openconnect --version
check "openvpn"     bash -c 'command -v openvpn'

# GUI apps
check "firefox dev"         /opt/firefox-dev/firefox --version
check "ff policies exist"   test -f /opt/firefox-dev/distribution/policies.json
check "ff ublock policy"    grep -q 'uBlock0@raymondhill.net' /opt/firefox-dev/distribution/policies.json
check "ff bitwarden policy" grep -q '446900e4-71c2-419f-a6a7-df9c091e268b' /opt/firefox-dev/distribution/policies.json
check "postman"             test -x /opt/Postman/Postman
check "bitwarden desktop"   test -x /opt/bitwarden/bitwarden
check "thunderbird"         rpm -q thunderbird

# Theme baked into default profile: Greybird-dark GTK + matching xfwm4
check "greybird gtk theme"       grep -q 'Greybird-dark' /home/kasm-default-profile/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
check "greybird xfwm4 theme"     grep -q 'Greybird-dark' /home/kasm-default-profile/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
check "greybird gtk installed"   test -d /usr/share/themes/Greybird-dark
check "greybird xfwm4 installed" rpm -q greybird-xfwm4-theme
check "vscode dark theme"        grep -q 'Default Dark Modern' /home/kasm-default-profile/.config/Code/User/settings.json

# Exactly the six desktop launchers we want, nothing else
DESK=/home/kasm-default-profile/Desktop
check "desktop firefox-dev"  test -x "$DESK/firefox-dev.desktop"
check "desktop vscode"       test -x "$DESK/code.desktop"
check "desktop terminal"     test -x "$DESK/xfce4-terminal.desktop"
check "desktop postman"      test -x "$DESK/postman.desktop"
check "desktop wireshark"    test -x "$DESK/wireshark.desktop"
check "desktop thunderbird"  test -x "$DESK/thunderbird.desktop"
check "exactly 6 desktop icons" \
    bash -c '[ "$(ls -1 /home/kasm-default-profile/Desktop/*.desktop 2>/dev/null | wc -l)" -eq 6 ]'

# Launchers with an absolute Icon= path must point at a file that exists
# (app tarballs move their icons between releases -- Postman has already)
for f in "$DESK"/*.desktop; do
    icon=$(grep -m1 '^Icon=' "$f" | cut -d= -f2-)
    case "$icon" in
        /*) check "icon exists: $(basename "$f" .desktop)" test -f "$icon" ;;
    esac
done

# Workspace polish baked into the default profile
check "vscode ansible ext"  bash -c 'ls /home/kasm-default-profile/.vscode/extensions | grep -q redhat.ansible'
check "vscode yaml ext"     bash -c 'ls /home/kasm-default-profile/.vscode/extensions | grep -q redhat.vscode-yaml'
check "vscode python ext"   bash -c 'ls /home/kasm-default-profile/.vscode/extensions | grep -q ms-python.python'
check "vscode jinja ext"    bash -c 'ls /home/kasm-default-profile/.vscode/extensions | grep -q samuelcolvin.jinjahtml'
check "vscode tf ext"       bash -c 'ls /home/kasm-default-profile/.vscode/extensions | grep -q hashicorp.terraform'
check "ssh config skeleton" test -f /home/kasm-default-profile/.ssh/config

# Uninstalled apps really gone
check "no sublime"   bash -c '! rpm -q sublime-text'
check "no firefox"   bash -c '! rpm -q firefox'
check "no zoom"      bash -c '! rpm -q zoom'
check "no slack"     bash -c '! rpm -q slack'
check "no gimp"      bash -c '! rpm -q gimp'
check "no telegram"  bash -c '! test -e /opt/Telegram'

exit $fail
