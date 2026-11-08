#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  source "$REPO_ROOT/lib/common.sh"
  source "$REPO_ROOT/lib/apps.sh"
  export FAKE_BREW_INFO="$REPO_ROOT/tests/fixtures/brew_info.json"
  export MACSETUP_APPS_DIR="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$MACSETUP_APPS_DIR"
  BREWFILE="$BATS_TEST_TMPDIR/Brewfile"
}

# Prints column $1 of the classify_items row for token $2.
column_for() {
  printf '%s\n' "$output" | awk -F'\t' -v col="$1" -v token="$2" '$2 == token { print $col }'
}

count_items() {
  brewfile_items "$REPO_ROOT/Brewfile" | awk -F'\t' -v k="$1" -v t="$2" '$1 == k && $3 == t' | wc -l | tr -d ' '
}

@test "Brewfile matches the spec" {
  [ "$(count_items cask default)" -eq 8 ]
  [ "$(count_items cask optional)" -eq 15 ]
  [ "$(count_items brew default)" -eq 19 ]
  [ "$(count_items brew optional)" -eq 9 ]
}

@test "tiers from the spec" {
  run brewfile_items "$REPO_ROOT/Brewfile"
  [[ "$output" == *$'cask\tdocker-desktop\toptional'* ]]
  [[ "$output" == *$'cask\tzen\tdefault'* ]]
  [[ "$output" == *$'brew\tkubernetes-cli\tdefault'* ]]
  [[ "$output" == *$'brew\targocd\toptional'* ]]
}

@test "excluded items are absent" {
  local tokens item
  tokens="$(brewfile_items "$REPO_ROOT/Brewfile" | cut -f2)"
  for item in visual-studio-code cursor arc firefox microsoft-edge sourcetree diffmerge aldente \
    microsoft-word microsoft-excel microsoft-powerpoint microsoft-outlook microsoft-teams \
    microsoft-auto-update tunnelblick transmission freecad sweet-home3d minecraft android-studio \
    p4v temurin@21 fig rar moon influxdb-cli postgresql@16 proto ollama eksctl go glab maven \
    protobuf yadm python@3.10 gemini-cli sshpass orca raycast gum; do
    if printf '%s\n' "$tokens" | grep -qx -- "$item"; then
      echo "found excluded $item"
      return 1
    fi
  done
}

@test "brewfile_items ignores comments and blank lines" {
  printf '# a comment\n\ncask "vlc" # optional\nbrew "eza"\n' > "$BREWFILE"
  run brewfile_items "$BREWFILE"
  [ "$output" = $'cask\tvlc\toptional\nbrew\teza\tdefault' ]
}

@test "alias counts as installed" {
  printf 'brew "kubectl"\n' > "$BREWFILE"
  run classify_items "$BREWFILE"
  [ "$status" -eq 0 ]
  [ "$(column_for 4 kubectl)" = "brew" ]
}

@test "renamed cask counts as installed" {
  printf 'cask "docker"\n' > "$BREWFILE"
  run classify_items "$BREWFILE"
  [ "$status" -eq 0 ]
  [ "$(column_for 4 docker)" = "brew" ]
}

@test "app outside brew" {
  mkdir "$MACSETUP_APPS_DIR/Zen.app"
  printf 'cask "zen"\n' > "$BREWFILE"
  run classify_items "$BREWFILE"
  [ "$(column_for 4 zen)" = "outside" ]
}

@test "app installed under its target name counts as outside brew" {
  mkdir "$MACSETUP_APPS_DIR/Renamed.app"
  printf 'cask "renamed-app"\n' > "$BREWFILE"
  run classify_items "$BREWFILE"
  [ "$(column_for 4 renamed-app)" = "outside" ]
}

@test "missing" {
  printf 'cask "vlc" # optional\nbrew "eza"\n' > "$BREWFILE"
  run classify_items "$BREWFILE"
  [ "$status" -eq 0 ]
  [ "$(column_for 4 vlc)" = "missing" ]
  [ "$(column_for 3 vlc)" = "optional" ]
  [ "$(column_for 4 eza)" = "missing" ]
  [ "$(column_for 5 eza)" = "Modern ls" ]
}

@test "description with a tab or null" {
  printf 'cask "cli-cask"\ncask "no-desc"\n' > "$BREWFILE"
  run classify_items "$BREWFILE"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(column_for 4 cli-cask)" = "missing" ]
  [ "$(column_for 5 cli-cask)" = "has a tab and a newline" ]
  [ "$(column_for 4 no-desc)" = "missing" ]
  [ "$(column_for 5 no-desc)" = "" ]
}

