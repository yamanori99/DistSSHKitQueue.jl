# [API](@id API)

```@meta
CurrentModule = DistSSHKitQueue
```

Submitters `using DistSSHKitQueue` or `julia -m DistSSHKitQueue submit go …`. Queue code `using DistSSHKit`. Job files for Kit `go` still do not import DistSSHKit.

CLI: `setup` / `teardown -y` / `submit go` / `submit drive` / `status` / `watch` / `cancel`. Prefer `julia -m DistSSHKitQueue`. Julia: `submit!(q, script, hosts...; kind=:drive)`. Waiter: DistSSHKit `execute!(…; detached=true)`. Config: `~/.distsshkitqueue/config.toml`.

```@docs
DistSSHKitQueue
Queue
Job
submit!
cancel!
serve!
```
