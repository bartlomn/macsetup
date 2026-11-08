# shellcheck shell=bash
# Screen Sharing: checks it is on and that only administrators may connect, and says what to do by
# hand when not. It never turns the service on itself: on macOS 27, starting it with launchctl
# opens port 5900 but without the screen capture and control permissions that only the switch in
# System Settings grants, so every viewer is refused, and nothing readable tells the two apart.

MACSETUP_SS_PANE="x-apple.systempreferences:com.apple.Sharing-Settings.extension"

# Prints the values of one attribute from dscl -read output, joining continuation lines.
_ss_values() {
  awk -v key="$1:" '
    $1 == key { on = 1; $1 = ""; print; next }
    /^ / && on { print; next }
    { on = 0 }' | tr -s ' \n' '  ' | sed 's/^ //; s/ $//'
}

# Returns 0 when only the admin group may connect, 1 when anyone else may, 2 when unreadable.
_ss_access() {
  local dscl="${MACSETUP_DSCL:-/usr/bin/dscl}" record admin status=0
  admin="$("$dscl" . -read /Groups/admin GeneratedUID 2>/dev/null | _ss_values GeneratedUID)"
  [ -n "$admin" ] || return 2
  record="$("$dscl" . -read /Groups/com.apple.access_screensharing GroupMembership GroupMembers \
    NestedGroups 2>/dev/null)" || status=$?
  # No access group at all means all users may connect.
  [ "$status" -eq 56 ] && return 1
  [ "$status" -eq 0 ] || return 2
  [ -z "$(_ss_values GroupMembership <<< "$record")" ] &&
    [ -z "$(_ss_values GroupMembers <<< "$record")" ] &&
    [ "$(_ss_values NestedGroups <<< "$record")" = "$admin" ] || return 1
}

screensharing_step() {
  local ok=1 access=0
  if ! port_open 5900; then
    manual_step "Turn on Screen Sharing in System Settings > General > Sharing, then re-run install.sh"
    ok=0
  fi
  _ss_access || access=$?
  case "$access" in
    1) manual_step "Allow only Administrators in System Settings > General > Sharing > Screen Sharing (i)" ;;
    2) manual_step "Check who may use Screen Sharing in System Settings > General > Sharing > Screen Sharing (i)" ;;
  esac
  [ "$access" -eq 0 ] || ok=0
  if [ "$ok" -eq 1 ]; then
    step "Screen Sharing: port open, not tested from another machine" true
  elif is_interactive; then
    open "$MACSETUP_SS_PANE"
  fi
  return 0
}
