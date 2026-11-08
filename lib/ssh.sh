# shellcheck shell=bash
# Key-only SSH: the owner's public key, an sshd drop-in that turns off password logins, and Remote
# Login. Each part needs the one before it, so a failure stops the rest. The drop-in is checked
# with sshd -t and sshd -T before anything is enabled, and rolled back if either check fails.

MACSETUP_SSH_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../ssh" && pwd)"

_ssh_dir() { printf '%s\n' "${MACSETUP_SSH_DIR:-/etc/ssh}"; }
_ssh_dropin() { printf '%s/sshd_config.d/000-macsetup.conf\n' "$(_ssh_dir)"; }

# Stops a privileged part when there is no sudo, and says how to finish it.
_ssh_need_sudo() {
  [ -n "${MACSETUP_NO_SUDO:-}" ] || return 0
  skip_step "$1" "no sudo"
  manual_step "Run ~/.macsetup/install.sh at a terminal to finish: $1"
  return 1
}

_ssh_key_done() {
  local key="$HOME/.ssh/authorized_keys" body
  body="$(awk '{ print $2 }' "$MACSETUP_SSH_REPO_DIR/authorized_key.pub")"
  [ "$(stat -f %Lp "$HOME/.ssh" 2>/dev/null)" = "700" ] &&
    [ "$(stat -f %Lp "$key" 2>/dev/null)" = "600" ] &&
    awk -v b="$body" '$2 == b { found = 1 } END { exit !found }' "$key"
}

ssh_authorize_key() {
  local key="$HOME/.ssh/authorized_keys" pub="$MACSETUP_SSH_REPO_DIR/authorized_key.pub" body
  body="$(awk '{ print $2 }' "$pub")"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" || return 1
  touch "$key" && chmod 600 "$key" || return 1
  awk -v b="$body" '$2 == b { found = 1 } END { exit !found }' "$key" && return 0
  # A file without a final newline would otherwise have its last key joined to ours.
  if [ -s "$key" ] && [ -n "$(tail -c 1 "$key")" ]; then
    printf '\n' >> "$key" || return 1
  fi
  cat "$pub" >> "$key"
}

_ssh_hostkeys_done() { [ -e "$(_ssh_dir)/ssh_host_ed25519_key" ]; }

ssh_create_hostkeys() {
  _run_sudo "${MACSETUP_SSH_KEYGEN:-/usr/bin/ssh-keygen}" -A
}

# sshd -t must pass, and sshd -T must show both password settings off. Names are matched in any
# case: older OpenSSH prints them in lower case, macOS 27 prints them as written in the config.
_ssh_config_valid() {
  local sshd="${MACSETUP_SSHD:-/usr/sbin/sshd}" effective
  if ! _run_sudo "$sshd" -t; then
    printf 'sshd -t rejected the configuration\n' >&2
    return 1
  fi
  effective="$(_run_sudo "$sshd" -T)" || return 1
  if ! printf '%s\n' "$effective" | grep -qix 'passwordauthentication no' ||
    ! printf '%s\n' "$effective" | grep -qix 'kbdinteractiveauthentication no'; then
    printf 'sshd -T still allows password or keyboard-interactive login\n' >&2
    return 1
  fi
}

# Writes the drop-in, checks it, and puts back what was there before if the check fails. An
# unchanged drop-in is only checked. Backups are not kept beside it, as sshd would read them too.
ssh_install_dropin() {
  local dropin new="$MACSETUP_SSH_REPO_DIR/000-macsetup.conf" before="" status=0
  dropin="$(_ssh_dropin)"
  if [ -e "$dropin" ]; then
    before="$(mktemp)" || return 1
    cp "$dropin" "$before" || { rm -f "$before"; return 1; }
  fi
  _run_sudo mkdir -p "$(dirname "$dropin")" &&
    _run_sudo /usr/bin/install -m 644 "$new" "$dropin" &&
    _ssh_config_valid || status=1
  if [ "$status" -ne 0 ]; then
    if [ -n "$before" ]; then
      _run_sudo /usr/bin/install -m 644 "$before" "$dropin" ||
        printf 'Could not restore %s\n' "$dropin" >&2
    else
      _run_sudo rm -f "$dropin" || printf 'Could not remove %s\n' "$dropin" >&2
    fi
  fi
  [ -z "$before" ] || rm -f "$before"
  return "$status"
}

_ssh_dropin_same() { cmp -s "$MACSETUP_SSH_REPO_DIR/000-macsetup.conf" "$(_ssh_dropin)"; }

# Waits for port 22, as a service just started may not be listening yet.
_ssh_wait_port() {
  local n=0
  while [ "$n" -lt "${MACSETUP_PORT_WAIT:-5}" ]; do
    port_open 22 && return 0
    n=$((n + 1))
    [ "$n" -lt "${MACSETUP_PORT_WAIT:-5}" ] && sleep 1
  done
  return 1
}

# Tries launchctl, then systemsetup, which needs Full Disk Access. Only an open port counts.
ssh_enable() {
  local launchctl="${MACSETUP_LAUNCHCTL:-/bin/launchctl}"
  local label="Remote Login on, port 22 open"
  if port_open 22; then
    return 0
  fi
  _ssh_need_sudo "Turn on Remote Login" || return 0
  _run_sudo "$launchctl" enable system/com.openssh.sshd
  _run_sudo "$launchctl" bootstrap system /System/Library/LaunchDaemons/ssh.plist
  if _ssh_wait_port; then
    step "$label" true
    return 0
  fi
  _run_sudo "${MACSETUP_SYSTEMSETUP:-/usr/sbin/systemsetup}" -setremotelogin on
  if _ssh_wait_port; then
    step "$label" true
    return 0
  fi
  manual_step "Turn on Remote Login in System Settings > General > Sharing, then re-run install.sh"
  if is_interactive; then
    open "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
  fi
  return 0
}

ssh_step() {
  _ssh_key_done || step "Add your SSH key to ~/.ssh/authorized_keys" ssh_authorize_key || return 1
  if ! _ssh_hostkeys_done; then
    _ssh_need_sudo "Create SSH host keys" || return 0
    step "Create SSH host keys" ssh_create_hostkeys || return 1
  fi
  if _ssh_dropin_same; then
    # Checked when sudo allows, so a later change elsewhere in sshd's config is noticed.
    if [ -z "${MACSETUP_NO_SUDO:-}" ] && ! _ssh_config_valid; then
      record_failure "SSH key-only login: sshd's checks fail with the drop-in in place"
      return 1
    fi
  else
    _ssh_need_sudo "SSH key-only login" || return 0
    step "SSH key-only login" ssh_install_dropin || return 1
  fi
  ssh_enable
}
