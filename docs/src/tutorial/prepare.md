# [Prepare](@id Tutorial-Prepare)

First-time **queue host** before a [First job](@ref Tutorial-Client).
Clients can skip this page if someone already set that box up.

Also see [Requirements](@ref), [Where files live](@ref Layout),
[User Guide · setup](@ref Manual-setup),
[Introduction](@ref DistSSHKitQueue.jl).

`setup` / `serve` / `enable` / `disable` / `add-host` / `remove-host`
refuse `qhost:` — log in to the queue host and run them there.

## Install Queue

Once, in `~/.distsshkitqueue/env` (`qhost:` and `enable` default):

```bash
mkdir -p ~/.distsshkitqueue/env
cd ~/.distsshkitqueue/env
julia --project=.
```

```julia
pkg> add https://github.com/yamanori99/DistSSHKitQueue.jl#v0.1.0-beta.1
```

That pulls DistSSHKit **0.4.1+** from General. `setup` does not create
that env (it would run `Pkg` as a side effect). A different dir is
`--queue-env DIR` on `enable` and on client `qhost:`. `--queue-env @` is
the remote default Julia env (no `--project=`).

## Config and inventory

```bash
cd ~/.distsshkitqueue/env
julia --project=. -m DistSSHKitQueue setup
julia --project=. -m DistSSHKitQueue add-host parent child:host1
julia --project=. -m DistSSHKitQueue list-host
```

`setup` writes `~/.distsshkitqueue/config.toml` if missing (`--force`
rewrites). Defaults work without it. Use it for `store=` or `[env]`.

`add-host` writes Kit tokens into config `hosts`
(`parent[:N]` / `child:NAME[:N]`). First add creates the list (submit is
no longer allow-all). Optional `:N` is a max. No `serve` restart: the
next `submit` re-reads the file.

Workers still need DistSSHKit `setup` (rsync or clone, then instantiate)
from the **queue host**, not from Queue, **from that job's clone**
(`~/org/Repo.jl`). Leave `DISTRIBUTED_REMOTE_PROJECT_ROOT` unset in
queue `config.toml` so Kit uses `~/parent/Repo.jl` per clone.
[kit Prepare](https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/prepare/).

## Survive reboot (optional)

```bash
julia --project=. -m DistSSHKitQueue enable --queue-env ~/.distsshkitqueue/env
```

`--queue-env` is the env that loads Queue in the OS unit, not Julia
`--project=` / the Kit project. After that, clients only `submit`. You do
not leave a `serve` terminal open.

Foreground, this session only:

```bash
julia --project=. -m DistSSHKitQueue serve
```

Next: [First job](@ref Tutorial-Client).
