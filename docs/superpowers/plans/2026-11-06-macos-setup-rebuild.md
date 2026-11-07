# macOS Setup Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `setup.sh` with a re-runnable setup that takes a freshly wiped Mac mini to usable with one command, then adds key-only SSH and Screen Sharing.

**Architecture:** A standalone `bootstrap.sh` installs Homebrew and clones the repo to `~/.macsetup`, then hands over to `install.sh`, which runs independent steps from `lib/` through a shared step runner that records results and prints an end summary. `Brewfile` is the source of truth for apps, and `zsh/zshrc.zsh` is the real shell config behind a stub `~/.zshrc`.

**Tech Stack:** Bash 3.2 (`/bin/bash` on macOS), Homebrew and `brew bundle`, `gum`, `/usr/bin/python3` for JSON, zsh with Oh My Zsh and Powerlevel10k. Development only: `bats-core`, `shellcheck`.

**Spec:** `docs/superpowers/specs/2026-11-06-macos-setup-rebuild-design.md`

## Global Constraints

- Every script must run on `/bin/bash` 3.2: no associative arrays, `mapfile`, `${var,,}`, or `&>>`.
- The script never uninstalls anything, never changes Firewall or FileVault settings, and never deletes the owner's files. Anything replaced is first moved to a timestamped backup.
- The repo is public: no secrets, tokens, private keys, or work-specific values.
- Exit codes: `0` all done; `1` something failed; `2` nothing failed but manual steps remain.
- A failed step never reads as success; one failed step does not stop unrelated steps.
- Never run `brew upgrade`. Install only through `brew bundle install --no-upgrade --file=-`.
- **Do not run these scripts for real on the owner's MacBook.** On it, run only `tests/` (sandboxed `HOME`, fake commands) and the read-only shell check in Task 5. Real runs happen on the Mac mini.
- Commit to `rebuild-mac-setup`. Push only when the owner agrees (Task 9).
- The owner runs anything needing `sudo` on the mini during acceptance. No passwordless `sudo`.

## Review Focus

- The owner cancels the picker (Esc or Ctrl-C): nothing is installed, nothing is recorded as declined, and the step reports "skipped". Pinned in Task 4.
- A `Brewfile` name differs from what Homebrew reports (`kubectl` versus `kubernetes-cli`, renamed casks): an installed item must not appear as missing. Pinned in Task 3.
- `install.sh` runs where Homebrew is not on `PATH` (a plain `ssh host ~/.macsetup/install.sh`): it finds Homebrew and installs only defaults. Pinned in Task 8.
- `sudo` is unavailable or expires mid-run: privileged steps report failed or skipped, and non-privileged steps still run. Pinned in Tasks 7 and 10.
- `~/.p10k.zsh` or `~/.zshrc` is a dangling symlink or a link to somewhere else: it is backed up, not followed or overwritten. Pinned in Task 6.

---

## File Structure

