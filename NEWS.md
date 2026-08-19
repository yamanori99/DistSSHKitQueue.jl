# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- Design: waiter is `serve`; orderers use Kit `go` / `drive` argv. FIFO one table job. No Queue slot ceiling.
- CLI: `julia -m DistSSHKitQueue serve|status|go|drive`. Store `~/.distsshkitqueue/jobs.toml`.
  DistSSHKit **0.3.1+**. `ok=false` is `:failed`. `result_path` recorded.
  Not registered.
