# macOS setup rebuild: design

Date: 2026-11-06
Status: approved by the owner, subject to Codex review; Codex approved

## Intent

Replace `setup.sh`, a 178-line script that fails silently, with a setup that takes a Mac from
fresh to usable with one command and is safe to re-run at any time.

An assessment of the old script found the failures that drive this design:

- Run the way the README says (`sh -c`), it writes `-e alias ls=...` into `~/.zshrc` and expands
  backslashes across the whole file, because macOS `sh` does not support `echo -e`.
- The `eza` alias is added above Oh My Zsh, which then overrides it.
- `--istall-rosetta` is misspelled, so Rosetta has never installed, and nothing reported it.
- Fixes made by hand on a real machine never reach the repo. The owner's `.zshrc` has drifted
  from what the script produces.
- Everything behind "does `~/.oh-my-zsh` exist?" is skipped forever if a run is interrupted.

## Goals

- One command on a fresh Mac, with no repo already present.
- Idempotent: every step checks state first, and a re-run changes only what is missing.
- Failures are visible: a failed step never looks like success, and the run ends with a summary
  of what failed and what needs doing by hand.
- A picker for choosing apps, which shows what is already installed.
- SSH into the Mac with the owner's main key after the script runs (local network only).
- Screen sharing available after the script runs (local network only).

## Non-goals

- Syncing the home directory, `~/.claude`, or a private dotfiles repo. Deferred until the main
  script is in good shape. The design must not block adding it later.
- The Ubuntu script (`ubuntu_setup.sh`, `50unattended-upgrades.conf`). Out of scope and left
  untouched.
- Intel Mac support beyond not breaking on it needlessly. This Mac is Apple silicon, and the owner
  believes the Mac mini is an M1; its macOS version is not yet known. Homebrew's path should be
  detected, not hardcoded.
- Live sync between Macs.
- Access from outside the local network.
- App Store apps through `mas`. Toggl Track, WireGuard, Decompressor and Windows App stay manual
  for now.

## Anti-goals

The rebuild has failed, even if it technically works, if it:

- Uninstalls anything. The script never removes apps.
- Overwrites a file holding the owner's config without first backing it up.
- Puts secrets in this repo. **The repo is public** and must stay public, because the curl
  one-liner depends on it.
- Reports success when a step failed.
- Runs a routine upgrade of already-installed packages as a side effect of a re-run. The one
  permitted exception: installing a missing package may upgrade a dependency it requires, which
  `brew bundle --no-upgrade` cannot rule out. Blocking the install would be worse.

## Build order

Decided by the owner. Each stage is finished and working before the next starts:

1. Basic setup: bootstrap, apps, shell config, macOS settings.
2. SSH.
3. Screen sharing.

The target is a **freshly wiped Mac mini** that stays on the owner's home network. "This Mac" in this
document means the owner's current MacBook Pro, which is where the private SSH key lives and where
the shell config and settings are taken from. The script is developed there and is not run there.

Stage 1 is run by the owner at the Mac mini, since no SSH exists yet, and it exercises the real fresh
install path. Once SSH works, it is the channel for further tests from this Mac, and the owner has
allowed any tests needed over it. The owner runs any commands that need `sudo`; no passwordless
`sudo` is set up. Everything must be idempotent because the script will run repeatedly on the mini
during this testing.

## Repo layout

Decided in principle. Exact file names are the builder's, except where stated.

```text
bootstrap.sh          Entry point. Must work with nothing else from the repo.
install.sh            Runs everything from the clone. Also runnable directly.
Brewfile              Single source of truth for apps and CLI tools.
macos.sh              macOS settings. Standalone and re-runnable.
zsh/zshrc.zsh         The real shell config.
p10k.zsh              Prompt config, symlinked to ~/.p10k.zsh.
ssh/                  Public key and the sshd drop-in.
```

`setup.sh` is removed once its replacement works. The README is updated to the new one-liner.

## Bootstrap

Entry point:

```bash
f="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/bartlomn/macsetup/main/bootstrap.sh -o "$f" && /bin/bash "$f"
```

The script is downloaded first because `/bin/bash -c "$(curl ...)"` runs an empty string and reports
success when the download fails. Calling `/bin/bash` directly removes the `sh` bug class, and running
from a file keeps the terminal attached, which the picker needs. `curl | bash` would not.

`bootstrap.sh`, in this order:

1. Check the account is an administrator, and stop with a clear message if not. Run `sudo -v` and
   keep the credential alive for the run. `NONINTERACTIVE=1` makes the Homebrew installer unable to
   prompt, so it depends on this. Without a terminal or valid credentials, bootstrap stops if
   Homebrew is missing; later, privileged steps are reported as failed or skipped, never silently
   passed over.
