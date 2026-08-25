# [waiter](@id Manual-waiter)

Run or register the FIFO process on the queue host.

```bash
julia -m DistSSHKitQueue serve [--interval S]
julia -m DistSSHKitQueue stop
julia -m DistSSHKitQueue enable [--queue-env DIR]
julia -m DistSSHKitQueue disable
```

Also: [Prepare](@ref Tutorial-Prepare), [submit](@ref Manual-submit),
[setup](@ref Manual-setup). `qhost:` is refused (`enable` is not a
client hop).

`serve` is this terminal, now. Ctrl-C stops this waiter, not a Kit job
that is already running. `enable` tells the OS to start `serve` after
reboot / login (LaunchAgent / systemd).

## Flags

| Flag | Meaning |
| --- | --- |
| `--interval S` | `serve` poll interval (default `0.2`) |
| `--queue-env DIR` | `enable`: Queue env in the OS unit (`julia --project=` there) |
| `--julia PATH` | `enable`: Julia binary in that unit |
| `--write-only` | `enable` / `disable`: write or remove the unit file without `launchctl` / `systemctl` |
| `-h` / `--help` | Queue usage |

`enable --project` is refused. The job tree stays cwd /
`DISTRIBUTED_PROJECT_ROOT`.

A dedicated env at `~/.distsshkitqueue/env`, if present, is the default
`--queue-env`. Prefer that so a checkout can be deleted.

## stop

Halts the waiter, keeps config / store / OS unit. Latches
(`jobs.toml.stopped`) so `submit` will not auto-start; only an explicit
`serve` resumes. Clients can `qhost:HOST stop`.

`disable` removes the OS unit. It does not delete the job table.
