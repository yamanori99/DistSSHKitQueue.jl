# [API](@id API)

```@meta
CurrentModule = DistSSHKitQueue
```

Submitters `using DistSSHKitQueue` or `julia -m DistSSHKitQueue submit go …`. Queue code `using DistSSHKit`. Job files for Kit `go` still do not import DistSSHKit.

CLI: `setup` / `teardown -y` / `submit go` / `submit drive` / `status` / `add-host` / `remove-host` / `list-host` / `watch` / `cancel`. Prefer `julia -m DistSSHKitQueue`. From a client: `qhost:HOST` (not `--hosts`). `add-host` / `remove-host` write config `hosts` on the queue host (no `qhost:`). `list-host` is read-only (not Kit `--hosts`): on the queue host, or `qhost:HOST list-host` from a client (`ssh -G` is the queue host's SSH config; no keys / IdentityFile). Host tokens for `submit` are `parent[:N]` / `child:NAME[:N]`. Config: `~/.distsshkitqueue/config.toml`. CLI `submit` reads `hosts`; library `submit!` uses `Queue(; allowed=…)`.

```@docs
DistSSHKitQueue
Queue
Job
submit!
cancel!
serve!
```
