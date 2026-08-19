# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- CI: schedule-only **E2E daily** (Linux / macOS Intel / WSL), GHCR worker image. Not a PR check.
- Design: waiter is `serve`; orderers use Kit `go` / `drive` argv. FIFO one table job. No Queue slot ceiling.
- Names: `Queue`, `Job`, `submit!` / CLI `submit`, `cancel!`, `job` / `jobs`, `serve!` (`--interval`).
  DistSSHKit **0.3.1+**. `ok=false` is `:failed`. `result_path` recorded.
  Not registered.
