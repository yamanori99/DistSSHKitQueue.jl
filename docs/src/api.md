# [API](@id API)

```@meta
CurrentModule = DistSSHKitQueue
```

Submitters `using DistSSHKitQueue` or `julia -m DistSSHKitQueue submit go …`. Queue code `using DistSSHKit`. Job files for Kit `go` still do not import DistSSHKit.

CLI: `submit go` / `submit drive`. Julia: `submit!(q, script, hosts...; kind=:drive)`.

```@docs
DistSSHKitQueue
Queue
Job
submit!
cancel!
serve!
```
