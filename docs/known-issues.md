# Known issues

Minor issues found in the final review of the setup rebuild (2026-11-08) and left for later. None of them can lock the owner out.

## SSH

- If the sudo timestamp lapses during the SSH checks, the failure is reported as sshd rejecting the drop-in. A failed `sshd -T` prints no message. (`lib/ssh.sh:54`, `lib/ssh.sh:135`)
- If the rollback of the drop-in itself fails, the message only goes to stderr, not to the summary. (`lib/ssh.sh:76-80`)
- `authorized_keys` lines with options before the key type are not recognised, so the key is appended again.
- No test covers the rollback itself failing.

## Screen Sharing

- The Sharing pane can open twice in one run when SSH and Screen Sharing are both off.
- A fresh Mac with Screen Sharing off and no access group gets two manual steps.
- No test covers a one-line `NestedGroups` with several values. The code handles it and it was checked by hand.
