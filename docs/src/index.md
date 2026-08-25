# [DistSSHKitQueue.jl](@id DistSSHKitQueue.jl)

!!! warning "Under construction. Do not use this."

Small-lab job queue on [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a long-lived waiter (FIFO, one table job).

This package is not on General yet. See the [README](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/README.md#concept) for the concept diagram.

## CLI

**Client** (dev laptop):

```bash
julia --project=. -m DistSSHKitQueue --qhost HOST status
julia --project=. -m DistSSHKitQueue --qhost HOST watch
julia --project=. -m DistSSHKitQueue --qhost HOST submit go child:worker:4 SCRIPT.jl
julia --project=. -m DistSSHKitQueue --qhost HOST cancel <id>
```

**Queue host** (always-on):

```bash
julia -m DistSSHKitQueue setup
julia -m DistSSHKitQueue serve
julia -m DistSSHKitQueue enable
julia -m DistSSHKitQueue teardown -y
```

`--qhost` is client-only. `setup` / `serve` / `enable` / `disable` refuse it. Omit `--qhost` only when you are already on the queue host (not a sleeping laptop). `status` / `watch` print that qhost (or `local` plus hostname). `submit` auto-starts the waiter. The waiter calls DistSSHKit `execute!(…; detached=true, job_id=…)`.

## Installation

From a checkout:

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

Needs DistSSHKit **0.4.1+** from General (a hard dependency; do not `Pkg.develop` Kit for ordinary Queue work), Julia **1.12+**, plus `ssh` / `rsync` / `git` as in DistSSHKit.

## Contributing

Bugs and features: [Issues](https://github.com/yamanori99/DistSSHKitQueue.jl/issues).
See [CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/CONTRIBUTING.md).
