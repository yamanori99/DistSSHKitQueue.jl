# [status](@id Manual-status)

Read the table, watch it live, or cancel a row. The table lives on the
queue host.

```bash
julia --project=. -m DistSSHQueue [qhost:HOST] status [-q]
julia --project=. -m DistSSHQueue [qhost:HOST] watch [-q] [--interval S]
julia --project=. -m DistSSHQueue [qhost:HOST] cancel <id>
julia --project=. -m DistSSHQueue [qhost:HOST] fetch <id>
```

Also: [First job](@ref Tutorial-Client), [submit](@ref Manual-submit),
[User Guide](@ref Manual), [fetch](@ref Manual-fetch).

`status` / `watch` share one Store table (`path` / `serve` / `qhost`).
`watch` with `qhost:HOST` uses `ssh -t` when this stdout is a TTY so the
remote can clear the screen. A pipe (no TTY) prints a compact
`serve` / `running` / `queued` line; use `status` for the history table.

`watch` does not stop `serve`. Ctrl-C leaves it running.

## Flags

| Flag | Meaning |
| --- | --- |
| `-q` / `--quiet` | Table only (`DISTSSHKIT_QUIET`) |
| `--progress` / `--verbose` | Keep chrome (exclusive with `-q`) |
| `--interval S` | `watch` only; default `0.5` |
| `-h` / `--help` | Queue usage |

`DISTSSHQUEUE_WATCH_TICKS` is a test harness (finite frames), not a
product flag.

## cancel

`:queued` is dropped. `:running` uses DistSSHKit `terminate_run!` when
the Kit output dir is known (allocated at start if submit omitted
`--output-dir`). Finished rows and unknown ids print
`cannot be cancelled` (exit 1). A successful cancel prints the id.

An `ERROR` column appears on `status` when a job has failed.

## fetch

After the row is `:done` / `:failed` / `:cancelled` with a Kit leaf,
[`fetch`](@ref Manual-fetch) copies that leaf onto this job tree.
