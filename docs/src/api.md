# [API](@id API)

```@meta
CurrentModule = DistSSHKitQueue
```

Submitters `using DistSSHKitQueue` or `julia -m DistSSHKitQueue submit go …`.
Queue code `using DistSSHKit`. Job files for Kit `go` still do not import DistSSHKit.

Prefer `julia -m DistSSHKitQueue`. From a client: `qhost:HOST` (not `--hosts`).
Default hop: `DISTSSHKITQUEUE_HOST`. `add-host` / `remove-host` write config `hosts`
on the queue host (Kit tokens `parent[:N]` / `child:NAME[:N]`). Do not restart
`serve`; the next `submit` re-reads the file. `list-host` is read-only (not Kit
`--hosts`). `size` is DistSSHKit `size` on the queue host. `cancel` of `:running`
uses the Kit output dir (allocated at start if submit omitted `--output-dir`).
CLI `submit` uses `follow_config`; library `submit!` uses `Queue(; allowed=…)`
unless `follow_config=true`. Config: `~/.distsshkitqueue/config.toml`.

Library surface:

```@docs
DistSSHKitQueue
Queue
Job
submit!
cancel!
serve!
```
