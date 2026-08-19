# [Design](@id Design)

The living design note is [`DESIGN.md`](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/DESIGN.md) at the repo root.

Queue verbs: `serve`, `status`, `submit`. After `submit`, Kit argv (`go` / `drive`). Job tree is cwd / `DISTRIBUTED_PROJECT_ROOT`, not `<queue-env>`. Julia: `Queue`, `submit!`, `serve!`.
