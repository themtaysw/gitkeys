# GitKeys

A tiny, native macOS app for wiring up SSH and GPG access to Git hosts — especially
self-hosted GitLab / GitHub / Gitea instances — **without touching the terminal**.

Point it at a host (e.g. `gitlab.spendee.com`), pick or generate a key, and it writes
your `~/.ssh/config`, shows you the public key to paste in, and tests the connection.

Built with SwiftUI. No Electron, no web view — just a real Mac app.

## Features

- **Connect a Git host** — a guided, end-to-end wizard:
  1. Enter host + SSH user
  2. Pick an existing key or generate a new ed25519 one
  3. Write the `Host` block to `~/.ssh/config` (with `IdentitiesOnly yes`)
  4. Copy the public key / open the host's keys page
  5. Test with `ssh -T`
- **SSH Config editor** — a GUI over `~/.ssh/config`. Add/edit/remove `Host` blocks and
  their options. Comments and unrecognised lines are preserved verbatim, and every save
  makes a timestamped backup in `~/.ssh/gitkeys-backups/`.
- **SSH Keys** — list existing keys, generate ed25519 keys, one-click copy of the public key.
- **GPG & Signing** — create an ed25519 signing key, export the public key for your host,
  and configure git (`user.signingkey`, `commit.gpgsign`, `tag.gpgsign`).

## Safety

- **Private keys are never read or displayed** — only `.pub` files and GPG *public* exports.
- Every write to `~/.ssh/config` is preceded by a timestamped backup.
- `~/.ssh` is created `0700` and `config` written `0600` if they don't already have those perms.

## Requirements

- macOS 13 (Ventura) or newer
- Xcode command-line tools / Swift 5.9+ (`swift --version`)
- `gpg` is only needed for the GPG tab: `brew install gnupg`

## Run it

```sh
git clone <your-fork-url> gitkeys
cd gitkeys
swift run
```

Or open `Package.swift` in Xcode and hit ⌘R.

## Build a distributable `.app`

`swift run` launches the binary directly (handy for dev). To ship a proper bundle,
open the package in Xcode, add a macOS App target, or use a tool like
[`swift bundler`](https://github.com/stackotter/swift-bundler). Contributions to add a
one-command `.app` build are welcome.

## Known limitations (good first issues 👋)

- The SSH config parser handles `Host` blocks; `Match` blocks are kept as raw lines but
  not specially modelled.
- Option values are re-serialised with single-space separators (fine for normal options;
  exotic `ProxyCommand` quoting may be reflowed).
- The "Open host keys page" button assumes GitLab's URL layout
  (`/-/user_settings/ssh_keys`).
- Connection test uses `BatchMode=yes`; passphrase-protected keys must be loaded into the
  ssh-agent first.

## License

AGPL-3.0 — see [LICENSE](LICENSE). You're free to use, modify, and share GitKeys;
any distributed or network-served modification must stay open source under the
same license.
