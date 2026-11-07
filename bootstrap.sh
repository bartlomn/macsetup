#!/bin/bash
# Entry point for a fresh Mac. Installs Homebrew and gum, clones the repo to ~/.macsetup, then
# hands over to install.sh. It stands alone, because nothing else from the repo exists yet.
#
# Run it with the one-liner in the README. The body is in main, called on the last line, so a
# partial download cannot run.

REPO_URL="${MACSETUP_REPO_URL:-https://github.com/bartlomn/macsetup.git}"
BRANCH="${MACSETUP_BRANCH:-main}"
BREW_PATHS="${MACSETUP_BREW_PATHS:-/opt/homebrew/bin/brew:/usr/local/bin/brew}"
BREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
TARGET="$HOME/.macsetup"

die() {
  printf 'bootstrap: %s\n' "$1" >&2
  exit 1
}

# Failures that must not stop bootstrap, passed on for install.sh to report.
add_failure() {
  MACSETUP_BOOTSTRAP_FAILURES="${MACSETUP_BOOTSTRAP_FAILURES:+$MACSETUP_BOOTSTRAP_FAILURES;}$1"
}

find_brew() {
  local candidate old_ifs="$IFS"
  IFS=:
  for candidate in $BREW_PATHS; do
    if [ -x "$candidate" ]; then
      IFS="$old_ifs"
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

# Refreshes the sudo credential until this process, which becomes install.sh, has gone.
keep_sudo_alive() {
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -n true
      sleep 60
    done
  ) </dev/null >/dev/null 2>&1 &
}

check_sudo() {
  local brew_missing="$1"
  if [ -t 0 ] && [ -t 1 ] && [ -z "${MACSETUP_NONINTERACTIVE:-}" ]; then
    if sudo -v; then
      keep_sudo_alive
      return 0
    fi
    [ "$brew_missing" = "0" ] || die "sudo failed, and Homebrew cannot be installed without it."
  else
    [ "$brew_missing" = "0" ] || die "Homebrew is missing and there is no terminal to install it from."
    sudo -n true 2>/dev/null && return 0
  fi
  export MACSETUP_NO_SUDO=1
  printf 'bootstrap: continuing without sudo; steps that need it will be reported.\n' >&2
}

install_brew() {
  local installer
  installer="$(mktemp)" || die "could not create a temp file."
  curl -fsSL "$BREW_INSTALLER_URL" -o "$installer" || die "could not download the Homebrew installer."
  NONINTERACTIVE=1 /bin/bash "$installer" || die "the Homebrew installer failed."
  rm -f "$installer"
}

# Adds the brew shellenv line to ~/.zprofile once, so Homebrew is on PATH in login shells.
add_to_zprofile() {
  local brew="$1" profile="$HOME/.zprofile" line
  line="eval \"\$($brew shellenv)\""
  grep -qF "$line" "$profile" 2>/dev/null && return 0
  if [ -s "$profile" ] && [ -n "$(tail -c 1 "$profile" 2>/dev/null)" ]; then
    printf '\n' >> "$profile" 2>/dev/null || return 1
  fi
  printf '%s\n' "$line" >> "$profile" 2>/dev/null
}

install_gum() {
  local brew="$1"
  "$brew" list gum >/dev/null 2>&1 && return 0
  if ! "$brew" install gum; then
    export MACSETUP_NO_PICKER=1
    add_failure "gum install"
  fi
}

# Reduces https and SSH forms of a remote to one form, as the owner may switch the clone to SSH.
normalize_remote() {
  local url="$1"
  url="${url#https://}"
  url="${url#ssh://}"
  url="${url#git@}"
  url="${url/github.com:/github.com/}"
  printf '%s\n' "${url%.git}"
}

is_our_clone() {
  local toplevel remote
  toplevel="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ "$(cd "$toplevel" && pwd -P)" = "$(cd "$TARGET" && pwd -P)" ] || return 1
  remote="$(git -C "$TARGET" remote get-url origin 2>/dev/null)" || return 1
  [ "$(normalize_remote "$remote")" = "$(normalize_remote "$REPO_URL")" ]
}

move_aside() {
  local base target n=1
  base="$TARGET.macsetup-bak-$(date +%Y%m%d-%H%M%S)"
  target="$base"
  while [ -e "$target" ] || [ -L "$target" ]; do
    target="$base-$n"
    n=$((n + 1))
  done
  mv "$TARGET" "$target" || die "could not move $TARGET aside."
  printf 'bootstrap: moved the existing %s to %s\n' "$TARGET" "$target"
}

# Clones beside the target and moves into place, so an interrupted clone blocks nothing.
fresh_clone() {
  local tmp
  tmp="$(mktemp -d "$TARGET.tmp.XXXXXX")" || die "could not create a temp directory."
  if ! git clone --branch "$BRANCH" "$REPO_URL" "$tmp/repo"; then
    rm -rf "$tmp"
    die "could not clone $REPO_URL."
  fi
  mv "$tmp/repo" "$TARGET" || die "could not move the clone to $TARGET."
  rm -rf "$tmp"
}

get_repo() {
  if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    fresh_clone
  elif ! is_our_clone; then
    move_aside
    fresh_clone
  elif [ -n "$(git -C "$TARGET" status --porcelain)" ]; then
    printf 'bootstrap: %s has uncommitted changes, so not pulling; using the local copy.\n' "$TARGET" >&2
  elif ! git -C "$TARGET" pull --ff-only; then
    printf 'bootstrap: could not update %s; using the local copy.\n' "$TARGET" >&2
    add_failure "repo update"
  fi
}

main() {
  local brew brew_missing=0

  id -Gn | grep -qw admin || die "this account is not an administrator. Use an administrator account."

  brew="$(find_brew)" || brew_missing=1
  check_sudo "$brew_missing"

  if [ "$brew_missing" = "1" ]; then
    install_brew
    brew="$(find_brew)" || die "the Homebrew installer finished, but brew was not found."
  fi
  eval "$("$brew" shellenv)"
  add_to_zprofile "$brew" || add_failure "zprofile"

  install_gum "$brew"
  get_repo

  export MACSETUP_BOOTSTRAP_FAILURES
  exec /bin/bash "$TARGET/install.sh" "$@"
}

main "$@"
