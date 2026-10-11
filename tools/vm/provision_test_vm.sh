#!/bin/bash
# One-time setup of a macOS VM for tools/run_tests_vm.sh. Idempotent: rerun it any time, e.g.
# after updating Xcode on this machine.
#
# Usage (from an interactive terminal, since some steps ask for the VM user's password):
#   tools/vm/provision_test_vm.sh HOST            # everything
#   tools/vm/provision_test_vm.sh --no-sudo HOST  # only the steps that need no password
#
# HOST is an ssh destination with key-based login as the VM user (an admin account).
#
# What it does:
#   1. Refuses to touch this machine or anything that is not a VM.
#   2. Copies this machine's Xcode to the VM's /Applications if the VM has no Xcode with the
#      same version (the build insists on the Xcode the prebuilt dependencies were made with).
#   3. With sudo on the VM (asks for the password once): accepts the Xcode license, runs Xcode's
#      first-launch install, selects that Xcode, enables developer mode for debugging/testing,
#      disables system sleep, and installs Homebrew.
#   4. Downloads Xcode's Metal toolchain (for the shaders) and installs tmux with Homebrew (for
#      the tmux live harnesses).
#   5. Turns off the screen saver, crash-report dialogs and iTerm2's first-run update prompt, so
#      nothing stalls a run.
#   6. Makes `ssh localhost` work with a key on the VM (for tools/run_ssh_integration_live.sh).
#   7. Checks for a GUI login. Tests run as a LaunchAgent in the VM user's GUI session, so the
#      user must be logged in at the VM's console. Turning on automatic login keeps that true
#      across reboots; it asks for the user's password (sysadminctl).
#
# Code signing: tests build unsigned (as tools/run_tests.expect does by default), so the VM needs
# no certificates or keychain setup. SIGNED=1 runs are not supported on the VM.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30)

use_sudo=1
if [[ "${1:-}" == "--no-sudo" ]]; then
    use_sudo=0
    shift
fi
host="${1:-}"
if [[ -z "$host" ]]; then
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi

step() { echo ""; echo "==> $*"; }
rsh() { ssh -T "${SSH_OPTS[@]}" "$host" "$@"; }
# Runs a /bin/sh script on the VM regardless of the user's login shell.
rsh_sh() { rsh "/bin/sh -c $(printf %q "$1")"; }

step "Checking that $host is a VM and not this machine"
local_uuid="$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')"
info="$(rsh_sh 'ioreg -rd1 -c IOPlatformExpertDevice | awk -F\" "/IOPlatformUUID/{print \$4}"; sysctl -n kern.hv_vmm_present; hostname; sw_vers -productVersion; id -un')" || {
    echo "Cannot ssh to $host with a key: $info" >&2
    exit 1
}
remote_uuid="$(echo "$info" | sed -n 1p)"
if [[ "$remote_uuid" == "$local_uuid" ]]; then
    echo "Refusing: $host is this machine. Check its HostName in ~/.ssh/config." >&2
    exit 1
fi
if [[ "$(echo "$info" | sed -n 2p)" != "1" ]]; then
    echo "Refusing: $host is not a virtual machine." >&2
    exit 1
fi
remote_user="$(echo "$info" | sed -n 5p)"
echo "$host is $(echo "$info" | sed -n 3p), macOS $(echo "$info" | sed -n 4p), user $remote_user"

step "Xcode"
local_xcode="$(xcodebuild -version)"
local_developer_dir="$(xcode-select -p)"
local_xcode_app="${local_developer_dir%/Contents/Developer}"
find_xcode='for x in /Applications/Xcode*.app; do d="$x/Contents/Developer"; [ -d "$d" ] || continue; [ "$(DEVELOPER_DIR="$d" xcodebuild -version 2>/dev/null)" = "$WANT" ] && { echo "$x"; break; }; done'
remote_xcode_app="$(rsh "WANT=$(printf %q "$local_xcode") /bin/sh -c $(printf %q "$find_xcode")")"
if [[ -z "$remote_xcode_app" ]]; then
    name="$(basename "$local_xcode_app")"
    if rsh_sh "test -e /Applications/$name"; then
        name="Xcode-$(echo "$local_xcode" | awk '/Build version/{print $3}').app"
    fi
    echo "No $(echo "$local_xcode" | head -1) on $host. Copying $local_xcode_app to $host:/Applications/$name (about $(du -sh -A "$local_xcode_app" | cut -f1))."
    # Unpack into a staging directory and rename at the end so an interrupted copy is never
    # mistaken for a working Xcode.
    staging="/Applications/.xcode-copy-in-progress"
    rsh_sh "rm -rf $staging && mkdir $staging" || exit 1
    if ! tar -cf - -C "$(dirname "$local_xcode_app")" "$(basename "$local_xcode_app")" |
            rsh_sh "tar -xpf - -C $staging && mv $staging/$(basename "$local_xcode_app") /Applications/$name && rmdir $staging"; then
        echo "Copying Xcode failed." >&2
        exit 1
    fi
    remote_xcode_app="/Applications/$name"
