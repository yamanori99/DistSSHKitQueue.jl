# DistSSHKitQueue.jl

Small-lab job queue on top of [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is FIFO, occupancy, and a long-lived Julia process on an always-on Mac mini.

Not on General yet. Public names are **placeholders** until the CLI exists. Design: [DESIGN.md](DESIGN.md).

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

```julia
using DistSSHKitQueue
h = Placeholder(; slots=["mini:4", "local:2"])
placeholder!(h, "job.jl", "mini:4")
placeholder!(h, "job.jl", "mini:4"; drive=true)
placeholder_head(h; poll=0.2)  # on the always-on mini
```

Julia **1.12+**, DistSSHKit **0.3**. API: [DESIGN.md](DESIGN.md).