@test "brew info failure" {
  printf 'cask "vlc"\n' > "$BREWFILE"
  FAKE_BREW_INFO_FAIL=1 run classify_items "$BREWFILE"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "token brew does not report fails rather than reading as missing" {
  printf 'cask "vlc"\ncask "not-in-the-response"\n' > "$BREWFILE"
  run classify_items "$BREWFILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not-in-the-response"* ]]
  [[ "$output" != *$'\t'* ]]
}

@test "brew info is called once per kind, with auto update off" {
  printf 'cask "vlc"\ncask "zen"\nbrew "eza"\n' > "$BREWFILE"
  run classify_items "$BREWFILE"
  [ "$(grep -c '^brew info' "$FAKE_LOG")" -eq 2 ]
  grep -q '^brew info --json=v2 --cask vlc zen$' "$FAKE_LOG"
  grep -q '^brew info --json=v2 --formula eza$' "$FAKE_LOG"
}

# --- Picker and install ---

picker_brewfile() {
  cat > "$BREWFILE" <<'LIST'
cask "zen"
cask "vlc" # optional
cask "docker-desktop" # optional
brew "eza"
brew "kubectl"
LIST
}

bundled() {
  cat "$FAKE_LOG.bundle" 2>/dev/null
}

declined_file() {
  printf '%s' "$HOME/.config/macsetup/declined"
}

@test "installed items are not offered" {
  picker_brewfile
  mkdir "$MACSETUP_APPS_DIR/VLC.app"
  run apps_step "$BREWFILE" pick
  [ "$status" -eq 0 ]
  ! cut -f2 "$FAKE_LOG.gum-input" | grep -qx 'kubectl'
  ! cut -f2 "$FAKE_LOG.gum-input" | grep -qx 'docker-desktop'
  ! cut -f2 "$FAKE_LOG.gum-input" | grep -qx 'vlc'
  [[ "$output" == *"kubectl"* ]]
  [[ "$output" == *"docker-desktop"* ]]
  [[ "$output" == *"vlc (outside brew)"* ]]
  [[ "$output" != *"kubectl (outside brew)"* ]]
}

@test "tier sets the start state" {
  picker_brewfile
  rm -f "$BREWFILE"
  printf 'cask "zen"\ncask "vlc" # optional\n' > "$BREWFILE"
  run apps_step "$BREWFILE" pick
  [ "$status" -eq 0 ]
  [ "$(bundled)" = 'cask "zen"' ]
}

@test "preselection survives a comma in the description" {
  printf 'cask "zen"\n' > "$BREWFILE"
  run apps_step "$BREWFILE" pick
  [ "$(bundled)" = 'cask "zen"' ]
  [ ! -s "$(declined_file)" ]
}

@test "unchecked default is recorded" {
  printf 'cask "zen"\nbrew "eza"\n' > "$BREWFILE"
  FAKE_GUM_PICK="eza" run apps_step "$BREWFILE" pick
  [ "$status" -eq 0 ]
  [ "$(cat "$(declined_file)")" = "zen" ]
  [ "$(bundled)" = 'brew "eza"' ]
}

@test "re-checked default is removed from the list" {
  printf 'cask "zen"\nbrew "eza"\n' > "$BREWFILE"
  declined_add zen
  declined_add eza
  FAKE_GUM_PICK="zen" run apps_step "$BREWFILE" pick
  [ "$(cat "$(declined_file)")" = "eza" ]
}

@test "declined_add does not repeat a token" {
  declined_add zen
  declined_add zen
  [ "$(cat "$(declined_file)")" = "zen" ]
  run declined_list
  [ "$output" = "zen" ]
}

@test "declined_remove leaves other tokens and handles a similar name" {
  declined_add zen
  declined_add zen-extra
  declined_remove zen
  [ "$(cat "$(declined_file)")" = "zen-extra" ]
}

@test "unchecked optional records nothing" {
  printf 'cask "vlc" # optional\nbrew "eza"\n' > "$BREWFILE"
  FAKE_GUM_PICK="eza" run apps_step "$BREWFILE" pick
  [ ! -s "$(declined_file)" ]
}

@test "declined default starts unchecked" {
  printf 'cask "zen"\nbrew "eza"\n' > "$BREWFILE"
  declined_add zen
  run apps_step "$BREWFILE" pick
  [ "$(bundled)" = 'brew "eza"' ]
  cut -f2 "$FAKE_LOG.gum-input" | grep -qx 'zen'
}

@test "nothing preselected passes no empty selection" {
  printf 'cask "vlc" # optional\n' > "$BREWFILE"
  run apps_step "$BREWFILE" pick
  ! grep -q -- '--selected' "$FAKE_LOG"
  [ ! -e "$FAKE_LOG.bundle" ]
}

@test "new Brewfile item starts by tier" {
  printf 'brew "eza"\n' > "$BREWFILE"
  declined_add some-old-item
  run apps_step "$BREWFILE" pick
  [ "$(bundled)" = 'brew "eza"' ]
}

