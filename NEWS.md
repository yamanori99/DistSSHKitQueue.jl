# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- Design: Queue is the controller entry; the Kit master sits under it (same process first, child later). Any number of orderer machines enqueue over SSH into that waiter (one FIFO, no HTTP). Names not frozen.
- Placeholder API: true FIFO occupancy, TOML store, one `placeholder!` (`drive=true` for DistSSHKit `drive!`).
  Not registered.
