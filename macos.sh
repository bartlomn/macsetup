#!/bin/bash
# macOS settings. Runs alone, or install.sh sources it and calls macos_step. Every setting is read
# first, so a re-run changes nothing and restarts nothing. Firewall and FileVault are only reported.

# domain|key|type|value|process to restart
MACOS_DEFAULTS='
com.apple.dock|autohide|bool|true|Dock
com.apple.dock|magnification|bool|true|Dock
com.apple.dock|static-only|bool|true|Dock
com.apple.dock|showhidden|bool|true|Dock
com.apple.dock|mru-spaces|bool|false|Dock
com.apple.dock|tilesize|int|66|Dock
com.apple.dock|largesize|int|90|Dock
com.apple.finder|AppleShowAllFiles|bool|true|Finder
com.apple.finder|ShowPathbar|bool|true|Finder
com.apple.finder|ShowStatusBar|bool|true|Finder
com.apple.finder|_FXSortFoldersFirst|bool|true|Finder
com.apple.finder|FXPreferredViewStyle|string|clmv|Finder
com.apple.finder|FXDefaultSearchScope|string|SCcf|Finder
NSGlobalDomain|AppleShowAllExtensions|bool|true|Finder
NSGlobalDomain|NSAutomaticSpellingCorrectionEnabled|bool|false|
NSGlobalDomain|ApplePressAndHoldEnabled|bool|false|
NSGlobalDomain|KeyRepeat|int|2|
NSGlobalDomain|InitialKeyRepeat|int|15|
NSGlobalDomain|com.apple.mouse.tapBehavior|int|1|
com.apple.AppleMultitouchTrackpad|Clicking|bool|true|
com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|bool|true|
com.apple.desktopservices|DSDontWriteNetworkStores|bool|true|
com.apple.desktopservices|DSDontWriteUSBStores|bool|true|
'

_stored_form() {
  # defaults read prints bools as 1 and 0.
  case "$1|$2" in
    bool\|true) printf '1' ;;
    bool\|false) printf '0' ;;
    *) printf '%s' "$2" ;;
  esac
}

_apply_defaults() {
  local domain key type value restart restart_dock=0 restart_finder=0
  while IFS='|' read -r domain key type value restart; do
    [ -n "$domain" ] || continue
    [ "$(defaults read "$domain" "$key" 2>/dev/null)" = "$(_stored_form "$type" "$value")" ] && continue
    step "Set $domain $key" defaults write "$domain" "$key" "-$type" "$value" || continue
    [ "$restart" = "Dock" ] && restart_dock=1
    [ "$restart" = "Finder" ] && restart_finder=1
  done <<< "$MACOS_DEFAULTS"
  # killall only fails if the process is not running, as in an SSH session, with nothing to restart.
  [ "$restart_dock" = "1" ] && { killall Dock 2>/dev/null || true; }
  [ "$restart_finder" = "1" ] && { killall Finder 2>/dev/null || true; }
  return 0
}

_apply_dark_mode() {
  [ "$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null)" = "Dark" ] && return 0
  step "Turn on dark mode" osascript -e \
    'tell application "System Events" to tell appearance preferences to set dark mode to true' || true
}

_apply_library_visible() {
  [ -d "$HOME/Library" ] || return 0
  case "$(stat -f %Sf "$HOME/Library")" in
    *hidden*) step "Show ~/Library" chflags nohidden "$HOME/Library" || true ;;
  esac
}

# Reads a setting from pmset -g custom, ignoring the battery section. Headings may be absent.
_pmset_value() {
  pmset -g custom 2>/dev/null | awk -v key="$1" '
    BEGIN { active = 1 }
    /^[A-Za-z]/ { active = ($0 ~ /^AC Power/) ; next }
    active && $1 == key { print $2; exit }'
}

_run_sudo() {
  if is_interactive; then
    sudo "$@"
  else
    sudo -n "$@"
  fi
}

_set_power() {
  local label="$1"
  shift
  if [ -n "${MACSETUP_NO_SUDO:-}" ]; then
    skip_step "$label" "no sudo"
    manual_step "Run ~/.macsetup/install.sh at a terminal to finish: $label"
    return 0
  fi
  step "$label" _run_sudo pmset "$@" || true
}

_apply_power() {
  local caps changes=()
  caps="$(pmset -g cap 2>/dev/null)"
  [ "$(_pmset_value sleep)" = "0" ] || changes+=(sleep 0)
  if printf '%s\n' "$caps" | grep -qw womp; then
    [ "$(_pmset_value womp)" = "1" ] || changes+=(womp 1)
  fi
  if [ "${#changes[@]}" -gt 0 ]; then
    _set_power "Stay awake on power, with wake for network" -c "${changes[@]}"
  fi

  if ! printf '%s\n' "$caps" | grep -qw autorestart; then
    skip_step "Restart after power failure" "this Mac has no autorestart setting"
  elif [ "$(_pmset_value autorestart)" != "1" ]; then
    _set_power "Restart after power failure" -a autorestart 1
  fi
}

_report_security() {
  printf 'FileVault: %s\n' "$(fdesetup status 2>/dev/null | head -n 1)"
  printf 'Firewall: %s\n' "$("${MACSETUP_SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}" --getglobalstate 2>/dev/null | head -n 1)"
}

macos_step() {
  _apply_defaults
  _apply_dark_mode
  _apply_library_visible
  _apply_power
  _report_security
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/common.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
  macos_step
  print_summary
  exit $?
fi
