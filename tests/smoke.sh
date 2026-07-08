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

# GUI apps
check "firefox dev"         /opt/firefox-dev/firefox --version
check "ff policies exist"   test -f /opt/firefox-dev/distribution/policies.json
check "ff ublock policy"    grep -q 'uBlock0@raymondhill.net' /opt/firefox-dev/distribution/policies.json
check "ff bitwarden policy" grep -q '446900e4-71c2-419f-a6a7-df9c091e268b' /opt/firefox-dev/distribution/policies.json
check "postman"             test -x /opt/Postman/Postman
check "bitwarden desktop"   test -x /opt/bitwarden/bitwarden

# Dark mode config baked into default profile
check "gtk dark theme"      grep -q 'Adwaita-dark' /home/kasm-default-profile/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
check "vscode dark theme"   grep -q 'Default Dark Modern' /home/kasm-default-profile/.config/Code/User/settings.json

exit $fail
