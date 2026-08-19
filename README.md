# DistSSHKitQueue.jl

> [!WARNING]
> **Under construction.** Do not use this.

[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/CI.yml?branch=main&label=Test)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/CI.yml)
[![E2E](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e.yml?branch=main&label=E2E)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e.yml)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/jetls.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl/graph/badge.svg)](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl)

Small-lab job queue on top of [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a long-lived waiter on an always-on controller (FIFO, one table job).

Not on General yet. Design: [DESIGN.md](DESIGN.md).

```julia
pkg> dev /path/to/DistSSHKitQueue.jl
```

```bash
# waiter env = this checkout (smoke)
julia --project=. -m DistSSHKitQueue serve
julia --project=. -m DistSSHKitQueue status
# job tree = wherever you cd
cd /path/to/YourJob.jl
julia --project=/path/to/DistSSHKitQueue.jl -m DistSSHKitQueue submit go SCRIPT.jl local:1
```

`<queue-env>` (`--project=` on `-m DistSSHKitQueue`) loads Queue. The job tree is cwd / `DISTRIBUTED_PROJECT_ROOT`.

Ctrl-C stops the waiter only. Julia **1.12+**, DistSSHKit **0.3.1+**.
