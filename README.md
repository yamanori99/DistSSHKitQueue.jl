# DistSSHKitQueue.jl

> [!WARNING]
> **Under construction.** Do not use this.

[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/CI.yml?branch=main&label=Test)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl/graph/badge.svg)](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/jetls.yml)
[![E2E](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e.yml?branch=main&label=E2E)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e.yml)
[![E2E daily](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e-daily.yml?branch=main&label=E2E%20daily)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e-daily.yml)

[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](DESIGN.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

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
julia --project=/path/to/DistSSHKitQueue.jl -m DistSSHKitQueue cancel <id>
```

`<queue-env>` (`--project=` on `-m DistSSHKitQueue`) loads Queue. The job tree is cwd / `DISTRIBUTED_PROJECT_ROOT`.

Ctrl-C stops the waiter only. Julia **1.12+**, DistSSHKit **0.3.2+**. The waiter runs Kit `execute!(…; detached=true)`.
