# [DistSSHKitQueue.jl](@id DistSSHKitQueue.jl)

!!! warning "Under construction. Do not use this."

Small-lab job queue on [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a FIFO waiter in
front of it: one **queue host** holds the table and the waiter; **clients** enqueue,
list, watch, and cancel.

Not on General yet. Julia **1.12+**, DistSSHKit **0.4.1+**. Placement tokens
(`parent[:N]` / `child:NAME[:N]`) stay DistSSHKit's — see the
[kit docs](https://yamanori99.github.io/DistSSHKit.jl/dev/). Concept diagram and the
full verb table: [README](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/README.md).

## Client

From the job directory. `qhost:HOST` names the queue host (like Kit `child:NAME`).
One lab: `export DISTSSHKITQUEUE_HOST=…` and omit `qhost:` (the token still wins).
`--hosts` / `--julia` stay on Kit `go` / `drive`.

```bash
julia --project=. -m DistSSHKitQueue --version
julia --project=. -m DistSSHKitQueue qhost:HOST list-host
julia --project=. -m DistSSHKitQueue qhost:HOST size
julia --project=. -m DistSSHKitQueue qhost:HOST submit go child:host1:4 SCRIPT.jl
julia --project=. -m DistSSHKitQueue qhost:HOST status -q
julia --project=. -m DistSSHKitQueue qhost:HOST watch
julia --project=. -m DistSSHKitQueue qhost:HOST cancel <id>
```

`submit` starts a waiter on the queue host if none is running. `status` / `watch`
print that `qhost` (or `local (hostname)`). There is no `--via`. `watch` is a live
table (Ctrl-C); it does not stop the waiter.

## Queue host

Always-on box (not a sleeping laptop). `setup` / `serve` / `enable` / `disable` /
`add-host` / `remove-host` refuse `qhost:`.

```bash
julia -m DistSSHKitQueue setup
julia -m DistSSHKitQueue add-host parent child:host1
julia -m DistSSHKitQueue enable --queue-env ~/.distsshkitqueue/env
julia -m DistSSHKitQueue serve
julia -m DistSSHKitQueue teardown -y
```

`--queue-env` is the env that loads Queue in the OS unit, not Julia `--project=` /
the job tree. `teardown` confirms like DistSSHKit (`DISTSSHKIT_YES`). The waiter
calls DistSSHKit `execute!(…; detached=true, job_id=…)`.

## Installation

From a checkout:

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

Needs DistSSHKit **0.4.1+** from General (do not `Pkg.develop` Kit for ordinary
Queue work), Julia **1.12+**, plus `ssh` / `rsync` / `git` as in DistSSHKit.

## Contributing

Bugs and features: [Issues](https://github.com/yamanori99/DistSSHKitQueue.jl/issues).
See [CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/CONTRIBUTING.md).
