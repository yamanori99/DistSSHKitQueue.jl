# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- CLI errors (`ArgumentError`) print as `Error: ...` on stderr, not a Julia stacktrace. `submit go/drive` checks the script exists before enqueuing (was silently queued, then failed). `cancel` reports an unknown id the same as `is not queued`. `status` shows an `ERROR` column when a job has failed.
- `stop` halts the waiter but keeps config / store / `dskq` / OS unit. It latches (`jobs.toml.stopped`) so `submit` will not auto-start; only an explicit `serve` resumes. Runs locally or via `--qhost HOST`.
- CLI chrome matches DistSSHKit (`--help` sections, `~` paths, colored `status` table). Job ids stay a bare stdout line.
- `dskq` shim (`setup` writes `~/.local/bin/dskq`) and `~/.distsshkitqueue/config.toml` (`store` + `[env]`; ENV wins). CLI `setup` / `setup --service`. Julia 1.12 Pkg Apps `[apps] dskq`.
- `submit` starts a waiter itself if none is watching the store, like Kit `go!` (opt out: `DISTSSHKITQUEUE_NO_AUTOSERVE=1`). `serve` gets a pidfile next to the store.
- `--qhost HOST` before the verb (`--qhost HOST status` / `submit` / `cancel`) picks the queue host. Remote Julia uses Kit auto-detect; `--remote-julia` / `JULIA_DISTRIBUTED_EXE` override. The client stays stateless.
- `teardown -y` stops the waiter and removes `dskq`, the OS unit, and `~/.distsshkitqueue` (not a git clone or `Pkg.rm`).
- Client vs queue-host verbs: `--qhost` is client-only; `setup` / `serve` / `service` refuse it. Source: `src/client/` and `src/qhost/`.
- Waiter runs DistSSHKit `execute!(kind; detached=true)` (`KitRunResult`). CLI `cancel <id>` (`:queued` only). Optional `service install` (LaunchAgent / systemd user). DistSSHKit **0.3.2+**.
- CI: schedule-only **E2E daily** (Linux / macOS Intel / WSL), GHCR worker image. Not a PR check.
- Design: waiter is `serve`; clients use Kit `go` / `drive` argv. FIFO one table job. No Queue slot ceiling.
- Names: `Queue`, `Job`, `submit!` / CLI `submit`, `cancel` / `cancel!`, `job` / `jobs`, `serve!` (`--interval`).
  Not registered.