fi
echo "Using $remote_xcode_app on $host"
developer_dir="$remote_xcode_app/Contents/Developer"

if [[ $use_sudo == 1 ]]; then
    step "Steps that need sudo on $host (enter $remote_user's password on the VM if asked)"
    sudo_script="
set -e
sudo -v
echo 'Accepting the Xcode license and running first launch'
sudo xcode-select -s '$developer_dir'
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
sudo DevToolsSecurity -enable
sudo dseditgroup -o edit -a '$remote_user' -t user _developer
echo 'Disabling sleep'
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
if [ ! -x /opt/homebrew/bin/brew ]; then
    echo 'Installing Homebrew'
    NONINTERACTIVE=1 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"
fi
"
    ssh -t "${SSH_OPTS[@]/BatchMode=yes/BatchMode=no}" "$host" "/bin/bash -c $(printf %q "$sudo_script")" || {
        echo "The sudo steps failed." >&2
        exit 1
    }
else
    step "Skipping sudo steps (--no-sudo)"
fi

step "Checking the Xcode license"
if rsh "DEVELOPER_DIR=$(printf %q "$developer_dir") xcodebuild -checkFirstLaunchStatus" >/dev/null 2>&1 &&
   rsh "DEVELOPER_DIR=$(printf %q "$developer_dir") xcrun --find swift" >/dev/null 2>&1; then
    echo "Xcode is ready."
else
    echo "Xcode still needs its license accepted / first launch. Rerun without --no-sudo." >&2
fi

step "Metal toolchain"
# The shaders need it, and Xcode no longer ships it. Downloading it needs no password.
if rsh "DEVELOPER_DIR=$(printf %q "$developer_dir") xcrun metal --version" >/dev/null 2>&1; then
    echo "Already installed."
else
    rsh "DEVELOPER_DIR=$(printf %q "$developer_dir") xcodebuild -downloadComponent MetalToolchain" ||
        echo "Could not download the Metal toolchain." >&2
fi

step "tmux"
if rsh_sh 'test -x /opt/homebrew/bin/brew'; then
    rsh_sh '/opt/homebrew/bin/tmux -V 2>/dev/null || /opt/homebrew/bin/brew install tmux'
else
    echo "No Homebrew yet; skipping tmux. Rerun without --no-sudo." >&2
fi

step "Screen saver, crash dialogs and first-run prompts"
# The test host is iTerm2 itself, with its preferences in the iterm2-tests suite (see
# ModernTests.xctestplan). On a fresh account Sparkle asks there whether to check for updates
# automatically, in a modal alert that nobody answers; while it is up, AppKit delivers no actions
# outside it, so tests that send menu actions or answer warnings fail.
rsh_sh 'defaults write iterm2-tests SUEnableAutomaticChecks -bool false
defaults write iterm2-tests SUSendProfileInfo -bool false
defaults -currentHost write com.apple.screensaver idleTime -int 0
defaults write com.apple.CrashReporter DialogType -string none
defaults write com.apple.dt.Xcode IDEDisableStateRestoration -bool YES
echo done'

step "ssh to localhost on the VM"
rsh_sh '
mkdir -p ~/.ssh && chmod 700 ~/.ssh
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -qF "$(cat ~/.ssh/id_ed25519.pub)" ~/.ssh/authorized_keys || cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
ssh-keyscan -t ed25519 localhost 2>/dev/null > ~/.ssh/known_hosts.localhost
grep -q "^localhost " ~/.ssh/known_hosts 2>/dev/null || cat ~/.ssh/known_hosts.localhost >> ~/.ssh/known_hosts
rm -f ~/.ssh/known_hosts.localhost
ssh -o BatchMode=yes localhost true && echo "ssh localhost works"'

step "GUI login"
console_user="$(rsh_sh 'stat -f %Su /dev/console')"
autologin="$(rsh_sh 'defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null')"
if [[ "$console_user" == "$remote_user" ]]; then
    echo "$remote_user is logged in to the GUI."
else
    echo "WARNING: $remote_user is not logged in to the VM's GUI (console user: $console_user). Log in at the VM's screen." >&2
fi
if [[ "$autologin" != "$remote_user" ]]; then
    echo "Automatic login is off, so a VM reboot leaves no GUI session for tests."
    if [[ $use_sudo == 1 ]]; then
        echo "Turning on automatic login for $remote_user (enter $remote_user's password when sysadminctl asks)."
        ssh -t "${SSH_OPTS[@]/BatchMode=yes/BatchMode=no}" "$host" "sudo sysadminctl -autologin set -userName $(printf %q "$remote_user") -password -" ||
            echo "Could not turn on automatic login. Do it in the VM: System Settings > Users & Groups > Automatically log in as." >&2
    fi
else
    echo "Automatic login is on for $remote_user."
fi

step "Done"
echo "Run tests with: tools/run_tests_vm.sh --host $host ModernTests/SomeTestClass"
