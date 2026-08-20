# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- `dskq` shim (`setup` writes `~/.local/bin/dskq`) and `~/.distsshkitqueue/config.toml` (`store` + `[env]`; ENV wins). CLI `setup` / `setup --service`. Julia 1.12 Pkg Apps `[apps] dskq`.
- `submit` starts a waiter itself if none is watching the store, like Kit `go!` (opt out: `DISTSSHKITQUEUE_NO_AUTOSERVE=1`). `serve` gets a pidfile next to the store.
- Waiter runs DistSSHKit `execute!(kind; detached=true)` (`KitRunResult`). CLI `cancel <id>` (`:queued` only). Optional `service install` (LaunchAgent / systemd user). DistSSHKit **0.3.2+**.
- CI: schedule-only **E2E daily** (Linux / macOS Intel / WSL), GHCR worker image. Not a PR check.
- Design: waiter is `serve`; orderers use Kit `go` / `drive` argv. FIFO one table job. No Queue slot ceiling.
- Names: `Queue`, `Job`, `submit!` / CLI `submit`, `cancel` / `cancel!`, `job` / `jobs`, `serve!` (`--interval`).
  Not registered.
