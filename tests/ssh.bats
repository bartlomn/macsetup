#!/usr/bin/env bats

load helper

KEY_BODY="$(awk '{ print $2 }' "$REPO_ROOT/ssh/authorized_key.pub")"

setup() {
  setup_sandbox
  export DROPIN="$MACSETUP_SSH_DIR/sshd_config.d/000-macsetup.conf"
  # macOS ships a drop-in of its own that sorts after ours.
  printf 'PasswordAuthentication yes\n' > "$MACSETUP_SSH_DIR/sshd_config.d/100-macos.conf"
}

SNIPPET="source '$REPO_ROOT/lib/common.sh'; source '$REPO_ROOT/lib/ssh.sh'; ssh_step; step after true; print_summary"

run_ssh() {
  run /bin/bash -c "$SNIPPET"
}

key_count() {
  grep -c "$KEY_BODY" "$HOME/.ssh/authorized_keys"
}

called() {
  grep -q "^$1" "$FAKE_LOG"
}

@test "key added once, other keys kept" {
  mkdir -m 700 "$HOME/.ssh"
  printf 'ssh-rsa AAAAother other@host\n' > "$HOME/.ssh/authorized_keys"
  run_ssh
  run_ssh
  [ "$(key_count)" -eq 1 ]
  grep -qxF 'ssh-rsa AAAAother other@host' "$HOME/.ssh/authorized_keys"
}

@test "permissions" {
  run_ssh
  [ "$(stat -f %Lp "$HOME/.ssh")" = "700" ]
  [ "$(stat -f %Lp "$HOME/.ssh/authorized_keys")" = "600" ]
}

@test "key file missing newline" {
  mkdir -m 700 "$HOME/.ssh"
  printf 'ssh-rsa AAAAother other@host' > "$HOME/.ssh/authorized_keys"
  run_ssh
  [ "$(sed -n 1p "$HOME/.ssh/authorized_keys")" = 'ssh-rsa AAAAother other@host' ]
  [ "$(sed -n 2p "$HOME/.ssh/authorized_keys")" = "$(cat "$REPO_ROOT/ssh/authorized_key.pub")" ]
}

@test "order" {
  run_ssh
  [ "$status" -eq 0 ]
  sequence="$(awk '
    /^ssh-keygen -A key=present/ { print "hostkeys" }
    /^sudo .*install .*000-macsetup.conf/ { print "dropin" }
    /^sshd -t/ { print "sshd-t" }
    /^sshd -T/ { print "sshd-T" }
    /^launchctl / { print "launchctl" }
    /^nc / { print "port" }' "$FAKE_LOG" | uniq | tr '\n' ' ')"
  [ "$sequence" = "hostkeys dropin sshd-t sshd-T port launchctl port " ]
  cmp "$DROPIN" "$REPO_ROOT/ssh/000-macsetup.conf"
  [[ "$output" == *"Remote Login on, port 22 open"* ]]
}

@test "effective values checked" {
  # Sorts before ours, so its value wins, as OpenSSH reads the first value.
  printf 'PasswordAuthentication yes\n' > "$MACSETUP_SSH_DIR/sshd_config.d/0-other.conf"
  run_ssh
  [ "$status" -eq 1 ]
  [ ! -e "$DROPIN" ]
  ! called launchctl || false
  [[ "$output" == *"FAILED:"*"SSH key-only login"* ]]
}

@test "new drop-in rolled back" {
  FAKE_SSHD_T_FAIL=1 run_ssh
  [ "$status" -eq 1 ]
  [ ! -e "$DROPIN" ]
  ! called launchctl || false
  ! called systemsetup || false
  [[ "$output" == *"FAILED:"*"SSH key-only login"* ]]
}

@test "existing drop-in restored" {
  printf 'PasswordAuthentication no\n# an earlier version\n' > "$DROPIN"
  cp "$DROPIN" "$BATS_TEST_TMPDIR/before"
  FAKE_OPEN_PORTS=22 FAKE_SSHD_T_FAIL=1 run_ssh
  [ "$status" -eq 1 ]
  cmp "$DROPIN" "$BATS_TEST_TMPDIR/before"
  ! called launchctl || false
  ! called systemsetup || false
}

@test "unchanged drop-in is not rewritten" {
  cp "$REPO_ROOT/ssh/000-macsetup.conf" "$DROPIN"
  FAKE_OPEN_PORTS=22 run_ssh
  [ "$status" -eq 0 ]
  ! grep -q 'install .*000-macsetup.conf' "$FAKE_LOG" || false
}

