# DistSSHKitQueue.jl

Small-lab job queue on top of [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is the hall:
FIFO, occupancy, and a long-lived Julia process on an always-on Mac mini.

Not on General yet. Design (including the v1 API boundary): [DESIGN.md](DESIGN.md).

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

```julia
using DistSSHKitQueue
h = Hall(; slots=["mini:4", "local:2"])
submit_go!(h, "job.jl", "mini:4")
run_head(h; poll=0.2)  # on the always-on mini
```

Julia **1.12+**, DistSSHKit **0.3**. API: [DESIGN.md](DESIGN.md).
