# Configuration

Resticker reads its settings from `~/.config/resticker/config.json`.

The file does not exist on a fresh install. The first time the app looks for it
and finds nothing, it copies the contents of `config.example.json` (from this
repository) to that location, comments included, and sets its permissions to
owner read/write only (`0600`), since the file can hold cloud-backend
credentials. After that first copy, Resticker never writes to the file again;
every change you make by hand is preserved across restarts and updates.

Open the file for editing at any time with the menu bar item's "Edit Config",
or directly:

```
open -t ~/.config/resticker/config.json
```

## Comments

JSON has no native comment syntax, but Resticker's own reader supports one
convention: any line whose *trimmed* content starts with `//` is treated as a
comment and removed before the rest of the file is parsed as JSON. For example:

```jsonc
{
  // This whole line is a comment and is ignored.
  "backupIntervalMinutes": 240
}
```

Only whole-line comments are supported. A `//` that appears elsewhere on a
line with real content — for instance inside a repository URL like
`s3:https://s3.amazonaws.com/bucket` — is left untouched. Trailing comments
after a value on the same line (`"key": "value", // comment`) are not
supported and will break JSON parsing; keep comments on their own line.

You can add, remove, or edit comments freely. They exist purely to document
the file for a human reader; Resticker itself never reads or writes them
after the initial copy.

## Keys

Every key below is optional. Any key you omit falls back to its default
value, so a config file containing only the keys you care about is valid.
Values shown are `Config.default`, the sample used when the file is created.

### `resticBinaryPath`

- Type: string (file path, `~` is expanded)
- Default: `/opt/homebrew/bin/restic`

Full path to the `restic` executable. Find yours with `which restic`. On an
Intel Mac with Homebrew this is typically `/usr/local/bin/restic`.

### `repository`

- Type: string
- Default: `/Volumes/Backup/restic`

The restic repository to back up to. This can be a local path, or any
repository location restic itself understands, for example:

- `sftp:user@host:/path/to/repo`
- `s3:https://s3.amazonaws.com/bucket-name`
- `rest:https://user:pass@host:8000/`

### `sourcePaths`

- Type: array of strings (file paths, `~` is expanded)
- Default: `["<your home directory>"]`

The files and folders passed to `restic backup`. Example:

```json
"sourcePaths": ["~/Documents", "~/Pictures", "/Volumes/Projects"]
```

### `excludeFile`

- Type: string or `null` (file path, `~` is expanded)
- Default: `~/.resticignore`

Path to a file listing patterns to exclude from the backup, one per line, in
restic's `--exclude-file` format. Set to `null` to skip passing an exclude
file. If the file does not exist at backup time, it is silently skipped.

### `backupIntervalMinutes`

- Type: integer (minutes)
- Default: `240` (every 4 hours)

How often a backup runs while the Mac is awake and the app is running. If the
Mac was asleep past the due time, the missed backup runs once, promptly,
rather than once per missed interval.

### `maintenanceIntervalHours`

- Type: integer (hours)
- Default: `24`

How often maintenance (`restic forget` and `restic check`, depending on which
are enabled in the menu) runs after a successful backup. A value of `0` means
maintenance is attempted after every successful backup.

### `retryDelayMinutes`

- Type: integer (minutes)
- Default: `15`

How long to wait before retrying after a failed backup.

### `maxRetries`

- Type: integer
- Default: `3`

How many times a failed backup is retried using `retryDelayMinutes` between
attempts. Once retries are exhausted, the schedule falls back to the regular
`backupIntervalMinutes` interval instead of retrying forever.

### `notifyOnSuccessfulBackup`

- Type: boolean
- Default: `false`

Whether to show a macOS notification when a backup finishes successfully.
Failures, and maintenance steps that fail after a successful backup, always
notify regardless of this setting.

### `environmentVariables`

- Type: object of string to string
- Default: `{}`

Extra environment variables passed to every `restic` invocation. This is
where cloud-backend credentials belong, for example:

```json
"environmentVariables": {
  "AWS_ACCESS_KEY_ID": "AKIA...",
  "AWS_SECRET_ACCESS_KEY": "..."
}
```

### `resticGlobalArgs`

- Type: array of strings
- Default: `["--compression", "max", "--pack-size", "64"]`

Extra arguments inserted before the subcommand on every `restic` invocation
(backup, forget, check, and unlock alike).

### `resticBackupArgs`

- Type: array of strings
- Default: `["--one-file-system", "--exclude-caches"]`

Extra arguments passed to `restic backup`.

### `resticForgetArgs`

- Type: array of strings
- Default: `["--prune", "-d", "4", "-w", "7", "-m", "4", "-y", "12"]`

Extra arguments passed to `restic forget`, the maintenance step that prunes
old snapshots. The default keeps 4 daily, 7 weekly, 4 monthly, and
12 yearly snapshots, and prunes the data those snapshots no longer reference.

### `resticCheckArgs`

- Type: array of strings
- Default: `[]`

Extra arguments passed to `restic check`, the maintenance step that verifies
repository integrity.

### `resticUnlockArgs`

- Type: array of strings
- Default: `[]`

Extra arguments passed to `restic unlock`, which runs before every backup (if
enabled in the menu) to clear a stale lock left behind by a crash or a forced
quit.
