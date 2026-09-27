# Resticker

Resticker is a macOS menu bar app that runs [restic](https://restic.net) backups on a
schedule. It backs up in the background, catches up after your Mac wakes from sleep,
and shows the last backup time, how much data moved, and your recent snapshots right
in the menu.

<img src="docs/screenshot.png" alt="Resticker menu bar dropdown" width="320">

## Getting Started

**Prerequisites:** macOS 14 or later, and restic itself:

```sh
brew install restic
```

Clone this repository, then build and install the app:

```sh
git clone <repository-url>
cd resticker
make install
make set-password
open ~/Applications/Resticker.app
```

Run these in order. `make install` copies the app to `~/Applications`, and
`make set-password` stores your repository password in the keychain, scoped to that
installed app. If you skip ahead and run `make set-password` first, it has nothing to
scope the keychain item to, and will fail. If you later re-sign the app with a
different identity, remove the old keychain item first:

```sh
security delete-generic-password -s resticker -a repository-password
make set-password
```

On first launch, Resticker creates `~/.config/resticker/config.json` with a commented
example, then starts a backup right away (see Behavior below). Edit the file, either
by hand or with **Edit Config** in the menu, to point `resticBinaryPath`,
`repository`, and `sourcePaths` at your own setup before or after that first run.
Changes are picked up automatically the moment you save.

Once that's set, click the menu bar icon and tick **Start at Login** so Resticker
keeps backing up after a restart.

## Configuration

Every setting, the retention policy, and any extra restic arguments live in
`~/.config/resticker/config.json`. See
[docs/CONFIGURATION.md](docs/CONFIGURATION.md) for the full list of keys.

## Behavior

A few things worth knowing before you rely on this:

- The first launch has no recorded backup, so one starts right away.
- If your Mac was asleep through a scheduled backup, it runs once after waking, not
  once for every slot it missed.
- `forget` (the retention/pruning step) is not scoped by host or tag, so it applies to
  every snapshot in the repository. Only point Resticker at a repository that holds
  backups from this Mac alone.
- **Cancel Backup** stops restic cleanly and does not leave a stale lock or count as a
  failed run.

## Other make targets

| Target | Action |
| --- | --- |
| `make build` / `make test` | Build or run the unit tests without installing. |
| `make run` | Install and launch in one step. |
| `make uninstall` | Removes the app. Leaves your config and keychain item in place. |
| `make clean` | Removes build output. |

Override the signing identity with `make install CODESIGN_IDENTITY="..."`.
