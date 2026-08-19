# DistSSHKitQueue.jl

Small-lab job queue on top of [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a long-lived waiter on an always-on Mac mini (FIFO, one table job).

Not on General yet. Design: [DESIGN.md](DESIGN.md).

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

```bash
julia --project=. -m DistSSHKitQueue serve
julia --project=. -m DistSSHKitQueue status
julia --project=. -m DistSSHKitQueue go SCRIPT.jl local:1
```

Ctrl-C stops the waiter only. Julia **1.12+**, DistSSHKit **0.3.1+**.
