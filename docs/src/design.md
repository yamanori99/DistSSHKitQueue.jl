# [Design](@id Design)

The living design note is [`DESIGN.md`](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/DESIGN.md) at the repo root.

Queue verbs: `setup`, `serve`, `status`, `submit`, `cancel`, `service`. After `submit`, Kit argv (`go` / `drive`). Job tree is cwd / `DISTRIBUTED_PROJECT_ROOT`, not `<queue-env>`. Waiter: DistSSHKit `execute!(…; detached=true)`. Config: `~/.distsshkitqueue/config.toml`. Julia: `Queue`, `submit!`, `cancel!`, `serve!`.
