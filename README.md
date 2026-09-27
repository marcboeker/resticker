# Resticker

A macOS menu bar app that runs and watches a [restic](https://restic.net) backup.

It backs up on a schedule, catches up after the Mac wakes from sleep, shows the last
backup time and the amount of data transferred, and runs the restic maintenance
commands once a day.

## Install

```sh
make install        # builds, signs and copies to ~/Applications
make set-password   # stores the repository password in the keychain
open ~/Applications/Resticker.app
```

The order matters. The keychain access list is bound to the installed app, so the
password item can only pre-authorize an app that already exists. If you re-sign the
app with a different identity later, delete the item and store it again:

```sh
security delete-generic-password -s resticker -a repository-password
make set-password
```

Tick **Start at Login** in the menu. The schedule only runs while the app runs.

## Configuration

The config file is `~/.config/resticker/config.json`. The app creates it with defaults
on first launch and never writes to it again, so your edits are safe. It is reloaded
when the file changes. Every key is optional.

```json
{
  "resticPath": "/opt/homebrew/bin/restic",
  "repository": "/Volumes/Backup/restic",
  "sourcePaths": ["/Users/tester"],
  "excludeFile": "~/.resticignore",
  "intervalMinutes": 240,
  "cleanupIntervalHours": 24,
  "retryDelayMinutes": 15,
  "maxRetries": 3,
  "notifyOnSuccess": false,
  "env": {},
  "globalArgs": ["--compression", "max", "--pack-size", "64"],
  "backupArgs": ["--one-file-system", "--exclude-caches"],
  "forgetArgs": ["--prune", "-l", "6", "-d", "7", "-w", "7", "-m", "4", "-y", "12"],
  "checkArgs": [],
  "unlockArgs": []
}
```

| Key | Meaning |
| --- | --- |
| `resticPath` | Full path to restic. An app started from Finder does not inherit your shell `PATH`, so this cannot be just `restic`. |
| `repository` | Passed as `RESTIC_REPOSITORY`. |
| `sourcePaths` | What gets backed up. |
| `excludeFile` | Passed as `--exclude-file`. Skipped when the file does not exist. |
| `intervalMinutes` | Time between runs, measured from the last success. |
| `cleanupIntervalHours` | How often the maintenance steps run. `0` means after every backup. |
| `retryDelayMinutes`, `maxRetries` | Retry behaviour after a failed backup. |
| `notifyOnSuccess` | Failures always produce a notification. Successes only with this on. |
| `env` | Extra environment variables, for backend credentials such as `AWS_ACCESS_KEY_ID`. |
| `globalArgs` | Flags placed before the restic subcommand, so they apply to every command. |
| `backupArgs`, `forgetArgs`, `checkArgs`, `unlockArgs` | Flags for the matching subcommand. |

Arguments are passed as a list, never through a shell, so no quoting rules apply.
The assembled command looks like this:

```
restic <globalArgs> forget <forgetArgs>
```

The password is read from the keychain and passed to restic as `RESTIC_PASSWORD` in
the child process environment only. It is never written to the config file or the log.

## What a run does

1. `unlock`, before the backup, to clear a lock left by a crashed earlier run.
2. `backup --json`, parsed for live progress and for the final summary.
3. `forget`, once per `cleanupIntervalHours`, and only after the backup succeeded.
4. `check`, in the same maintenance window.

Each step is optional and controlled by a checkbox in the menu. A step that fails
stops the remaining steps, because running prune after a failed check is how a damaged
repository becomes a permanently damaged one.

A failed backup is retried after `retryDelayMinutes`, up to `maxRetries` times, then it
waits for the next scheduled slot. A failed maintenance step never retries the backup.

**Transferred** is `data_added_packed` from the restic summary, which is what actually
landed in the repository after compression.

## Notes

- `forget` is not filtered by tag or host, so it applies its retention policy to every
  snapshot in the repository. This is safe only while the repository holds backups from
  this Mac alone.
- The first launch has no recorded run, so a backup starts at once.
- Sleeping through a scheduled run causes exactly one catch-up run after the wake, not
  one run per missed slot.
- During a run the app holds an idle sleep assertion. Closing the lid still forces sleep
  and kills restic. The run is then simply due again after the wake.
- **Cancel Backup** sends `SIGINT` so restic can remove its own lock, then `SIGKILL`
  after 10 seconds. A cancelled run does not count as a failure and does not move the
  schedule.
- Log: kept in memory only, capped around 5 MB. **Open Log** shows it live and resets on
  every launch.
- State: `~/Library/Application Support/Resticker/state.json`, holding the last 20 runs.
- Checkbox states live in `UserDefaults` under `net.at6.resticker`.

## Make targets

| Target | Action |
| --- | --- |
| `make build` | Release build with SwiftPM. |
| `make test` | Unit tests for the schedule arithmetic and the restic JSON decoding. |
| `make bundle` | Assembles and signs `dist/Resticker.app`. |
| `make install` | Stops a running copy and installs into `~/Applications`. |
| `make set-password` | Stores the repository password in the keychain. |
| `make run` | Installs and launches. |
| `make uninstall` | Removes the app. Leaves the config and the keychain item. |
| `make clean` | Removes build output. |

Override the signing identity with `make install CODESIGN_IDENTITY="..."`.
