#!/bin/bash
# Runs everything from the clone: apps, shell, macOS settings, then SSH and Screen Sharing. It is
# safe to re-run, and bootstrap.sh hands over to it. Exit codes: 0 all done, 1 something failed,
# 2 nothing failed but manual steps remain.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/apps.sh
source "$ROOT/lib/apps.sh"
# shellcheck source=lib/shell.sh
source "$ROOT/lib/shell.sh"
# shellcheck source=macos.sh
source "$ROOT/macos.sh"
if [ -f "$ROOT/lib/ssh.sh" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/lib/ssh.sh"
fi
if [ -f "$ROOT/lib/screensharing.sh" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/lib/screensharing.sh"
fi

usage() {
  printf 'Usage: install.sh [--all]\n'
  printf '  --all  Skip the picker and install everything not installed or declined.\n'
}

# Finds Homebrew by path and puts it on PATH, as a plain ssh command does not load ~/.zprofile.
load_brew() {
  local candidate old_ifs="$IFS"
  IFS=:
  for candidate in ${MACSETUP_BREW_PATHS-/opt/homebrew/bin/brew:/usr/local/bin/brew}; do
    if [ -x "$candidate" ]; then
      IFS="$old_ifs"
      eval "$("$candidate" shellenv)"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

# Later steps read MACSETUP_NO_SUDO to report what they could not do.
check_sudo() {
  [ -z "${MACSETUP_NO_SUDO:-}" ] || return 0
  if is_interactive; then
    if sudo -v; then
      (
        while kill -0 "$$" 2>/dev/null; do
          sudo -n true
          sleep 60
        done
      ) </dev/null >/dev/null 2>&1 &
      return 0
    fi
  elif sudo -n true 2>/dev/null; then
    return 0
  fi
  export MACSETUP_NO_SUDO=1
}

record_bootstrap_failures() {
  local failure old_ifs="$IFS"
  IFS=';'
  for failure in ${MACSETUP_BOOTSTRAP_FAILURES:-}; do
    record_failure "$failure"
  done
  IFS="$old_ifs"
}

# Sets MODE. Not printed for capture: in a command substitution stdout is a pipe, which would make
# is_interactive false.
set_mode() {
  if [ "$1" = "1" ]; then
    MODE=all
  elif [ -n "${MACSETUP_NO_PICKER:-}" ] || ! is_interactive; then
    MODE=defaults
  else
    MODE=pick
  fi
}

main() {
  local all=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1 ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        usage
        return 1
        ;;
    esac
    shift
  done

  record_bootstrap_failures
  check_sudo

  if load_brew; then
    set_mode "$all"
    apps_step "$ROOT/Brewfile" "$MODE"
  else
    record_failure "Homebrew not found, so no apps were installed. Run bootstrap.sh first."
  fi
  shell_step
  macos_step
  if declare -F ssh_step >/dev/null; then
    ssh_step
  fi
  if declare -F screensharing_step >/dev/null; then
    screensharing_step
  fi

  if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
    warn "$ROOT has uncommitted changes. Push them from a Mac holding your SSH key (see the README)."
  fi
  if [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ]; then
    warn "Terminal.app needs its font set to MesloLGS NF by hand to show icons. kitty works as it is."
  fi

  print_summary
}

main "$@"
exit $?
