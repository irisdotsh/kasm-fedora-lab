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

# Uninstalled apps really gone
check "no sublime"   bash -c '! rpm -q sublime-text'
check "no firefox"   bash -c '! rpm -q firefox'
check "no zoom"      bash -c '! rpm -q zoom'
check "no slack"     bash -c '! rpm -q slack'
check "no gimp"      bash -c '! rpm -q gimp'
check "no telegram"  bash -c '! test -e /opt/Telegram'

exit $fail
