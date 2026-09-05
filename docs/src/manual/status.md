# [status](@id Manual-status)

Read the table, watch it live, or cancel a row. The table lives on the
queue host.

```bash
julia --project=. -m DistSSHQueue [qhost:HOST] status [-q] [--interval S]
julia --project=. -m DistSSHQueue [qhost:HOST] watch [-q] [--interval S]
julia --project=. -m DistSSHQueue [qhost:HOST] cancel <id>
julia --project=. -m DistSSHQueue [qhost:HOST] fetch <id>
```

Also: [First job](@ref Tutorial-Client), [submit](@ref Manual-submit),
[User Guide](@ref Manual), [fetch](@ref Manual-fetch).

`status` / `watch` share one Store table (`path` / `serve` / `enable` /
`qhost`). `path` is the store file, or `none` when it is missing
(teardown / never submitted). Via `qhost:HOST`, `path` is
`HOST:~/.distsshqueue/jobs.toml` so `~` is not this laptop. `Jobs
(empty)` is a live store with zero rows; `(none)` is no file. `serve`
is the live process (`running` / `stopped` / `none`). `enable` is the
OS unit file on this host (LaunchAgent / systemd), or `none`. After
`qhost:` those paths are the queue host's.
Bare `status` is a snapshot. `watch` is `status --interval` (default
`0.5`). Live with `qhost:HOST` uses `ssh -t` when this stdout is a TTY
so the remote can clear the screen. A pipe without `-q` prints a compact
`serve` / `running` / `queued` line; `-q` on a pipe is still the table.
How the table file is locked and rewritten:
[User Guide · Job record](@ref Manual-job-record).

Live does not stop `serve`. Ctrl-C leaves it running.

## Flags

| Flag | Meaning |
| --- | --- |
| `-q` / `--quiet` | Table only (`DISTSSHKIT_QUIET`) |
| `--progress` / `--verbose` | Keep chrome (exclusive with `-q`) |
| `--interval S` | Live redraw (`watch` default `0.5`) |
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
