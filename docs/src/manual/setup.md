# [setup](@id Manual-setup)

Write config, or wipe Queue state on this host.

```bash
julia -m DistSSHKitQueue setup [--force]
julia -m DistSSHKitQueue teardown -y
```

Also: [Prepare](@ref Tutorial-Prepare), [waiter](@ref Manual-waiter),
[hosts](@ref Manual-hosts). `setup` refuses `qhost:`. `teardown` can
run from a client (`qhost:HOST teardown -y`).

`setup` is optional. Defaults work without `config.toml`. Re-run is a
no-op unless `--force`.

## Flags

| Flag | Meaning |
| --- | --- |
| `--force` | `setup`: rewrite `config.toml` |
| `--config PATH` | `setup` / `teardown`: config path (`DISTSSHKITQUEUE_CONFIG`) |
| `-y` / `--yes` | `teardown`: confirm (`DISTSSHKIT_YES`; same values as DistSSHKit) |
| `--write-only` | `teardown`: do not stop the waiter or unload the OS unit |
| `--home DIR` | `teardown`: home for `~/.distsshkitqueue` |
| `--bindir DIR` | `teardown`: leftover `dskq` shim path |
| `-h` / `--help` | Queue usage |

`DISTSSHKITQUEUE_YES` is gone. `[env]` in the target `config.toml`
still applies.

## teardown

Stops the waiter, removes the OS unit and `~/.distsshkitqueue`. Does
not `Pkg.rm`, and never deletes a git clone or Kit `.distsshkit/`
results. Still removes a leftover `~/.local/bin/dskq` if present.

## config.toml

`~/.distsshkitqueue/config.toml`. Override:
`DISTSSHKITQUEUE_CONFIG`. Resolution: CLI / ENV > config.toml >
built-in defaults. `[env]` keys use `get!` so a real ENV value wins.

```toml
store = "~/.distsshkitqueue/jobs.toml"
# hosts = ["parent", "child:host1:4"]

[env]
# DISTRIBUTED_SSH_OPTS = "-F /path/to/ssh_config"
# DISTRIBUTED_REMOTE_PROJECT_ROOT = "/home/dev/job"
# DISTSSHKIT_YES = "1"
```

| Key | Meaning |
| --- | --- |
| `store` | Job table path (`DISTSSHKITQUEUE_STORE`) |
| `hosts` | Kit tokens; missing = allow-all; `[]` = allow none |
| `[env]` | Default ENV for this host (not `DISTSSHKITQUEUE_HOST`) |

CLI `submit` re-reads `hosts` each time
([submit](@ref Manual-submit)). Library [`submit!`](@ref) uses
`Queue(; allowed=…)` unless `follow_config=true`.