@test "second run changes nothing and stays quiet" {
  run_ssh
  : > "$FAKE_LOG"
  run_ssh
  [ "$status" -eq 0 ]
  ! called launchctl || false
  ! grep -q 'install ' "$FAKE_LOG" || false
  ! called 'ssh-keygen -A' || false
  [[ "$output" != *"authorized_keys"* ]]
}

@test "enable falls back to systemsetup" {
  FAKE_LAUNCHCTL_FAIL=1 run_ssh
  [ "$status" -eq 0 ]
  called 'systemsetup -setremotelogin on'
  [ "$(grep -n '^launchctl' "$FAKE_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n '^systemsetup' "$FAKE_LOG" | cut -d: -f1)" ]
  [[ "$output" == *"Remote Login on, port 22 open"* ]]
}

@test "port still closed is a manual step, not success" {
  FAKE_LAUNCHCTL_FAIL=1 FAKE_SYSTEMSETUP_FAIL=1 run_ssh
  [ "$status" -eq 2 ]
  [[ "$output" == *"Do by hand:"*"Remote Login"* ]]
  [[ "$output" != *"port 22 open"* ]]
  [[ "$output" != *"FAILED"* ]]
}

@test "no terminal: Sharing pane is not opened" {
  FAKE_LAUNCHCTL_FAIL=1 FAKE_SYSTEMSETUP_FAIL=1 run_ssh
  ! called open || false
}

@test "terminal: Sharing pane is opened when the port stays closed" {
  unset MACSETUP_NONINTERACTIVE
  FAKE_LAUNCHCTL_FAIL=1 FAKE_SYSTEMSETUP_FAIL=1 run "$REPO_ROOT/tests/in_pty.py" "$SNIPPET"
  [ "$status" -eq 2 ]
  called 'open x-apple.systempreferences:com.apple.Sharing-Settings.extension'
}

@test "host key failure stops enabling, later steps still run" {
  FAKE_SSH_KEYGEN_FAIL=1 run_ssh
  [ "$status" -eq 1 ]
  [ ! -e "$DROPIN" ]
  ! called launchctl || false
  ! called systemsetup || false
  [[ "$output" == *"FAILED:"*"Create SSH host keys"* ]]
  [[ "$output" == *"Done:"*"after"* ]]
}

@test "key failure stops everything privileged" {
  printf 'not a folder\n' > "$HOME/.ssh"
  run_ssh
  [ "$status" -eq 1 ]
  ! called 'ssh-keygen -A' || false
  [ ! -e "$DROPIN" ]
  ! called launchctl || false
  [[ "$output" == *"FAILED:"*"authorized_keys"* ]]
  [[ "$output" == *"Done:"*"after"* ]]
}

@test "no sudo: key added, privileged parts reported, nothing half-written" {
  MACSETUP_NO_SUDO=1 run_ssh
  [ "$status" -eq 2 ]
  [ "$(key_count)" -eq 1 ]
  ! called sudo || false
  [ ! -e "$DROPIN" ]
  [[ "$output" == *"Skipped:"*"no sudo"* ]]
  [[ "$output" == *"Do by hand:"*"install.sh"* ]]
}

@test "no sudo with SSH already set up is done" {
  run_ssh
  : > "$FAKE_LOG"
  MACSETUP_NO_SUDO=1 run_ssh
  [ "$status" -eq 0 ]
  ! called sudo || false
}

@test "sudo refused: drop-in not written, step failed" {
  FAKE_SUDO_FAIL=1 run_ssh
  [ "$status" -eq 1 ]
  [ ! -e "$DROPIN" ]
  ! called launchctl || false
}

@test "no sudo with only Remote Login missing is a manual step" {
  : > "$MACSETUP_SSH_DIR/ssh_host_ed25519_key"
  cp "$REPO_ROOT/ssh/000-macsetup.conf" "$DROPIN"
  MACSETUP_NO_SUDO=1 run_ssh
  [ "$status" -eq 2 ]
  ! called sudo || false
  ! called launchctl || false
  [[ "$output" == *"Do by hand:"*"Turn on Remote Login"* ]]
}

@test "sshd -T printing names in mixed case, as on macOS 27, is accepted" {
  FAKE_SSHD_T_MIXED_CASE=1 run_ssh
  [ "$status" -eq 0 ]
  cmp "$DROPIN" "$REPO_ROOT/ssh/000-macsetup.conf"
  [[ "$output" == *"Remote Login on, port 22 open"* ]]
}

@test "mixed case still catches password login left on" {
  printf 'PasswordAuthentication yes\n' > "$MACSETUP_SSH_DIR/sshd_config.d/0-other.conf"
  FAKE_SSHD_T_MIXED_CASE=1 run_ssh
  [ "$status" -eq 1 ]
  [ ! -e "$DROPIN" ]
}
