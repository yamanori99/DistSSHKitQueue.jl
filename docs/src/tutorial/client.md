# [First job](@id Tutorial-Client)

Submit from a **client** after the queue host is up
([Prepare](@ref Tutorial-Prepare)). Also see
[User Guide · submit](@ref Manual-submit), [status](@ref Manual-status).

## Point at the queue host

Run from the job directory (`julia --project=.`). Queue must be loadable
from that env.

```bash
julia --project=. -m DistSSHKitQueue qhost:mini list-host
julia --project=. -m DistSSHKitQueue qhost:mini size
```

One lab: `export DISTSSHKITQUEUE_HOST=mini` and omit `qhost:` (the token
still wins). Several clusters: pass `qhost:` each time.

`list-host` is not Kit `--hosts`. `ssh -G` runs on the queue host.
`size` is DistSSHKit `size` there (does not enqueue).

## Submit

Kit argv is DistSSHKit's (`go child:NAME:N SCRIPT.jl`, or `parent:N`
when workers are on the queue host). Flags:
[kit go](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/go/),
[kit drive](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/drive/).

```bash
julia --project=. -m DistSSHKitQueue qhost:mini submit go child:host1:4 SCRIPT.jl
julia --project=. -m DistSSHKitQueue qhost:mini status
julia --project=. -m DistSSHKitQueue qhost:mini watch
julia --project=. -m DistSSHKitQueue qhost:mini cancel <id>
```

`submit` starts a waiter if none is running. `status` / `watch` print
`qhost` (or `local (hostname)` when you omitted it). `watch` redraws
until Ctrl-C; it does not stop the waiter. Job ids print as a bare
stdout line.

Bare `go` / `drive` alias `submit go` / `submit drive`. A Kit-shaped
line with a `.jl` and no Queue verb is `go`.

There is no `--via`. Do not pass `qhost:` to `setup` / `serve` /
`enable` / `disable` / `add-host` / `remove-host`.

Next: [User Guide](@ref Manual).
