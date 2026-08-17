# [DistSSHKitQueue.jl](@id DistSSHKitQueue.jl)

Small-lab job queue on [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is the hall:
FIFO, occupancy, and a long-lived Julia process on an always-on Mac mini.

This package is not on General yet. Read [Design](@ref Design).

## Installation

From a checkout:

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

Needs DistSSHKit **0.3**, Julia **1.12+**, plus `ssh` / `rsync` / `git` as in the kit.

## Contributing

Bugs and features: [Issues](https://github.com/yamanori99/DistSSHKitQueue.jl/issues).
See [CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/CONTRIBUTING.md).