```text
bootstrap.sh              Entry point; self-contained
install.sh                Parses flags, runs all steps, prints the summary
Brewfile                  Apps and CLI tools; `# optional` marks the optional tier
macos.sh                  Standalone macOS settings
lib/common.sh             Step runner, summary, backups, atomic download, port check
lib/apps.sh               Brewfile parsing, classification, declined list, picker, install
lib/item_info.py          Turns `brew info --json=v2` into tab-separated rows
lib/shell.sh              Stub, p10k link, Oh My Zsh, theme, plugins, fonts
lib/ssh.sh                authorized_keys, sshd drop-in, Remote Login
lib/screensharing.sh      Screen Sharing
zsh/zshrc.zsh             Real shell config
p10k.zsh                  Prompt config
ssh/authorized_key.pub    The owner's public key
ssh/000-macsetup.conf     sshd drop-in
tests/helper.bash         Sandbox and fake-command helpers
tests/fakes/              Fake brew, gum, sudo, defaults, killall, curl, sshd, launchctl, ...
tests/*.bats              Tests
tests/zsh_startup.py      Real zsh startup check in a pty
```

---

### Task 1: Test harness and step runner

**Files:**
- Create: `lib/common.sh`, `tests/helper.bash`, `tests/fakes/`, `tests/common.bats`

**Interfaces:**
- Produces:
  - `step <label> <command...>`: runs the command, records ok or failed, and returns the command's status. Scripts do not use `set -e`, so a failure never stops the run on its own. Dependent work gates on the return value: `step "a" do_a && step "b" do_b`.
  - `step` wraps leaf operations only. Composite functions (`apps_step`, `shell_step`, `ssh_step`, `screensharing_step`) are called directly, so each failure and manual result is recorded once under its own label, and no parent is ever marked ok over a failed child.
  - `record_failure <label>`: records a failure that happened outside `step`.
  - `skip_step <label> <reason>`, `manual_step <text>`, `warn <text>`: record for the summary.
  - `print_summary`: prints the results and returns 0, 1 or 2 per Global Constraints.
  - `timestamped_backup <path>`: moves a file, directory or symlink to a unique `<path>.macsetup-bak-<timestamp>[-n]`.
  - `download_atomic <url> <dest>`: `curl -fsSL` to a temp file in the destination's directory, then `mv`.
  - `port_open <port>`: returns 0 if `nc -z -G 2 localhost <port>` succeeds.
  - `is_interactive`: true if stdin and stdout are terminals, and `MACSETUP_NONINTERACTIVE` is unset.
  - `setup_sandbox`: test helper that sets a temp `HOME`, prepends `tests/fakes` to `PATH`, and sets `FAKE_LOG`. Fakes append their arguments to `FAKE_LOG` and take behaviour from `FAKE_*` variables.

- [ ] **Step 1:** On the MacBook, with the owner's agreement, run `brew install bats-core shellcheck`.
- [ ] **Step 2: Write the failing tests** in `tests/common.bats`:
  - `step records failure and continues`: a failing `step` then a passing one both run, and `print_summary` returns 1 with the failed label in its output.
  - `step returns the status`: `step "a" false && step "b" true` never runs `b`, and `b` is absent from the summary.
  - `manual step alone exits 2`, `all ok exits 0`.
  - `failure beats manual`: both present returns 1.
  - `backup never collides`: two backups of the same path in the same second produce two distinct files, both preserved.
  - `backup moves a dangling symlink`: the link itself is moved.
  - `download failure leaves dest untouched`: with `FAKE_CURL_FAIL=1`, an existing dest keeps its content, no temp file remains, and the return is non-zero.
- [ ] **Step 3:** Run `bats tests/common.bats`. Expected: FAIL (functions undefined).
- [ ] **Step 4:** Implement `lib/common.sh`, with results held in plain indexed arrays.
- [ ] **Step 5:** Run `bats tests/common.bats && shellcheck lib/common.sh`. Expected: PASS.
- [ ] **Step 6:** Commit: `feat: add step runner and test harness`.

### Task 2: Bootstrap

**Files:**
- Create: `bootstrap.sh`, `tests/bootstrap.bats`

**Interfaces:**
- Consumes: nothing from the repo. It must stand alone, so it duplicates the little it needs.
- Produces: `~/.macsetup`; a `~/.zprofile` containing the `brew shellenv` line once; if `gum` failed, `MACSETUP_NO_PICKER=1` and `MACSETUP_BOOTSTRAP_FAILURES="gum install"` exported to `install.sh`, which records each as a failure so the final exit is 1. If `sudo` failed but Homebrew exists, `MACSETUP_NO_SUDO=1` is exported, and bootstrap continues.
- Environment for tests and branch runs: `MACSETUP_REPO_URL`, `MACSETUP_BRANCH` (default `main`), `MACSETUP_BREW_PATHS` (default `/opt/homebrew/bin/brew:/usr/local/bin/brew`).

- [ ] **Step 1: Write the failing tests** in `tests/bootstrap.bats`, with `MACSETUP_REPO_URL` pointing at a local bare git repo and `install.sh` in it logging its arguments:
  - `non-admin stops`: fake `id -Gn` without `admin` exits non-zero and installs nothing.
  - `no terminal and no brew stops`: exits non-zero with a clear message.
  - `no terminal with brew continues`: reaches the handover.
  - `brew install failure stops`: `FAKE_BREW_INSTALL_FAIL=1` exits non-zero, with no clone and no handover.
  - `gum failure continues`: the handover happens with `MACSETUP_NO_PICKER=1` and `MACSETUP_BOOTSTRAP_FAILURES` set.
  - `sudo failure, brew missing, stops`: `FAKE_SUDO_FAIL=1` exits non-zero and installs nothing.
  - `sudo failure, brew present, continues`: the handover happens with `MACSETUP_NO_SUDO=1`.
  - `fresh clone`: `~/.macsetup` is a valid clone, and no temp clone remains.
  - `branch is honoured`: `MACSETUP_BRANCH=foo` clones `foo`.
  - `clone failure stops`: a bad URL exits non-zero with no handover and no `~/.macsetup`.
  - `re-run pulls`: a new upstream commit appears in the clone.
  - `uncommitted changes skip the pull`: local edits survive, the handover still happens, and a warning is printed.
  - `invalid clone moved aside`: an existing non-git `~/.macsetup` with a file in it is at a timestamped path with the file intact, and a fresh clone is in place.
  - `different repo moved aside`: a valid clone of another remote is treated the same way.
  - `zprofile line added once`: two runs leave one `brew shellenv` line.
  - `truncated script does nothing`: running only the first half of the file performs no action.
  - `one-liner fails on bad URL`: the one-liner from the spec, with `FAKE_CURL_FAIL=1`, exits non-zero and runs nothing.
- [ ] **Step 2:** Run `bats tests/bootstrap.bats`. Expected: FAIL.
- [ ] **Step 3:** Implement `bootstrap.sh` in the spec's order: admin check, then `sudo -v` with keep-alive if interactive, then Homebrew (installer downloaded to a temp file, run with `NONINTERACTIVE=1`), `brew shellenv` for this process and `~/.zprofile`, `gum`, clone or pull, `exec` `install.sh` passing all arguments. Wrap the body in `main` and call `main "$@"` on the last line. A `sudo` failure stops bootstrap only if Homebrew is missing.
- [ ] **Step 4:** Run `bats tests/bootstrap.bats && shellcheck bootstrap.sh`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: add bootstrap`.

### Task 3: Brewfile and classification

**Files:**
- Create: `Brewfile`, `lib/apps.sh` (first part), `lib/item_info.py`, `tests/fixtures/brew_info.json`, `tests/apps.bats`

**Interfaces:**
- Produces:
  - `Brewfile` lines such as `cask "vlc" # optional`, using the spec's lists exactly, with `brew "kubernetes-cli"` for `kubectl`.
  - `brewfile_items <file>`: prints `kind<TAB>token<TAB>tier` (`brew` or `cask`; `default` or `optional`).
  - `item_info.py` reads the JSON on stdin and prints `kind<TAB>name<TAB>aliases-and-old-names(comma)<TAB>installed(0/1)<TAB>app-paths(colon)<TAB>desc`.
  - `classify_items <file>`: prints `kind<TAB>token<TAB>tier<TAB>state<TAB>desc`, where state is `brew`, `outside` or `missing`. `outside` means a cask is not installed by Homebrew but one of its apps exists under `MACSETUP_APPS_DIR` (default `/Applications`).

- [ ] **Step 1: Write the failing tests** in `tests/apps.bats`:
  - `Brewfile matches the spec`: exact counts of 9 default casks, 14 optional casks, 20 default formulae, 9 optional formulae.
  - `excluded items are absent`: `sshpass`, `gemini-cli`, `arc`, `cursor`, `visual-studio-code`, `orca` and the rest of the spec's exclusions.
  - `alias counts as installed`: fixture with `kubernetes-cli` installed and alias `kubectl`; a Brewfile line of `brew "kubectl"` classifies as `brew`.
  - `renamed cask counts as installed`: fixture where `docker-desktop` has old token `docker`; `cask "docker"` classifies as `brew`.
  - `app outside brew`: `Zen.app` present under `MACSETUP_APPS_DIR` and `installed` empty gives `outside`.
  - `missing`: neither gives `missing`.
  - `description with a tab or null`: does not break the columns.
  - `brew info failure`: `classify_items` returns non-zero and prints no rows, rather than classifying everything as missing.
- [ ] **Step 2:** Run `bats tests/apps.bats`. Expected: FAIL.
- [ ] **Step 3:** Implement. Call `brew info --json=v2 --formula` and `--cask` once for the whole list, not per item. Set `HOMEBREW_NO_AUTO_UPDATE=1`.
- [ ] **Step 4:** Run `bats tests/apps.bats && shellcheck lib/apps.sh`. Expected: PASS. Also run `brew info --json=v2` against the real `Brewfile` tokens on the MacBook (read-only) and confirm each resolves and none is disabled.
- [ ] **Step 5:** Commit: `feat: add Brewfile and item classification`.

### Task 4: Picker and app install

**Files:**
- Modify: `lib/apps.sh`, `tests/apps.bats`

**Interfaces:**
- Consumes: `classify_items`, `step`, `skip_step`, `warn`, `is_interactive`.
- Produces:
  - `declined_list`, `declined_add <token>`, `declined_remove <token>`, on `~/.config/macsetup/declined`.
  - `apps_step <brewfile> <mode>`, where mode is `pick`, `all` or `defaults`. It prints the read-only list, gets the selection, and installs it.

- [ ] **Step 1:** Run `gum choose --help` for the version in `Brewfile` (install `gum` on the MacBook if the owner agrees) and confirm the flags for multi-select, preselected items, a header, and separating a visible label from the returned value. Note the chosen flags in a comment in `lib/apps.sh`. If labels and values can't be separated, match on the first column of the returned line.
- [ ] **Step 2: Write the failing tests:**
  - `installed items are not offered`: a `brew` or `outside` item is absent from fake `gum`'s input and present in the printed list, with `outside brew` next to the second kind.
  - `tier sets the start state`: defaults are preselected, and optional items are not.
  - `unchecked default is recorded`; `re-checked default is removed from the list`.
  - `unchecked optional records nothing`.
  - `declined default starts unchecked`.
  - `new Brewfile item starts by tier`.
  - `cancel records nothing`: `FAKE_GUM_EXIT=130` means no `brew bundle` call, an unchanged declined file, and a "skipped" result.
  - `nothing left`: all installed means `gum` is not called and the list is printed.
  - `only the selection is piped`: fake `brew` receives exactly the chosen `Brewfile` lines on stdin, with args `bundle install --no-upgrade --file=-`.
  - `all mode`: every missing item except declined ones, with no `gum` call.
  - `defaults mode`: only missing, non-declined defaults, with no `gum` call.
  - `partial bundle failure reported`: `FAKE_BUNDLE_FAIL=vlc` makes the step fail, and the summary names `vlc`, found by re-classifying the selection afterwards.
- [ ] **Step 2b:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `bats tests/apps.bats && shellcheck lib/apps.sh`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: add app picker and install`.

### Task 5: Shell config files

**Files:**
- Create: `zsh/zshrc.zsh`, `p10k.zsh`, `tests/zsh_startup.py`

**Interfaces:**
- Produces: `~/.macsetup/zsh/zshrc.zsh`, ordered as in the spec.

- [ ] **Step 1:** Read the owner's real `~/.zshrc` and `~/.p10k.zsh`. List for the owner every line not carried over (secrets, machine paths, work values, unused template comments) and where it should go, and get agreement before writing. Do not paste values into the plan, chat, or commit messages if they look secret.
- [ ] **Step 2:** Write `zsh/zshrc.zsh` in the spec's six-step order. Add `plugins` entries for tools that may be absent only if the command exists (`direnv`, `kubectl`, `helm`, `aws`, `docker`). Wrap `fnm env` and the `eza` alias in command checks. If `brew` isn't on `PATH`, run `brew shellenv` from the first existing path in `MACSETUP_BREW_PATHS` (default `/opt/homebrew/bin/brew:/usr/local/bin/brew`), which lets the test hide Homebrew without uninstalling anything. Copy `p10k.zsh` from the real file.
- [ ] **Step 3:** Write `tests/zsh_startup.py <repo> <mode>`: builds a temp `HOME` with `.macsetup` linked to the repo and `.oh-my-zsh` and `.p10k.zsh` linked, plus the stub `.zshrc`, with temp cache and history. It opens a real pty and asserts on the output. Modes:
  - `full`: `ZSH_THEME` and the `eza` alias are correct; no instant prompt warning; no `command not found`.
  - `delay`: with a 3-second delay injected after instant prompt on the second run, first output arrives in under 1 second.
  - `no-tools`: `PATH` is `/usr/bin:/bin`, `MACSETUP_BREW_PATHS` is empty, and `HOMEBREW_*` is unset, so `fnm` and `eza` are unavailable. Asserts: no errors; `ls` is not aliased to `eza` and works; no `fnm` hook is defined; the conditional plugins are absent from `plugins`.
  - `no-omz`: `.oh-my-zsh` is absent, and the shell still starts with a clear message and no errors.
- [ ] **Step 4:** Run all four modes on the MacBook. This uses the existing Oh My Zsh read-only and touches only the temp `HOME`. Expected: PASS. Fix `no-omz` by guarding `source $ZSH/oh-my-zsh.sh`.
- [ ] **Step 5:** Scan: `gitleaks`-style regex for tokens and keys across `zsh/` and `p10k.zsh`, expecting nothing; have the owner read the final `zsh/zshrc.zsh` diff.
- [ ] **Step 6:** Commit: `feat: add shell config`.

### Task 6: Shell setup step

**Files:**
- Create: `lib/shell.sh`, `tests/shell.bats`

**Interfaces:**
- Consumes: `timestamped_backup`, `download_atomic`, `step`.
- Produces: `shell_write_stub`, `shell_link_p10k`, `shell_install_omz`, `shell_install_theme`, `shell_install_plugins`, `shell_install_fonts`, and `shell_step`, which runs them in that order through `step`.

- [ ] **Step 1: Write the failing tests:**
  - `stub written when absent`, with the spec's exact two lines.
  - `stub replaces template with backup`: the old file is in a timestamped backup with its content intact.
  - `stub present is left alone`: a file with the stub line and machine-specific lines below is unchanged, byte for byte.
  - `stub survives a dangling symlink`: the link is moved aside, and a regular file is written.
  - `p10k link created`; `p10k link idempotent`: a second run creates no backup.
  - `p10k other file backed up`; `p10k dangling or foreign link backed up`.
  - `omz valid skipped`: valid clone with `oh-my-zsh.sh` means no installer call.
  - `omz partial moved aside`: a directory without `oh-my-zsh.sh` is moved to a timestamped path, and the installer runs with `--unattended --keep-zshrc`.
  - `stub written before omz`: order in `FAKE_LOG`.
  - `theme interrupted`: a failed clone leaves no theme directory and no temp directory, and the next run succeeds.
  - `each plugin checked alone`: one plugin present, the other still installed.
  - `font names and curl -f`: four files named `MesloLGS NF Regular.ttf`, `Bold`, `Italic`, `Bold Italic`.
  - `font failure leaves no file`: `FAKE_CURL_FAIL=1` means no `.ttf`, the step fails, and other fonts are still tried.
  - `omz failure is reported`, and other steps still run.
- [ ] **Step 2:** Run `bats tests/shell.bats`. Expected: FAIL.
- [ ] **Step 3:** Implement. Theme and plugins clone to a temp directory beside the target, then `mv`. Fonts go in `MACSETUP_FONTS_DIR`, default `/Library/Fonts`.
- [ ] **Step 4:** Run `bats tests/shell.bats && shellcheck lib/shell.sh`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: add shell setup step`.

### Task 7: macOS settings

**Files:**
- Create: `macos.sh`, `tests/macos.bats`

**Interfaces:**
- Consumes: `step`, `warn`, `print_summary`.
- Produces: `macos.sh`, runnable alone or called by `install.sh`. All values sit in one table at the top: `domain|key|type|value|restart-target`.

Values, from the spec:

| Domain | Key | Value |
|---|---|---|
| `com.apple.dock` | `autohide`, `magnification`, `static-only`, `showhidden` | `true` |
| `com.apple.dock` | `mru-spaces` | `false` |
| `com.apple.dock` | `tilesize` / `largesize` | `66` / `90` |
| `com.apple.finder` | `AppleShowAllFiles`, `ShowPathbar`, `ShowStatusBar`, `_FXSortFoldersFirst` | `true` |
| `com.apple.finder` | `FXPreferredViewStyle` / `FXDefaultSearchScope` | `clmv` / `SCcf` |
| `NSGlobalDomain` | `AppleShowAllExtensions` | `true` |
| `NSGlobalDomain` | `NSAutomaticSpellingCorrectionEnabled`, `ApplePressAndHoldEnabled` | `false` |
| `NSGlobalDomain` | `KeyRepeat` / `InitialKeyRepeat` | `2` / `15` |
| `NSGlobalDomain` | `com.apple.mouse.tapBehavior` | `1` |
| `com.apple.AppleMultitouchTrackpad`, `com.apple.driver.AppleBluetoothMultitouch.trackpad` | `Clicking` | `true` |
| `com.apple.desktopservices` | `DSDontWriteNetworkStores`, `DSDontWriteUSBStores` | `true` |

Also: dark mode through `osascript`, read first and only set if different; `chflags nohidden ~/Library`; and with `sudo`: `pmset -c sleep 0 womp 1` and `pmset -a autorestart 1`.

- [ ] **Step 1: Write the failing tests** with fake `defaults`, `killall`, `osascript`, `pmset`, `sudo`, `fdesetup`, and `socketfilterfw` (path through `MACSETUP_SOCKETFILTERFW`):
  - `first run writes and restarts`: every table row is written, and `killall Dock` and `killall Finder` each run once.
  - `second run changes nothing`: with fakes remembering state, there are no `defaults` writes, `killall`, `pmset` set calls, `chflags` calls, or `osascript` set calls. Read `pmset -g custom` and `pmset -g cap` first, and `stat -f %Sf ~/Library` before `chflags`.
  - `only Dock change restarts only Dock`.
  - `bool compare`: a stored `1` counts as equal to `true`.
  - `extensions domain`: `AppleShowAllExtensions` goes to `NSGlobalDomain`, never `com.apple.finder`.
  - `no sudo`: `FAKE_SUDO_FAIL=1` makes the `pmset` steps fail or skip, and the `defaults` rows still run; exit is 1.
  - `security is report-only`: FileVault and Firewall status appear in the output, and the log shows no `fdesetup enable` and no `--setglobalstate`.
  - `autorestart unsupported`: `pmset -g cap` lacking it means a skip, not a failure.
- [ ] **Step 2:** Run `bats tests/macos.bats`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `bats tests/macos.bats && shellcheck macos.sh`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: add macOS settings`.

### Task 8: Install orchestration

**Files:**
- Create: `install.sh`, `tests/install.bats`

**Interfaces:**
- Consumes: `apps_step`, `shell_step`, `macos.sh`, `print_summary`; later `ssh_step` and `screensharing_step`, each sourced only if its file exists until Tasks 10 and 12.
- Produces: `install.sh [--all]`, running from its own directory, not assuming the current directory.

- [ ] **Step 1: Write the failing tests:**
  - `mode selection`: terminal gives `pick`; `--all` gives `all`; no terminal gives `defaults`; `MACSETUP_NO_PICKER=1` gives `defaults`.
  - `finds brew off PATH`: with `PATH` lacking Homebrew, `install.sh` uses `MACSETUP_BREW_PATHS`, and fails clearly if none exists.
  - `runs from any directory`.
  - `unknown flag`: exits non-zero with usage and does nothing.
  - `one failure does not stop the rest`: a failing `apps_step` still runs `shell_step` and `macos.sh`, and the exit is 1.
  - `macOS settings summary is included`: `macos.sh` failures reach the final exit code.
  - `bootstrap failure carried through`: `bootstrap.sh` with `gum` failing and everything else succeeding, run end to end through the handover, installs defaults, names `gum install` in the summary, and exits 1.
  - `no sudo flag respected`: `MACSETUP_NO_SUDO=1` makes `install.sh` skip its `sudo` prompt and report privileged steps as skipped.
  - `uncommitted changes warn`: a dirty clone adds a summary warning without changing the exit code.
  - `re-run is quiet`: a second run over the same fakes does no writes, no `brew bundle`, and no restarts.
- [ ] **Step 2:** Run `bats tests/install.bats`. Expected: FAIL.
- [ ] **Step 3:** Implement, with `sudo -v` and keep-alive when interactive, and `sudo -n true` otherwise, recording whether `sudo` is available for later steps.
- [ ] **Step 4:** Run `bats tests/ && shellcheck bootstrap.sh install.sh macos.sh lib/*.sh`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: add install orchestration`.

### Task 9: Stage 1 acceptance on the Mac mini

**Files:**
- Modify: `README.md`, `Brewfile` or scripts if testing finds problems
- Delete: `setup.sh`, only as the last step

- [ ] **Step 1:** Ask the owner to agree to pushing `rebuild-mac-setup`, which is public. Push it.
- [ ] **Step 2:** Update `README.md`: the new one-liner, `--all`, the stub, `p10k configure` advice, editing and pushing from `~/.macsetup`, and the Ubuntu section unchanged.
- [ ] **Step 3:** The owner runs this at the mini, and first confirms the chip and macOS version:

```bash
f="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/bartlomn/macsetup/rebuild-mac-setup/bootstrap.sh -o "$f" && MACSETUP_BRANCH=rebuild-mac-setup /bin/bash "$f"
```

Expected: the fresh path runs (Command Line Tools, Homebrew, clone, picker), with exit 0 or a summary explaining what didn't work.

- [ ] **Step 4:** Owner confirms by eye: the picker shows the right items and tiers; a new `kitty` window has the theme and fonts with no errors; `ls` uses `eza`; Dock and Finder match the spec.
- [ ] **Step 5:** Run `~/.macsetup/install.sh` again. Expected: nothing installed, no restarts, same result.
- [ ] **Step 6:** Interrupt checks: `Ctrl-C` during a run, then re-run. Expected: it finishes the job. Interrupting the first clone and Oh My Zsh install is covered on the mini only if practical, as the wipe can't be repeated cheaply; simulate by renaming `~/.oh-my-zsh` and `~/.macsetup` aside and interrupting a re-run.
- [ ] **Step 7:** Failure check: add a bad cask name to a temp `Brewfile` copy, select it, and confirm it appears in the summary with exit 1. Remove it.
- [ ] **Step 8:** Fix anything found through Tasks 1-8, with a test first. Then `git rm setup.sh` and commit: `feat: replace setup.sh with the new setup`.

### Task 10: SSH step

**Files:**
- Create: `lib/ssh.sh`, `ssh/authorized_key.pub`, `ssh/000-macsetup.conf`, `tests/ssh.bats`
- Modify: `install.sh` (already conditional)

**Interfaces:**
- Consumes: `step`, `manual_step`, `port_open`, `install.sh`'s record of `sudo` availability.
- Produces: `ssh_authorize_key`, `ssh_install_dropin`, `ssh_enable`, `ssh_step`. Paths for tests: `MACSETUP_SSHD_DROPIN_DIR` (default `/etc/ssh/sshd_config.d`).

`ssh/000-macsetup.conf` holds exactly `PasswordAuthentication no` and `KbdInteractiveAuthentication no`.

- [ ] **Step 1:** Copy `~/.ssh/id_ed25519_bnowak.pub` to `ssh/authorized_key.pub`. Run `ssh-keygen -lf ssh/authorized_key.pub`. Expected: `SHA256:gg5Xe/wTYSff/P0kLq83PZKehyHaExDj1owPADkG4gs`. Never read or copy the private key.
- [ ] **Step 2: Write the failing tests:**
  - `key added once`: two runs leave one line; other existing keys stay.
  - `permissions`: `~/.ssh` is `700`, `authorized_keys` is `600`.
  - `key file missing newline`: an existing file with no trailing newline doesn't get its last line merged.
  - `order`: key, then host keys (`ssh-keygen -A`), then drop-in, then `sshd -t` and `sshd -T`, then enable, then port check.
  - `effective values checked`: `sshd -T` reporting `passwordauthentication yes` counts as a failure.
  - `new drop-in rolled back`: `FAKE_SSHD_T_FAIL=1` on the first run removes the file, makes no `launchctl` or `systemsetup` call, and fails the step.
  - `existing drop-in restored`: on a re-run, a failure restores the earlier file byte for byte and leaves the service alone.
  - `unchanged drop-in`: an identical file means no write.
  - `enable falls back`: `launchctl` failing then trying `systemsetup`; port still closed adds a `manual_step` naming Remote Login, opens the Sharing pane, and exits 2, without reporting success.
  - `prerequisite failure stops enabling`: a failure in the key, host-key or validation step means no `launchctl` or `systemsetup` call, with the failing part named in the summary, and unrelated steps after `ssh_step` still run.
  - `no sudo`: the key is still added, privileged parts are reported, and nothing is half-written.
  - `no terminal`: the Sharing pane is not opened, but the manual step is still listed.
- [ ] **Step 3:** Run `bats tests/ssh.bats`. Expected: FAIL.
- [ ] **Step 4:** Implement, trying `launchctl enable system/com.openssh.sshd` plus `launchctl bootstrap` first, then `systemsetup -setremotelogin on`. Open the pane with `open "x-apple.systempreferences:com.apple.Sharing-Settings.extension"`.
- [ ] **Step 5:** Run `bats tests/ && shellcheck lib/ssh.sh`. Expected: PASS.
- [ ] **Step 6:** Commit: `feat: add SSH step`.

### Task 11: Stage 2 acceptance

**Files:**
- Modify: `README.md`, `lib/ssh.sh` if testing finds problems

Run from the MacBook unless stated. The owner runs `sudo` commands. Record results for the README.

- [ ] **Step 1:** Push. On the mini: `git -C ~/.macsetup pull --ff-only && ~/.macsetup/install.sh`. Record which enable route worked, or whether the manual step was needed.
- [ ] **Step 2:** `ssh <name>.local true`. Expected: key login succeeds, through the Firewall.
- [ ] **Step 3:** `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password <name>.local true` and the same with `keyboard-interactive`. Expected: both `Permission denied`.
- [ ] **Step 4:** Rollback on the mini: temporarily add an invalid line to the drop-in in the repo copy and re-run. Expected: the previous drop-in restored, SSH still works, exit 1. Revert the line.
- [ ] **Step 5:** Run `ssh <name>.local '~/.macsetup/install.sh'` with no terminal. Expected: defaults only, no optional apps, clear reporting of anything needing `sudo`.
- [ ] **Step 6:** Restart test with the owner's FileVault choice in place. With it off: restart, confirm SSH returns unattended. With it on: confirm the unlock over SSH on the chosen network, or record that it failed. Key-only login stays regardless, per the spec.
- [ ] **Step 7:** Power-cut test if the owner agrees: unplug, replug, confirm it returns.
- [ ] **Step 8:** Write results in the README and commit: `docs: record SSH and restart results`.

### Task 12: Screen Sharing

**Files:**
- Create: `lib/screensharing.sh`, `tests/screensharing.bats`
- Modify: `README.md`

**Interfaces:**
- Consumes: `step`, `manual_step`, `port_open`.
- Produces: `screensharing_step`.

- [ ] **Step 1:** Over SSH on the mini, with the owner running `sudo`, try each route by hand before writing code: `launchctl enable system/com.apple.screensharing` plus `launchctl bootstrap`, then `kickstart` limited to the owner's account. Check port 5900 from the MacBook and record what worked on this macOS version. Also record how to read and set who may connect, starting with `dscl . -read /Groups/com.apple.access_screensharing GroupMembership` and `dseditgroup`. Turn it off between tries.
- [ ] **Step 2: Write the failing tests:**
  - `already open, access correct`: port 5900 open and the owner the only allowed account means no changes.
  - `already open, access too wide`: port 5900 open with all users or another account allowed gets corrected, or adds a `manual_step` if it can't be. An open port alone never counts as done.
  - `access unreadable`: if the allowed accounts can't be read, adds a `manual_step`.
  - `enables by working route first`: the route order matches Step 1.
  - `summary wording`: success reads exactly `port open, not tested from another machine`.
  - `closed after attempts`: adds a `manual_step`, opens the Sharing pane when interactive, and exits 2.
  - `access limited`: the owner's account only, with no all-users flag in any `kickstart` call.
- [ ] **Step 3:** Run `bats tests/screensharing.bats`. Expected: FAIL.
- [ ] **Step 4:** Implement.
- [ ] **Step 5:** Run `bats tests/ && shellcheck lib/screensharing.sh`. Expected: PASS.
- [ ] **Step 6:** Update the README and commit: `feat: add Screen Sharing step`.
- [ ] **Step 7:** Push. On the mini: `git -C ~/.macsetup pull --ff-only && ~/.macsetup/install.sh`. Then from the MacBook open `vnc://<name>.local`. The owner confirms viewing and control work, and that only their account is allowed. If the mini has no display attached, the owner checks the screen is usable too. Stage 3 isn't done until the owner has confirmed.
- [ ] **Step 8:** Run the whole suite and a final no-change `install.sh` on the mini. Expected: PASS, no changes. Commit and push any fixes, each with a test first.

### Task 13: Publish to main

**Files:**
- None expected, beyond fixes found here

- [ ] **Step 1:** Ask the owner how to integrate `rebuild-mac-setup` into `main`, for example by a pull request, and do it only once they agree. This is what makes the new one-liner live for anyone using the public URL, and it removes `setup.sh` from `main`.
- [ ] **Step 2:** On the mini, run the production one-liner from the README exactly as written, with no branch overrides, after pointing the clone back with `git -C ~/.macsetup switch main && git -C ~/.macsetup pull --ff-only`. Expected: exit 0, or 2 only for a documented manual step, with nothing changed.
- [ ] **Step 3:** Confirm the Ubuntu section of the README and `ubuntu_setup.sh` are unchanged: `git diff <base> main -- ubuntu_setup.sh 50unattended-upgrades.conf` prints nothing.
