# [DistSSHKitQueue.jl](@id DistSSHKitQueue.jl)

!!! warning "Under construction. Do not use this."

Small-lab job queue on [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a long-lived waiter (FIFO, one table job).

This package is not on General yet. Public Julia names are placeholders. Read [Design](@ref Design).

## CLI

```bash
julia --project=Lab.jl -m DistSSHKitQueue serve
julia --project=Lab.jl -m DistSSHKitQueue status
julia --project=Lab.jl -m DistSSHKitQueue submit go SCRIPT.jl worker:4
julia --project=Lab.jl -m DistSSHKitQueue submit drive local:2 SCRIPT.jl
```

`submit` writes the store and exits. It does not run DistSSHKit. Bare `go` / `drive` are aliases of `submit go` / `submit drive`.

## Installation

From a checkout:

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

Needs DistSSHKit **0.3.1+**, Julia **1.12+**, plus `ssh` / `rsync` / `git` as in DistSSHKit.

## Contributing

Bugs and features: [Issues](https://github.com/yamanori99/DistSSHKitQueue.jl/issues).
See [CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/CONTRIBUTING.md).
