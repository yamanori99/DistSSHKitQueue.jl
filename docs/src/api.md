# [API](@id API)

```@meta
CurrentModule = DistSSHKitQueue
```

Submitters `using DistSSHKitQueue` or `julia -m DistSSHKitQueue submit go …`. Queue code `using DistSSHKit`. Job files for Kit `go` still do not import DistSSHKit.

CLI: `setup` / `teardown -y` / `submit go` / `submit drive` / `status` / `allowed` / `watch` / `cancel`. Prefer `julia -m DistSSHKitQueue`. Client hop: `qhost:HOST` (not `--hosts`). Julia: `submit!(q, script, hosts...; kind=:drive)`. Waiter: DistSSHKit **0.4.1+** `execute!(…; detached=true, job_id=…)`. Placement tokens are `parent[:N]` / `child:NAME[:N]`. Config: `~/.distsshkitqueue/config.toml` (`allowed` is optional Kit SSH names; CLI `submit` reads it, library `submit!` uses `Queue(; allowed=…)`). `allowed` prints `ssh -G` Host / HostName / User / Port.

```@docs
DistSSHKitQueue
Queue
Job
submit!
cancel!
serve!
```
