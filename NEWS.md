# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- `teardown` confirms like DistSSHKit: `-y` / `--yes` / `DISTSSHKIT_YES` (`1` / `true` / `yes` / `on`).
  `DISTSSHKITQUEUE_YES` is gone. `[env]` in the target `config.toml` still applies.
- `julia -m DistSSHKitQueue --version` (`-v`, `-V`) prints Queue then DistSSHKit.
  `submit go -v` stays Kit only.
- `status` / `watch` print the client `qhost:` token via `DISTSSHKITQUEUE_QHOST`
  (set on the ssh hop). No `--via` flag. Omit `qhost:` → `local (hostname)`.
- `go --hosts` / `go --julia` (and `submit go` / `submit drive`) stay DistSSHKit's:
  Queue does not peel them as the queue hop (`qhost:` / `--remote-julia`).
  A Kit-shaped line with a `.jl` and no Queue verb is `go` (`--hosts child:w:2 SCRIPT.jl`).
  `enable --julia` is still the unit binary.
- Testenv Docker / Apple SSH boxes are Compose `child-1` / `child-2` (Apple
  containers `dskq-child-*` so they can sit next to Kit). Peer DNS is
  `dev@child-1`. Examples use `child:host1`, not `child:worker`. Image tags stay
  `dskq-linux-ssh-worker`. Controller aliases stay `dskq-w1` / `dskq-w2`.
