# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- Autoserve: spawn `serve` via `sh -c … &` so `submit` can exit. Client `--qhost submit` was hanging after `Started waiter` because `run(...; wait=false)` kept a libuv handle on the waiter.
- README / `--help`: the product path is a dedicated queue host plus client `--qhost`. Omit `--qhost` only when you are already on that box. Kit `submit go` argv is `host:N SCRIPT.jl` (DistSSHKit order).
- SSH E2E covers those README CLI verbs over real OpenSSH (`--qhost` to a loopback queue host) and DistSSHKit docker-ssh workers. `enable` / `disable` / `teardown` use `--write-only` so CI does not touch the runner’s user systemd / LaunchAgent.
- `watch` reprints the job table until Ctrl-C (`--interval`, default 0.5s). Same verb on the queue host and via `--qhost` (`ssh -t` when the local stdout is a TTY). Does not stop the waiter.
- Drop the `dskq` PATH shim and Pkg Apps entry. Use `julia -m DistSSHKitQueue`. `setup` writes `config.toml` only; `teardown` still removes a leftover `~/.local/bin/dskq`.
- CLI errors (`ArgumentError`) print as `Error: ...` on stderr, not a Julia stacktrace. `submit go/drive` checks the script exists before enqueuing (was silently queued, then failed). `cancel` reports an unknown id the same as `is not queued`. `status` shows an `ERROR` column when a job has failed.
- `stop` halts the waiter but keeps config / store / OS unit. It latches (`jobs.toml.stopped`) so `submit` will not auto-start; only an explicit `serve` resumes. Runs locally or via `--qhost HOST`.
- CLI chrome matches DistSSHKit (`--help` sections, `~` paths, colored `status` table). Job ids stay a bare stdout line.
- `~/.distsshkitqueue/config.toml` (`store` + `[env]`; ENV wins). CLI `setup` (re-run is a no-op unless `--force`). OS unit: `enable` / `disable` (was `service install` / `uninstall`).
- `submit` starts a waiter itself if none is watching the store, like Kit `go!` (opt out: `DISTSSHKITQUEUE_NO_AUTOSERVE=1`). `serve` gets a pidfile next to the store.
- `--qhost HOST` before the verb (`--qhost HOST status` / `submit` / `cancel`) picks the queue host. Remote Julia uses Kit auto-detect; `--remote-julia` / `JULIA_DISTRIBUTED_EXE` override. The client stays stateless.
- `teardown -y` stops the waiter and removes the OS unit and `~/.distsshkitqueue` (not a git clone or `Pkg.rm`).
- Client vs queue-host verbs: `--qhost` is client-only; `setup` / `serve` / `enable` / `disable` refuse it. Source: `src/client/` and `src/qhost/`.
- Waiter runs DistSSHKit `execute!(kind; detached=true)` (`KitRunResult`). CLI `cancel <id>` (`:queued` only). Optional `enable` (LaunchAgent / systemd user). DistSSHKit **0.3.2+**.
- CI: schedule-only **E2E daily** (Linux / macOS Intel / WSL), GHCR worker image. Not a PR check.
- Design: waiter is `serve`; clients use Kit `go` / `drive` argv. FIFO one table job. No Queue slot ceiling.
- Names: `Queue`, `Job`, `submit!` / CLI `submit`, `cancel` / `cancel!`, `job` / `jobs`, `serve!` (`--interval`).
  Not registered.
