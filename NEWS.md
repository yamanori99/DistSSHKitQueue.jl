# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

First snapshot. Not on General. Pin `v0.1.0-beta.1` when that tag exists.
[DistSSHKit](https://github.com/yamanori99/DistSSHKit.jl) **0.4.1+** comes from General.
Do not `Pkg.develop` Kit for ordinary Queue work.
Julia **1.12+**. `julia -m DistSSHKitQueue` (no `dskq` shim;
`teardown` still removes a leftover `~/.local/bin/dskq`).

### Jobs

- FIFO one table job. Waiter is DistSSHKit `execute!(kind; detached=true)`.
- `submit` starts `serve` if none is watching (`DISTSSHKITQUEUE_NO_AUTOSERVE=1`
  to opt out). `stop` latches (`jobs.toml.stopped`); only an explicit `serve`
  resumes. `stop` keeps config / store / OS unit.
- `submit go` / `submit drive` check the script exists first. A Kit-shaped
  line with a `.jl` and no Queue verb is `go`. `--hosts` / `--julia` stay on
  Kit. Queued `go` with `job_id` runs the slot script (`-L`).
- Job ids are a bare stdout line. `cancel` of `:running` records
  `allocate_output_dir` (or `--output-dir`) so `terminate_run!` has a path.
  `cannot be cancelled` for an unknown id, a finished row, or `:running`
  without a known output dir. `status` has an `ERROR` column on failure.
- `watch` reprints until Ctrl-C (`--interval`, default 0.5s). Does not stop
  the waiter. Kit `-q` / `--quiet` / `DISTSSHKIT_QUIET`: table only.

### Client hop

- Token is `qhost:NAME` (like Kit `child:NAME`). `--qhost` and `--via` are
  refused. `setup` / `serve` / `enable` / `disable` refuse `qhost:` (log in
  on the queue host).
- Omitted `qhost:` uses `DISTSSHKITQUEUE_HOST` (SSH name). Token wins. Not
  `DISTSSHKIT_HOSTS`. Not forwarded on the hop.
- `status` / `watch` print `qhost` from `DISTSSHKITQUEUE_QHOST` (set on the
  hop), or `local (hostname)` when omitted. Not the job `HOSTS` column.

### Queue host

- Store is `~/.distsshkitqueue` (`config.toml`: `store` + `[env]`; ENV wins).
  `setup` writes config only.
- `enable --queue-env DIR` is the unit's Queue env (`--project` refused).
  Job tree stays cwd / `DISTRIBUTED_PROJECT_ROOT`. `enable --julia` is the
  unit binary. Queue-host Julia for jobs is `--remote-julia` /
  `JULIA_DISTRIBUTED_EXE`.
- `teardown` confirms like DistSSHKit (`-y` / `--yes` / `DISTSSHKIT_YES`).
  `[env]` in the target config still applies.
- `--version` (`-v`, `-V`) prints Queue then DistSSHKit. `submit go -v` stays
  Kit only. CLI chrome matches Kit (`--help` sections, `~` paths, colored
  `status`). `ArgumentError` is `Error: ...` on stderr.

### Hosts

- `add-host` / `remove-host` on the queue host. Tokens `parent[:N]` /
  `child:NAME[:N]`. Optional `:N` is a max. First add creates the list;
  missing key is allow-all; empty array allows none. Leftover `allowed` is
  still read until rewritten. Next `submit` re-reads (do not restart
  `serve`). CLI `submit` follows config; library `submit!` uses
  `Queue(; allowed=…)` unless `follow_config=true`. `submit!` rejects
  pre-0.4 tokens (`parenthost`, bare `NAME:N`).
- `list-host`: tokens plus `ssh -G` Host / HostName / User / Port. No keys.
  On the queue host, or `qhost:HOST list-host`.
- `size`: DistSSHKit `size` on the queue host. Omit tokens to size config
  `hosts`. Does not enqueue; prints a `submit drive` template.

### Docs

- English README is the landing page. Japanese: `README.ja.md`. Documenter
  First Steps / User Guide cover Queue verbs; Kit `go` / `drive` stay in
  the kit docs.
