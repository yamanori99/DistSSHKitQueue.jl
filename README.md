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
# controller, once (from the Queue checkout)
julia --project=. -m DistSSHKitQueue setup --service
# orderer (non-interactive ssh: use the absolute shim)
ssh controller ~/.local/bin/dskq submit go SCRIPT.jl local:1
ssh controller ~/.local/bin/dskq status
ssh controller ~/.local/bin/dskq cancel <id>
```

`setup` writes `~/.local/bin/dskq` (julia + `--project` baked in) and `~/.distsshkitqueue/config.toml` if missing. `[env]` is applied at start (existing ENV wins). Store: config `store=` or `DISTSSHKITQUEUE_STORE` (default `~/.distsshkitqueue/jobs.toml`).

Like Kit: `submit` starts a waiter itself if none is watching the store (opt out: `DISTSSHKITQUEUE_NO_AUTOSERVE=1`). `serve` / `service install` are for a long-lived controller.

`<queue-env>` loads Queue. The job tree is cwd / `DISTRIBUTED_PROJECT_ROOT`. Julia 1.12 Pkg Apps: `[apps] dskq` (`pkg> app add .` → `~/.julia/bin/dskq`).

`setup` bakes `--project` from the environment active when it runs (a dev checkout, by default) — remove that checkout and `dskq` breaks. To decouple, set up `~/.distsshkitqueue/env` once and re-run `setup` (from anywhere); it is preferred automatically whenever present:

```bash
julia --project=~/.distsshkitqueue/env -e 'using Pkg; Pkg.develop(path="/path/to/DistSSHKitQueue.jl"); Pkg.instantiate()'
julia --project=~/.distsshkitqueue/env -m DistSSHKitQueue setup --service
```

Once DistSSHKitQueue is on General, `Pkg.develop` above becomes `Pkg.add("DistSSHKitQueue")` and no local checkout is needed at all.

Ctrl-C stops the waiter only. Julia **1.12+**, DistSSHKit **0.3.2+**. The waiter runs Kit `execute!(…; detached=true)`.