- `:running` cancel and waiter restart no longer need the submitter to pass `--output-dir`. At start the waiter records DistSSHKit `allocate_output_dir` (or the given `output_dir`) on the row so `terminate_run!` / `kit.pid` have a path.
- CLI `add-host` / `remove-host` write config `hosts` on the queue host (not via `qhost:`). Tokens are DistSSHKit's: `parent[:N]` / `child:NAME[:N]` (not a bare `host1`). Optional `:N` is a per-name max; a larger submit `:N` is refused. First add creates the list. Missing key stays allow-all. Empty array allows none. A leftover `allowed` key is still read until rewritten. Hand-edit still works. Do not restart `serve`: the next `submit` re-reads the file. A Kit job that is already `:running` is not stopped. `:queued` rows still start if a name is later removed. CLI `submit` uses `follow_config`; library `submit!` uses `Queue(; allowed=…)` unless `follow_config=true`.
- Read-only CLI `list-host` (not Kit `--hosts`): prints that list as host tokens (`parent` / `child:NAME`) plus `ssh -G` Host / HostName / User / Port. No private keys, no IdentityFile. On the queue host: `list-host`. From a client: `qhost:HOST list-host` (`ssh -G` uses the queue host's SSH config).
- CLI `size`: DistSSHKit `size` on the queue host (job tree, same flags: `parent` / `child:NAME`, `--gb-per-worker`, `--probe`, …). Omit tokens to size config `hosts`. `qhost:HOST size`. Does not enqueue; prints a `submit drive` template. Not a submit gate.
- Client queue host is `qhost:NAME` (like Kit `child:NAME`). `--qhost` is refused. `--hosts` / `--julia` stay on Kit `go` / `drive`. Queue-host Julia remains `--remote-julia` / `JULIA_DISTRIBUTED_EXE`.
- DistSSHKit **0.4.1+** from General is the Queue floor (docs, CONTRIBUTING, examples, tests). Do not `Pkg.develop` Kit for ordinary Queue work. Library `submit!` rejects pre-0.4 host tokens (`parenthost`, bare `NAME:N`). `qhost:` is DistSSHKit `run_on_host` only (no second ssh builder).
- DistSSHKit **0.4.1+** ([release](https://github.com/yamanori99/DistSSHKit.jl/releases/tag/v0.4.1)): queued `go` with `job_id` actually runs the slot script (`-L` mark file). 0.4.0 skipped the script because of `--eval`.
- SSH E2E (controller + worker image) is Julia slot **max** (today 1.13), same pair as DistSSHKit. Compat floor stays 1.12.
- DistSSHKit **0.4.1+**: `execute_detached_accepts` / `execute_kwargs_from_parsed` / `host_tokens`, `kit_pid_file_running`, `kit_result_from_dir` on waiter restart, `terminate_run!` for `:running` cancel, `qhost:` via `run_on_host`. Go/drive tokens are `parent[:N]` and `child:NAME[:N]` (`parenthost` / bare `host:N` are gone).
- `status` / `watch` print `qhost`: the client `qhost:` token (forwarded as `--via`) plus the queue host's hostname, or `local (hostname)` when omitted. Not the job `HOSTS` column.
- Autoserve: spawn `serve` via `sh -c … &` so `submit` can exit. Client `qhost:HOST submit` was hanging after `Started waiter` because `run(...; wait=false)` kept a libuv handle on the waiter. Tests set `DISTSSHKITQUEUE_SERVE_TAG` / `DISTSSHKITQUEUE_TEST_PIDS` so an interrupted `Pkg.test` still SIGTERMs those waiters; production leaves both unset.
- README / `--help`: the product path is a dedicated queue host plus client `qhost:HOST`. Omit it only when you are already on that box. Kit `submit go` argv is DistSSHKit order (`parent[:N]` / `child:NAME[:N]` then `SCRIPT.jl`).
- SSH E2E covers those CLI verbs over real OpenSSH (`qhost:` to a loopback queue host) and DistSSHKit docker-ssh workers. `enable` / `disable` / `teardown` use `--write-only` so CI does not touch the runner’s user systemd / LaunchAgent.
- `watch` reprints the job table until Ctrl-C (`--interval`, default 0.5s). Same verb on the queue host and via `qhost:` (`ssh -t` when the local stdout is a TTY). Does not stop the waiter.
- Drop the `dskq` PATH shim and Pkg Apps entry. Use `julia -m DistSSHKitQueue`. `setup` writes `config.toml` only; `teardown` still removes a leftover `~/.local/bin/dskq`.
- CLI errors (`ArgumentError`) print as `Error: ...` on stderr, not a Julia stacktrace. `submit go/drive` checks the script exists before enqueuing (was silently queued, then failed). `cancel` prints `cannot be cancelled` for an unknown id, a finished row, or `:running` without a known output dir. `status` shows an `ERROR` column when a job has failed.
- `stop` halts the waiter but keeps config / store / OS unit. It latches (`jobs.toml.stopped`) so `submit` will not auto-start; only an explicit `serve` resumes. Runs locally or via `qhost:HOST`.
- CLI chrome matches DistSSHKit (`--help` sections, `~` paths, colored `status` table). Job ids stay a bare stdout line.
- `~/.distsshkitqueue/config.toml` (`store` + `[env]`; ENV wins). CLI `setup` (re-run is a no-op unless `--force`). OS unit: `enable` / `disable` (was `service install` / `uninstall`).
- `submit` starts a waiter itself if none is watching the store, like Kit `go!` (opt out: `DISTSSHKITQUEUE_NO_AUTOSERVE=1`). `serve` gets a pidfile next to the store.
- `qhost:HOST` before the verb (`qhost:HOST status` / `submit` / `cancel`) picks the queue host. Remote Julia uses Kit auto-detect; `--remote-julia` / `JULIA_DISTRIBUTED_EXE` override. The client stays stateless.
- `teardown -y` stops the waiter and removes the OS unit and `~/.distsshkitqueue` (not a git clone or `Pkg.rm`).
- Client vs queue-host verbs: `qhost:` is client-only; `setup` / `serve` / `enable` / `disable` refuse it. Source: `src/client/` and `src/qhost/`.
- Waiter runs DistSSHKit `execute!(kind; detached=true)` (`KitRunResult`). CLI `cancel <id>` (`:queued`, or `:running` via `terminate_run!`). Optional `enable` (LaunchAgent / systemd user). DistSSHKit **0.4.1+**.
- CI: Kit-shaped Julia slots (`min` / `max` / `tip`). JETLS min plus `JULIA_SLOT_JETLS_MAX` (~1.13). Codecov `pkgtest` on main push (max slot); E2E `e2e` on cut PRs and **E2E daily** Linux. Docs-only PRs skip heavy steps (`ci-heavy`). **CI weekly** (Sunday) is not a PR check. GHCR worker image. Not registered.
- Design: waiter is `serve`; clients use Kit `go` / `drive` argv. FIFO one table job.
- Names: `Queue`, `Job`, `submit!` / CLI `submit`, `cancel` / `cancel!`, `job` / `jobs`, `serve!` (`--interval`).
  Not registered.
