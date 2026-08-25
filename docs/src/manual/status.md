# [status](@id Manual-status)

Read the table, watch it live, or cancel a row. The table lives on the
queue host.

```bash
julia --project=. -m DistSSHKitQueue [qhost:HOST] status [-q]
julia --project=. -m DistSSHKitQueue [qhost:HOST] watch [-q] [--interval S]
julia --project=. -m DistSSHKitQueue [qhost:HOST] cancel <id>
```

Also: [First job](@ref Tutorial-Client), [submit](@ref Manual-submit),
[User Guide](@ref Manual).

`status` / `watch` print `qhost` from `DISTSSHKITQUEUE_QHOST` (set on
the ssh hop), or `local (hostname)` when omitted. No `--via`. Not the
job `HOSTS` column. `watch` with `qhost:HOST` uses `ssh -t` so the
remote TTY can clear the screen.

`watch` does not stop the waiter. Ctrl-C leaves it running.

## Flags

| Flag | Meaning |
| --- | --- |
| `-q` / `--quiet` | Table only (`DISTSSHKIT_QUIET`) |
| `--progress` / `--verbose` | Keep chrome (exclusive with `-q`) |
| `--interval S` | `watch` only; default `0.5` |
| `-h` / `--help` | Queue usage |

`DISTSSHKITQUEUE_WATCH_TICKS` is a test harness (finite frames), not a
product flag.

## cancel

`:queued` is dropped. `:running` uses DistSSHKit `terminate_run!` when
the Kit output dir is known (allocated at start if submit omitted
`--output-dir`). Finished rows and unknown ids print
`cannot be cancelled` (exit 1). A successful cancel prints the id.

An `ERROR` column appears on `status` when a job has failed.
