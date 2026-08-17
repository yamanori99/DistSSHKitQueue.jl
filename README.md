# DistSSHKitQueue.jl

Small-lab job queue on top of [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is the hall:
FIFO, occupancy, and a long-lived Julia process on an always-on Mac mini.

Not on General yet. Design: [DESIGN.md](DESIGN.md).

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

Julia **1.12+**, DistSSHKit **0.3**.
