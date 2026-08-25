# [API](@id API)

```@meta
CurrentModule = DistSSHKitQueue
```

Submitters `using DistSSHKitQueue` or `julia -m DistSSHKitQueue submit go …`. Queue code `using DistSSHKit`. Job files for Kit `go` still do not import DistSSHKit.

CLI: `setup` / `teardown -y` / `submit go` / `submit drive` / `status` / `add-host` / `remove-host` / `list-host` / `size` / `watch` / `cancel`. Prefer `julia -m DistSSHKitQueue`. From a client: `qhost:HOST` (not `--hosts`). `add-host` / `remove-host` write config `hosts` on the queue host (no `qhost:`). Tokens are Kit's (`parent[:N]` / `child:NAME[:N]`). Do not restart `serve`; the next `submit` re-reads the file. `list-host` is read-only (not Kit `--hosts`): on the queue host, or `qhost:HOST list-host` from a client (`ssh -G` is the queue host's SSH config; no keys / IdentityFile). `size` is DistSSHKit `size` on the queue host (`qhost:HOST size`; omit tokens to use config `hosts`). `cancel` of `:running` uses the Kit output dir (allocated at start if submit omitted `--output-dir`). Host tokens for `submit` are `parent[:N]` / `child:NAME[:N]`. Config: `~/.distsshkitqueue/config.toml`. CLI `submit` uses `follow_config`; library `submit!` uses `Queue(; allowed=…)`.

```@docs
DistSSHKitQueue
Queue
Job
submit!
cancel!
serve!
```
