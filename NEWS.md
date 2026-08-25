# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- Docs: Documenter First Steps / User Guide (Queue verbs; Kit `go` / `drive`
  stay in the kit docs). Japanese README (`README.ja.md`). English README is
  the landing page.
- CI: Kit-shaped Type (`PR label`) and Labels (`area:*` from `src/client/` /
  `src/qhost/`). TagBot workflow (idle until General).
- Client hop is `qhost:NAME` (like Kit `child:NAME`). `--qhost` is refused. `--hosts` /
  `--julia` stay on Kit `go` / `drive`. Queue-host Julia is `--remote-julia` /
  `JULIA_DISTRIBUTED_EXE`. `qhost:` uses DistSSHKit `run_on_host`.
- `DISTSSHKITQUEUE_HOST` is the default SSH name when `qhost:` is omitted. Token wins.
  Not `DISTSSHKIT_HOSTS`. Not forwarded on the hop. Not `DISTSSHKITQUEUE_QHOST`
  (that is status/watch display).
- `status` / `watch` print `qhost` from `DISTSSHKITQUEUE_QHOST` (set on the ssh hop), or
  `local (hostname)` when omitted. No `--via`. Not the job `HOSTS` column. Kit `-q` /
  `--quiet` / `DISTSSHKIT_QUIET`: table only. `--progress` / `--verbose` keep chrome.
- `watch` reprints until Ctrl-C (`--interval`, default 0.5s). `ssh -t` when stdout is a
  TTY. Does not stop the waiter. No `--ticks`; tests use `DISTSSHKITQUEUE_WATCH_TICKS`.
- `julia -m DistSSHKitQueue --version` (`-v`, `-V`) prints Queue then DistSSHKit.
  `submit go -v` stays Kit only.
- `teardown` confirms like DistSSHKit: `-y` / `--yes` / `DISTSSHKIT_YES`.
  `DISTSSHKITQUEUE_YES` is gone. `[env]` in the target `config.toml` still applies.
- `enable --queue-env DIR` is the Queue env in the OS unit. `enable --project` is refused.
  The job tree stays cwd / `DISTRIBUTED_PROJECT_ROOT`. The unit still runs
  `julia --project=<that env>`.
- `go --hosts` / `go --julia` (and `submit go` / `submit drive`) stay DistSSHKit's.
  A Kit-shaped line with a `.jl` and no Queue verb is `go`. `enable --julia` is the
  unit binary.
- CLI `add-host` / `remove-host` write config `hosts` on the queue host (not via
  `qhost:`). Tokens are DistSSHKit's: `parent[:N]` / `child:NAME[:N]`. Optional `:N` is a
  per-name max. First add creates the list; missing key is allow-all; empty array allows
  none. A leftover `allowed` key is still read until rewritten. Next `submit` re-reads
  the file (do not restart `serve`). A `:running` Kit job is not stopped. CLI `submit`
  uses `follow_config`; library `submit!` uses `Queue(; allowed=…)` unless
  `follow_config=true`.
- `list-host` (not Kit `--hosts`): host tokens plus `ssh -G` Host / HostName / User /
  Port. No keys. On the queue host, or `qhost:HOST list-host`.
- CLI `size`: DistSSHKit `size` on the queue host. Omit tokens to size config `hosts`.
  Does not enqueue; prints a `submit drive` template.
- `:running` cancel records DistSSHKit `allocate_output_dir` (or the given `output_dir`)
  on the row so `terminate_run!` / `kit.pid` have a path without submit `--output-dir`.
- DistSSHKit **0.4.1+** from General is the floor. Do not `Pkg.develop` Kit for ordinary
  Queue work. Library `submit!` rejects pre-0.4 tokens (`parenthost`, bare `NAME:N`).
  Queued `go` with `job_id` runs the slot script (`-L`).
- Testenv Docker / Apple boxes are Compose `child-1` / `child-2` (Apple containers
  `dskq-child-*`). Peer DNS `dev@child-1`. Examples `child:host1`. Image tags
  `dskq-linux-ssh-worker`. Controller aliases `dskq-w1` / `dskq-w2`.
- SSH E2E (controller + worker image) is Julia slot **max** (today 1.13), same pair as
  DistSSHKit. Compat floor stays 1.12. Covers CLI over loopback OpenSSH (`qhost:`) and
  docker-ssh workers. `enable` / `disable` / `teardown` use `--write-only` in CI.
- Autoserve: `submit` starts `serve` if none is watching (`DISTSSHKITQUEUE_NO_AUTOSERVE=1`
  to opt out). Spawn via `sh -c … &` so the client can exit. Tests set
  `DISTSSHKITQUEUE_SERVE_TAG` / `DISTSSHKITQUEUE_TEST_PIDS`.
- Drop the `dskq` PATH shim and Pkg Apps entry. Use `julia -m DistSSHKitQueue`. `setup`
  writes `config.toml` only; `teardown` still removes a leftover `~/.local/bin/dskq`.
- CLI errors (`ArgumentError`) print as `Error: ...` on stderr. `submit go/drive` checks
  the script exists before enqueuing. `cancel` prints `cannot be cancelled` for an
  unknown id, a finished row, or `:running` without a known output dir. `status` shows
  an `ERROR` column when a job has failed.
- `stop` halts the waiter but keeps config / store / OS unit. It latches
  (`jobs.toml.stopped`) so `submit` will not auto-start; only an explicit `serve`
  resumes. `qhost:` is client-only; `setup` / `serve` / `enable` / `disable` refuse it.
- CLI chrome matches DistSSHKit (`--help` sections, `~` paths, colored `status` table).
  Job ids stay a bare stdout line.
- `~/.distsshkitqueue/config.toml` (`store` + `[env]`; ENV wins). OS unit: `enable` /
  `disable`. Waiter: DistSSHKit `execute!(kind; detached=true)`. FIFO one table job.
- CI: Kit-shaped Julia slots (`min` / `max` / `tip`). JETLS min plus `JULIA_SLOT_JETLS_MAX`
  (~1.13). Codecov `pkgtest` on main push (max slot); E2E `e2e` on cut PRs and **E2E daily**
  Linux. Docs-only PRs skip heavy steps (`ci-heavy`). **CI weekly** is not a PR check.
  Not registered.