2. Install Homebrew if missing, with `NONINTERACTIVE=1`. This also installs the Xcode Command Line
   Tools, and that is what provides a real `git`. A fresh Mac's `/usr/bin/git` is a stub that opens
   a GUI prompt, so this order matters.
3. Install `gum`. If this alone fails, the run continues using defaults only, as for a run with no
   terminal, and reports it.
4. Clone the repo to a temporary path over HTTPS, because a fresh Mac has no SSH keys, and move it to
   `~/.macsetup` once complete. If `~/.macsetup` exists and is a valid clone of this repo, run
   `git pull --ff-only`. If it has uncommitted changes, skip the pull and carry on with the local copy,
   so ordinary tweaking cannot block a re-run. If it exists but is not a valid clone, move it aside
   with a timestamped name, never delete it, and clone again.
5. Hand over to `~/.macsetup/install.sh`.

The rest of the setup depends on Homebrew, `git` and the clone, so a failure in any of those stops
bootstrap immediately with a clear message and a non-zero exit code. The body of `bootstrap.sh` is
wrapped in a function called on its last line, so a partial file cannot run.

The clone location is permanent, because symlinks point into it.

Getting changes back to the repo (builder's call): `~/.macsetup` is the working copy, so edits to the
symlinked files appear in its `git status`. The end summary warns when it has uncommitted changes.
Pushing is manual, from a machine holding the key, after switching that clone's remote to SSH; the
README documents this. No auto-commit, because that is how a secret gets pushed unnoticed.

## Apps

The `Brewfile` is the single source of truth. A marker in it (for example a trailing comment) sets
an entry's tier:

- **Default:** starts checked. Needed on every Mac.
- **Optional:** starts unchecked.

### Picker

`gum` (installed by the bootstrap straight after Homebrew; the builder confirms during the build
that its flags do what is described here). The flow:

- Already-installed items appear in a **read-only list above the checklist**, not as rows, so they
  have no checkbox and cannot be unchecked.
- The checklist holds only what is not installed.
- If nothing is left to install, the picker is skipped and the read-only list is printed.
- Descriptions come from `brew info --json=v2`.
- Selected entries are piped to `brew bundle install --no-upgrade --file=-`.

### Installed states

Each item is **managed by Homebrew**, **installed outside Homebrew**, or **not installed**. The
first two go in the read-only list, with the second labelled "outside brew", because `brew list`
cannot see those and installing the cask over one usually fails. Detection uses the app paths in
the cask metadata. This case is untested so far, and needs a specific test, for example with the
owner's directly installed `Zen.app`.

### Unchecking

Unchecking means "don't install", and nothing more. Unchecked **default** items are remembered in a
per-machine list of declined items under `~/.config/macsetup/`, outside the repo, and start unchecked
next time. Checking one again removes it from the list. Optional items always start unchecked, so
leaving one unchecked records nothing. Items newly added to the `Brewfile` start according to their
tier. (Builder's call: recording only defaults.)

### Unattended runs

`--all` skips the picker and installs every missing default and optional item that has not been
declined. With no terminal attached, the script installs **only missing, non-declined defaults**, so
that a plain `ssh host script` cannot pull in every optional app, which the script would never
remove. (Builder's call: this narrows what was discussed in conversation, where no-terminal behaved
like `--all`.)

### The list

Default apps: `zen`, `google-chrome`, `kitty`, `claude`, `claude-code`, `codex`, `bitwarden`,
`localsend`.

Optional apps: `alfred`, `balenaetcher`, `evernote`, `vlc`, `spotify`, `meetily`, `handy`,
`cyberduck`, `slack`, `dbeaver-community`, `raspberry-pi-imager`, `gpg-suite`, `gcloud-cli`,
`coderabbit`, `docker-desktop` (optional by the owner's choice, as the 8 GB mini may struggle with
it).

Default CLI tools: `aws-cdk`, `awscli`, `eza`, `git`, `fnm`, `helm`, `k9s`, `kubectl`, `direnv`,
`gh`, `git-lfs`, `go-task`, `kubectx`, `tfenv`, `yq`, `tmux`, `glow`, `ncdu`, `rename`, `z`.

Optional CLI tools: `argocd`, `opentofu`, `nmap`, `iperf`, `ffmpeg`, `poppler`, `tesseract-lang`,
`zbar`, `cmatrix`.

Deliberately excluded, so they should not be re-added by reflex:

- No GUI code editor: VS Code and Cursor are both out, by the owner's choice.
- Browsers: `arc` (discontinued), `firefox`, `microsoft-edge`.
- `sourcetree`, `diffmerge` (disabled in Homebrew), `aldente`, all Microsoft Office apps,
  `microsoft-auto-update`.
- `tunnelblick`, `transmission`, `freecad`, `sweet-home3d`, `minecraft`, `android-studio`, `p4v`,
  `temurin@21`, `fig`, `rar`.
- `moon`, `influxdb-cli`, `postgresql@16`, `proto`, `ollama`, `eksctl`, `go`, `glab`, `maven`,
  `protobuf`, `yadm`, `python@3.10`, `gemini-cli`, `sshpass`.
- `orca`: Homebrew's cask of that name is a disabled Plotly tool, not the Orca app the owner uses.
- `raycast`: added later only if Spotlight falls short. The owner is trying Spotlight in place of
  Alfred.

Rosetta: the old script tried to install it and never succeeded. Whether it is still needed is the
builder's call; nothing in the list above is known to require it.

## Shell config

`~/.zshrc` is a small stub, not the Oh My Zsh template:

```zsh
source ~/.macsetup/zsh/zshrc.zsh
# Machine-specific settings and secrets go below this line
```

Adding a line to the default template does not work. At the bottom it is too late for instant prompt
and the theme, and at the top the template overwrites them.

`zsh/zshrc.zsh` runs in this order:

1. Anything that needs console input or may print (`fnm` is here on the owner's Mac today).
2. p10k instant prompt.
3. `ZSH_THEME`, `plugins`, other Oh My Zsh settings.
4. `source $ZSH/oh-my-zsh.sh`.
5. Aliases and other overrides, including the `eza` alias, which must come after step 4.
6. `source ~/.p10k.zsh`.

Tested on this Mac in a throwaway `ZDOTDIR` with a 3-second delay after step 2: the prompt appeared
at 0.02–0.03s, against 3.14s without instant prompt. The theme and alias were correct, and the
terminal output had no instant prompt warnings. Only the `git` plugin was enabled, so this must be
repeated with the full plugin list.

Requirements:

- `zshrc.zsh` is built from the owner's **real** `~/.zshrc`, not from the old script, because the
  real file has drifted (for example it has a `direnv` plugin). It must be reviewed for secrets and
  machine-specific values first, since the repo is public. Those stay below the stub line.
- Write the stub before installing Oh My Zsh, and install with `--unattended --keep-zshrc`.
- `~/.oh-my-zsh` counts as installed only if it is a valid clone containing `oh-my-zsh.sh`. A folder
  that fails this check is left over from an interrupted install, so it is moved aside with a
  timestamped name, never deleted, and the install runs again.
- Back up an existing `~/.zshrc` before replacing it, using a timestamped name so a backup is never
  overwritten. If the stub line is already present, leave the file alone.
- `~/.p10k.zsh` is a symlink into the repo, which should also stop the setup wizard on a new Mac. It
  gets the same backup treatment if a different file or link is already there.
- `zshrc.zsh` must not assume any tool is installed, because tools can be declined or fail to
  install. `fnm` initialisation, the `eza` alias and similar are conditional on the command existing,
  so a missing tool never causes a startup error or a broken `ls`.
- Theme, plugins and fonts each get their own check, not one shared check on `~/.oh-my-zsh`. Each is
  fetched to a temporary path and moved into place once complete, so "it exists" means "it finished",
  and an interrupted run cannot leave a partial clone or truncated font that blocks a re-run.
- Fonts save with real spaces in their names and use `curl -f`, so a 404 cannot become a `.ttf`.
- `p10k configure` will probably offer to edit `~/.zshrc`, which should be declined. Worth a
  comment in the stub or README.

## macOS settings

`macos.sh` is standalone and re-runnable. It has no picker. Dock or Finder restart only if a value
actually changed.

Keep from the old script:

- Dark mode. Dock: auto-hide, magnification, only running apps shown, dimmed icons for hidden apps.
- Finder: hidden files, path bar, status bar, `~/Library` visible.

Change:

- Set Dock auto-hide and magnification with `defaults`, so they do not need Automation permission.
- Finder default view becomes column (`clmv`), matching this Mac.
- Write `AppleShowAllExtensions` to `NSGlobalDomain`. The old script wrote the wrong domain.

Add:

- Tap to click. May need setting in more than one place to cover external trackpads; test it.
- Dock icon size 66, magnified 90.
- Automatic Spaces rearranging off (`mru-spaces` false).
- No `.DS_Store` on network or USB drives.
- Finder: search the current folder by default, and sort folders first.
- Typing: faster key repeat, autocorrect off, key repeat instead of the accent popup. Exact repeat
  values are the builder's call, and should be easy to change in one place.
- On power: stay awake with wake-for-network on, matching this Mac. Battery settings are untouched.
- Restart automatically after a power failure, so the mini comes back on its own. (Builder's call.)

Report only, never change: Firewall and FileVault status. Turning FileVault on stays the owner's
manual decision.

## SSH (stage 2)

- Key: `~/.ssh/id_ed25519_bnowak.pub`, fingerprint
  `SHA256:gg5Xe/wTYSff/P0kLq83PZKehyHaExDj1owPADkG4gs`. It is the only key on the `bartlomn` GitHub
  account, and the one `github.com` uses.
- Store the **public** key in the repo and add it to `~/.ssh/authorized_keys` if missing, with `700`
  on `~/.ssh` and `600` on the file. Do not fetch `github.com/bartlomn.keys`, because a key added to
  GitHub later would then get login access. The private key is never copied.
- Key-only login: a drop-in in `/etc/ssh/sshd_config.d/` turns off `PasswordAuthentication` and
  `KbdInteractiveAuthentication`. The owner accepts needing physical access if the key is lost.
  OpenSSH uses the first value it reads for a setting, so the drop-in's name must sort before any
  other file there. Before enabling or reloading SSH, validate with `sshd -t` and confirm the
  effective values with `sshd -T`. If either check fails, roll back and report the failure: restore the
  previous drop-in if one existed, remove it only if this run created it, and leave the running SSH
  service as it was. A re-run must never remove a working key-only setup. The key must be in
  `authorized_keys` first.
- Enable Remote Login. Apple documents that `systemsetup -setremotelogin on` needs Full Disk Access,
  which a fresh terminal lacks. `launchctl` may avoid this, but the source for that is weak, so it
  needs testing on macOS 26.
- Then **verify port 22 is actually open**. If not, open the Sharing pane in System Settings and put
  the manual step in the end summary. Do not report success otherwise.
- Connection is by `<name>.local` on the local network. "Local only" means no port forwarding or
  tunnels are set up. It is not enforced with firewall rules, because the mini stays on the home
  network.

Open points to test:

- Whether the Firewall, which is on, allows it. The script never changes Firewall settings; a block
  becomes a manual step in the summary. (Builder's call.) A port check from the Mac itself does not
  pass through the Firewall, so testing must also connect from a second machine.
- Coming back after a restart with nobody present is wanted, though not a hard requirement. With
  FileVault off, nothing should block it, and this needs confirming. With FileVault on, the Mac waits
  for an unlock. Apple silicon on macOS 26 can unlock over SSH, with Remote Login on and a network
  connection, and on Wi-Fi only with a previously joined open or WPA2-PSK network. Whether key-only
  login affects this is unknown. Test it and record the result in the README; a failure here does not
  by itself reopen key-only login.

## Screen sharing (stage 3)

- Try the command line (`launchctl`, or `kickstart`). The available guides are old and nothing
  confirms they work on macOS 26, so this needs testing.
- **Verify port 5900 is open**, with the same fallback as SSH: open the Sharing pane and list the
  manual step in the summary. An open port is the limit of what the script can check, so its summary
  says "port open, not tested from another machine" rather than claiming Screen Sharing works.
- On by default, because the mini stays on the home network.
- Limit access to the owner's account. Never expose it to the internet.
- If the mini runs without a display, check the screen is usable over Screen Sharing.
- It logs in with the macOS password, not the SSH key, so key-only SSH does not affect it.

## Error handling

- Each step runs and records its result. One failed step does not stop unrelated steps, but no
  failure goes unreported.
- The end summary lists what failed and what needs doing by hand, and the exit code is non-zero if
  anything failed.

## Testing

- `bash -n` and ShellCheck on all scripts. ShellCheck is not currently installed.
- Run on the wiped Mac mini, then run a second time and confirm nothing changes.
- SSH acceptance, from this Mac: key login succeeds, and password and keyboard-interactive login are
  both rejected.
- Screen Sharing acceptance, from this Mac: a real graphical session where the owner confirms both
  viewing and control work, and access is limited to the owner's account. Stage 3 is not done until
  the owner has confirmed this.
- Decline `fnm` and `eza` (or remove them), and confirm a new shell starts with no errors and `ls`
  still works.
- Download failure: a bad bootstrap URL must exit non-zero with nothing run.
- Interrupt a run and confirm a re-run finishes the job, including interruptions during the repo
  clone and the Oh My Zsh install.
- On a re-run, force the SSH validation to fail and confirm the previous drop-in is restored and the
  running SSH service is unchanged.
- Confirm a real failure, such as a bad cask name, shows up in the summary and exit code.
- Repeat the shell test with the full plugin list.

## Left to the builder

- Exact file names and internal structure of the scripts, and the `Brewfile` marker format.
- How steps record results.
- Whether grouping in the picker is by label prefix or screens, based on what `gum` supports.
