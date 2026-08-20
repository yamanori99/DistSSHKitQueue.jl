# [DistSSHKitQueue.jl](@id DistSSHKitQueue.jl)

!!! warning "Under construction. Do not use this."

Small-lab job queue on [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a long-lived waiter (FIFO, one table job).

This package is not on General yet. Read [Design](@ref Design).

## CLI

```bash
julia --project=<queue-env> -m DistSSHKitQueue setup --service
dskq status
cd /work/Thesis.jl
dskq submit go SCRIPT.jl worker:4
dskq submit drive local:2 SCRIPT.jl
dskq cancel <id>
```

`setup` writes `~/.local/bin/dskq` and `~/.distsshkitqueue/config.toml` if missing. `submit` / `cancel` write the store and exit. The job tree is cwd / `DISTRIBUTED_PROJECT_ROOT`. Bare `go` / `drive` alias `submit`. The waiter calls DistSSHKit `execute!(…; detached=true)`. Non-interactive ssh: `~/.local/bin/dskq`.

## Installation

From a checkout:

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

Needs DistSSHKit **0.3.2+**, Julia **1.12+**, plus `ssh` / `rsync` / `git` as in DistSSHKit.

## Contributing

Bugs and features: [Issues](https://github.com/yamanori99/DistSSHKitQueue.jl/issues).
See [CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/CONTRIBUTING.md).