@test "cancel records nothing" {
  printf 'cask "zen"\n' > "$BREWFILE"
  local code
  for code in 130 1; do
    FAKE_GUM_EXIT=$code apps_step "$BREWFILE" pick > /dev/null
    ! grep -q '^brew bundle' "$FAKE_LOG"
    [ ! -s "$(declined_file)" ]
  done
  run print_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped"* ]]
  [[ "$output" == *"Apps"* ]]
}

@test "nothing left" {
  printf 'cask "docker-desktop"\nbrew "kubectl"\n' > "$BREWFILE"
  run apps_step "$BREWFILE" pick
  [ "$status" -eq 0 ]
  ! grep -q '^gum' "$FAKE_LOG"
  ! grep -q '^brew bundle' "$FAKE_LOG"
  [[ "$output" == *"docker-desktop"* ]]
}

@test "only the selection is piped" {
  picker_brewfile
  FAKE_GUM_PICK="vlc eza" run apps_step "$BREWFILE" pick
  [ "$status" -eq 0 ]
  [ "$(bundled)" = $'cask "vlc" # optional\nbrew "eza"' ]
  grep -q '^brew bundle install --no-upgrade --file=-$' "$FAKE_LOG"
}

@test "empty selection installs nothing" {
  printf 'cask "vlc" # optional\n' > "$BREWFILE"
  FAKE_GUM_PICK="" run apps_step "$BREWFILE" pick
  [ "$status" -eq 0 ]
  ! grep -q '^brew bundle' "$FAKE_LOG"
}

@test "all mode" {
  picker_brewfile
  declined_add eza
  run apps_step "$BREWFILE" all
  [ "$status" -eq 0 ]
  ! grep -q '^gum' "$FAKE_LOG"
  [ "$(bundled)" = $'cask "zen"\ncask "vlc" # optional' ]
}

@test "defaults mode" {
  picker_brewfile
  declined_add eza
  run apps_step "$BREWFILE" defaults
  [ "$status" -eq 0 ]
  ! grep -q '^gum' "$FAKE_LOG"
  [ "$(bundled)" = 'cask "zen"' ]
}

@test "pick mode without gum falls back to defaults and says so" {
  printf 'cask "zen"\ncask "vlc" # optional\n' > "$BREWFILE"
  command() { [ "$2" = "gum" ] && return 1; builtin command "$@"; }
  apps_step "$BREWFILE" pick > /dev/null 2>&1
  unset -f command
  [ "$(bundled)" = 'cask "zen"' ]
  ! grep -q '^gum' "$FAKE_LOG"
  run print_summary
  [[ "$output" == *"gum"* ]]
}

@test "partial bundle failure reported" {
  printf 'cask "vlc"\ncask "zen"\n' > "$BREWFILE"
  FAKE_BUNDLE_FAIL=vlc apps_step "$BREWFILE" defaults > /dev/null 2>&1 || true
  run print_summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"vlc"* ]]
  [[ "$(printf '%s\n' "$output" | sed -n '/^FAILED/,$p')" != *"zen"* ]]
}

@test "bundle failure is the return value" {
  printf 'cask "vlc"\n' > "$BREWFILE"
  FAKE_BUNDLE_FAIL=vlc run apps_step "$BREWFILE" defaults
  [ "$status" -ne 0 ]
}

@test "list failure reports and offers nothing" {
  printf 'cask "vlc"\n' > "$BREWFILE"
  FAKE_BREW_INFO_FAIL=1 apps_step "$BREWFILE" pick > /dev/null 2>&1 || true
  ! grep -q '^gum' "$FAKE_LOG"
  run print_summary
  [ "$status" -eq 1 ]
}

# These use the real gum, because the install flow rests on how it treats --selected and cancel.
real_gum_run() {
  [ -x /opt/homebrew/bin/gum ] || skip "gum not installed"
  unset MACSETUP_NONINTERACTIVE
  export FAKE_GUM_REAL=1
  run "$REPO_ROOT/tests/in_pty.py" "source '$REPO_ROOT/lib/common.sh'; source '$REPO_ROOT/lib/apps.sh'; apps_step '$BREWFILE' pick" "$1"
}

@test "real gum: Enter keeps defaults, comma in description included" {
  printf 'cask "zen"\nbrew "eza"\ncask "vlc" # optional\n' > "$BREWFILE"
  real_gum_run '\r'
  [ "$status" -eq 0 ]
  [ "$(bundled)" = $'cask "zen"\nbrew "eza"' ]
  [ ! -s "$(declined_file)" ]
}

@test "real gum: Esc cancels" {
  printf 'cask "zen"\n' > "$BREWFILE"
  real_gum_run '\x1b'
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_LOG.bundle" ]
  [ ! -s "$(declined_file)" ]
}
