# shellcheck shell=bash
# Step runner, end summary and small helpers shared by install.sh, macos.sh and lib/*.sh.
# Scripts do not use set -e: a failed step is recorded, and dependent work gates on step's status.

MACSETUP_OK=()
MACSETUP_FAILED=()
MACSETUP_SKIPPED=()
MACSETUP_MANUAL=()
MACSETUP_WARNINGS=()

# step <label> <command...>: runs a leaf operation, records it, and returns its status.
step() {
  local label="$1" status
  shift
  printf '==> %s\n' "$label"
  "$@"
  status=$?
  if [ "$status" -eq 0 ]; then
    MACSETUP_OK+=("$label")
  else
    MACSETUP_FAILED+=("$label")
    printf 'FAILED: %s\n' "$label" >&2
  fi
  return "$status"
}

record_failure() {
  MACSETUP_FAILED+=("$1")
  printf 'FAILED: %s\n' "$1" >&2
}

skip_step() {
  MACSETUP_SKIPPED+=("$1: $2")
  printf 'Skipped: %s: %s\n' "$1" "$2"
}

manual_step() {
  MACSETUP_MANUAL+=("$1")
}

warn() {
  MACSETUP_WARNINGS+=("$1")
  printf 'Warning: %s\n' "$1" >&2
}

_print_section() {
  local title="$1" item
  shift
  [ $# -gt 0 ] || return 0
  printf '\n%s:\n' "$title"
  for item in "$@"; do
    printf '  %s\n' "$item"
  done
}

# Prints the results. Returns 0 if all done, 1 if anything failed, 2 if only manual steps remain.
print_summary() {
  printf '\n===== Summary =====\n'
  _print_section "Done" ${MACSETUP_OK[@]+"${MACSETUP_OK[@]}"}
  _print_section "Skipped" ${MACSETUP_SKIPPED[@]+"${MACSETUP_SKIPPED[@]}"}
  _print_section "Warnings" ${MACSETUP_WARNINGS[@]+"${MACSETUP_WARNINGS[@]}"}
  _print_section "Do by hand" ${MACSETUP_MANUAL[@]+"${MACSETUP_MANUAL[@]}"}
  _print_section "FAILED" ${MACSETUP_FAILED[@]+"${MACSETUP_FAILED[@]}"}
  [ "${#MACSETUP_FAILED[@]}" -eq 0 ] || return 1
  [ "${#MACSETUP_MANUAL[@]}" -eq 0 ] || return 2
  return 0
}

# Moves a file, directory or symlink (the link itself) to a unique timestamped path.
timestamped_backup() {
  local path="${1%/}" base target n=1
  [ -e "$path" ] || [ -L "$path" ] || return 0
  base="$path.macsetup-bak-$(date +%Y%m%d-%H%M%S)"
  target="$base"
  while [ -e "$target" ] || [ -L "$target" ]; do
    target="$base-$n"
    n=$((n + 1))
  done
  mv "$path" "$target" || return 1
  printf 'Backed up %s to %s\n' "$path" "$target"
}

# Downloads to a temp file beside dest and moves it into place, so dest is only ever complete.
download_atomic() {
  local url="$1" dest="$2" tmp
  tmp="$(mktemp "$dest.tmp.XXXXXX")" || return 1
  if ! curl -fsSL "$url" -o "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! { chmod 644 "$tmp" && mv -f "$tmp" "$dest"; }; then
    rm -f "$tmp"
    return 1
  fi
}

port_open() {
  nc -z -G 2 localhost "$1" >/dev/null 2>&1
}

is_interactive() {
  [ -z "${MACSETUP_NONINTERACTIVE:-}" ] && [ -t 0 ] && [ -t 1 ]
}
