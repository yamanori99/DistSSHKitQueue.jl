# [DistSSHKitQueue.jl](@id DistSSHKitQueue.jl)

!!! warning "Under construction. Do not use this."

Small-lab job queue on [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a long-lived waiter (FIFO, one table job).

This package is not on General yet. Read [Design](@ref Design).

## CLI

**Client** (dev laptop):

```bash
julia --project=. -m DistSSHKitQueue --qhost HOST status
julia --project=. -m DistSSHKitQueue --qhost HOST watch
julia --project=. -m DistSSHKitQueue --qhost HOST submit go SCRIPT.jl worker:4
julia --project=. -m DistSSHKitQueue --qhost HOST cancel <id>
```

**Queue host** (always-on):

```bash
julia -m DistSSHKitQueue setup [--service]
julia -m DistSSHKitQueue serve
julia -m DistSSHKitQueue teardown -y
```

`--qhost` is client-only. `setup` / `serve` / `service` refuse it. Same machine: omit `--qhost`. `submit` auto-starts the waiter. The waiter calls DistSSHKit `execute!(…; detached=true)`.

## Installation

From a checkout:

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

Needs DistSSHKit **0.3.2+**, Julia **1.12+**, plus `ssh` / `rsync` / `git` as in DistSSHKit.

## Contributing

Bugs and features: [Issues](https://github.com/yamanori99/DistSSHKitQueue.jl/issues).
See [CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/CONTRIBUTING.md).
