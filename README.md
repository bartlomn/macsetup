# Mac setup utility script

## Running on Mac

Takes a fresh Mac to usable with one command. It is safe to re-run at any time: every step checks
first, and a re-run changes only what is missing.

```bash
f="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/bartlomn/macsetup/main/bootstrap.sh -o "$f" && /bin/bash "$f"
```

This installs Homebrew, clones the repo to `~/.macsetup`, and runs `~/.macsetup/install.sh`. The
account must be an administrator, and you'll be asked for your password once.

To re-run later:

```bash
~/.macsetup/install.sh         # Choose apps in the picker
~/.macsetup/install.sh --all   # Install everything not yet installed or declined
~/.macsetup/macos.sh           # macOS settings only
```

With no terminal, as in a plain `ssh host ~/.macsetup/install.sh`, only default apps are installed.

The run ends with a summary. Exit codes: `0` all done, `1` something failed, `2` nothing failed but
manual steps remain.

### Apps

`Brewfile` lists everything, and `# optional` marks items that start unchecked. Apps already
installed are listed above the picker. Unchecking a default records it in
`~/.config/macsetup/declined`, so it starts unchecked next time. Nothing is ever uninstalled.

### Shell

`~/.zshrc` is a small stub that loads `~/.macsetup/zsh/zshrc.zsh`. Put machine-specific settings and
secrets below the stub line, as this repo is public. Any previous `~/.zshrc` is kept with a
`.macsetup-bak-<timestamp>` suffix.

If `p10k configure` offers to edit `~/.zshrc`, decline, because the prompt is already loaded.

Icons work in kitty as it is. Terminal.app needs its font set to `MesloLGS NF` by hand.

### Changing the setup

`~/.macsetup` is a working copy, and `~/.p10k.zsh` links into it, so edits show up in its
`git status`, and the summary warns about them. It's cloned over HTTPS, as a new Mac has no SSH key.
To push from a Mac that holds the key:

```bash
git -C ~/.macsetup remote set-url origin git@github.com:bartlomn/macsetup.git
git -C ~/.macsetup push
```

### Tests

For development, `brew install bats-core shellcheck gum`, then:

```bash
bats tests/
shellcheck -x bootstrap.sh install.sh macos.sh lib/*.sh
```

The tests use a temporary `HOME` and fake commands. Don't run the scripts themselves on a Mac you
don't want changed.

## Running on Ubuntu

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/bartlomn/macsetup/main/ubuntu_setup.sh)"
```
