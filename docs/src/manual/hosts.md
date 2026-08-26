# [hosts](@id Manual-hosts)

Lab inventory and DistSSHKit `size` on the queue host. These verbs do
not enqueue. Not Kit `--hosts` (that still names workers on `go` /
`drive`).

```bash
julia -m DistSSHQueue add-host parent child:host1
julia -m DistSSHQueue list-host
julia -m DistSSHQueue size
julia -m DistSSHQueue remove-host child:host1
```

From a **client**, `list-host` and `size` are forwarded like `status`.
`add-host` / `remove-host` run on the queue host only (like `setup`).

Also: [Prepare](@ref Tutorial-Prepare), [submit](@ref Manual-submit),
[kit size](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/size/).

## add-host / remove-host

Write Kit tokens into config `hosts`
(`parent[:N]` / `child:NAME[:N]`). Optional `:N` is a per-name max.
Bare `host1` is not a token.

| | |
| --- | --- |
| Missing `hosts` | Allow all names |
| First `add-host` | Creates the list (submit is no longer allow-all) |
| `hosts = []` | Last `remove-host`; submit accepts none |
| Leftover `allowed` | Still read until rewritten to `hosts` |

No `serve` restart. Next [`submit`](@ref Manual-submit) re-reads the
file. A `:running` Kit job is not stopped.

## list-host

Read-only: host tokens (`parent` / `child:NAME`) plus `ssh -G` Host /
HostName / User / Port. No private keys or IdentityFile. `ssh -G` runs
on the queue host, not on the client.

```bash
julia -m DistSSHQueue qhost:mini list-host
```

## size

DistSSHKit `size` on the queue host (cwd / project). Omit tokens to size
config `hosts`. Does not enqueue. Prints a `submit drive` template.

```bash
julia -m DistSSHQueue qhost:mini size
julia -m DistSSHQueue qhost:mini size --gb-per-worker 1.5 parent child:host1
```

Kit flags (`--probe`, `--gb-per-worker`, …):
[kit size](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/size/).
`size --help` adds a Queue note under the Kit help.
