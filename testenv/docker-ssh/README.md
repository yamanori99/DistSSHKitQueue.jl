# Docker SSH workers (Queue happy-path E2E)

Real OpenSSH + rsync Linux workers for a DistSSHKitQueue end-to-end run. These
containers are **DistSSHKit `go` / `drive` targets** (`child:NAME[:N]`), not the queue
host. The queue host and `serve` run on the host during `--e2e`.

Adapted from DistSSHKit's `testenv/docker-ssh` (same worker image shape), kept
independent in this repo. `Pkg.test()` does **not** start Docker or run this.

Optional Mac-only path (same image and `test/e2e.jl`):
[`../apple-container-ssh`](../apple-container-ssh) — `./scripts/up.sh --e2e`
(Apple `container`; **not CI**). Do not run both stacks at once (shared
`ssh_config`).

## What the E2E proves

The host during `--e2e` is the **queue host**. docker-ssh containers are DistSSHKit `child:NAME[:N]` workers only. Do not add a container named `qhost`; the client `qhost:` is loopback `qhost:dskq-qh`. SSH Host `dskq-w1` / `dskq-w2` is not Compose `child-1` / `child-2` (naming: issue #35). Roles: [test/README.md](../../test/README.md#ssh-e2e-roles).

[`test/e2e.jl`](../../test/e2e.jl):

1. Copy DistSSHKit `demos/` file/echo scripts into `example-job` (not `pipeline_*`;
   those call `go!` / `pipeline!` themselves).
2. `setup!` deploys that project to the workers (rsync + instantiate).
3. Enqueue each remaining demo (same contract as `submit go` / `submit drive`) and
   drive `serve` to `:done`.
4. FIFO: two queued Kit jobs, one running at a time.
5. Cancel the middle queued row; `serve` skips it and runs the next.
6. `result_path` is Kit’s collected tree; peek it on the queue host (no second collect).
7. Queue-host CLI (omit `qhost:`, fake `HOME`): `setup`, `enable --write-only`,
   `disable --write-only`, foreground `serve`, `submit go child:dskq-w1:1 SCRIPT.jl`, `status`,
   `watch` (harness `DISTSSHKITQUEUE_WATCH_TICKS=1`), `stop`.
8. Client `qhost:dskq-qh` over a **loopback OpenSSH** (not a fake `ssh` binary):
   `submit` / `status` / `watch` / `cancel` / `stop` / `teardown -y --write-only`.
   `qhost:HOST setup` is refused.
9. Does not `systemctl enable --now` or `launchctl bootstrap`. Does not treat
   `parent:N` on a sleeping laptop as the product path.

Worker image pins Julia to CI slot **max** (juliaup `--default-channel`, today **1.13**)
so DistSSHKit `setup --check` can run **without** `--ignore-julia-version`. Pins live in
[`.github/julia-slots.env`](../../.github/julia-slots.env).

## Layout

| Path | Role |
| --- | --- |
| [`Dockerfile`](Dockerfile) / [`start.sh`](start.sh) | Worker image (sshd, rsync, git, Julia via juliaup; slot **max**, today **1.13**) |
| [`compose.yml`](compose.yml) | Two children (`child-1` / `child-2`) |
| [`scripts/gen-keys.sh`](scripts/gen-keys.sh) | Controller + inter-worker keys, SSH config |
| [`scripts/up.sh`](scripts/up.sh) | Keys → down → up → wait (`--e2e` also runs the suite) |
| [`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh) | macOS Intel GitHub runner: Lima + Colima |
| [`scripts/wait-ready.sh`](scripts/wait-ready.sh) | BatchMode SSH + Julia probe |
| [`scripts/down.sh`](scripts/down.sh) | Compose down |
| `.generated/` | gitignored SSH config / keys (created by scripts) |

SSH Host aliases (written to `.generated/ssh_config`):

- `dskq-w1` → `127.0.0.1:2222` user `dev`
- `dskq-w2` → `127.0.0.1:2223` user `dev`

On macOS, ports publish on `127.0.0.1` (Docker Desktop / Colima defaults) so
macOS Local Network Privacy does not block SSH from the queue host.

Do not run DistSSHKit `testenv/docker-ssh` at the same time: both bind
`2222` / `2223`. Compose project name is `distsshkitqueue-docker-ssh` so a
Kit stack in a folder also named `docker-ssh` is not treated as the same
project. `up.sh` runs `down.sh` first (same as Kit) and drops a stale
`.generated/known_hosts` (container sshd host keys change on recreate;
`BatchMode` cannot replace them).

## Local use (macOS, Linux, or WSL2)

Requires Docker Compose. From this directory:

```bash
./scripts/up.sh --e2e    # workers + Queue E2E (runs test/e2e.jl from repo root)
./scripts/up.sh          # workers only
./scripts/down.sh
```

Manual smoke (no suite): after workers are up, this machine is the queue host.
From a **client** (same box is fine if you still pass `qhost:HOST` to a real ssh alias):

```bash
# on the queue host, once
julia --project=../.. -m DistSSHKitQueue setup
# put SSH opts in ~/.distsshkitqueue/config.toml [env]

# from a client
julia --project=../.. -m DistSSHKitQueue qhost:HOST submit go child:dskq-w1:1 SCRIPT.jl
julia --project=../.. -m DistSSHKitQueue qhost:HOST status
```

Or probe a worker without Queue:

```bash
./scripts/up.sh
ssh -F .generated/ssh_config dskq-w1 'echo ok; julia --version'
```

Run the suite by hand once workers are up:

```bash
cd ../..                                   # repo root
DSKQ_SSH_E2E=1 julia --project=test test/e2e.jl
```

`DSKQ_WORKER_IMAGE=<tag> ./scripts/up.sh` pulls a prebuilt worker image instead
of building locally (`DSKQ_WORKER_PULL_RETRIES` for wait-on-push). After a local
build, `DSKQ_PUSH_IMAGE=<tag>` tags and pushes that image (`scripts/push-image.sh`,
retries). `DSKQ_SKIP_UP=1` skips compose up (image job: build+push only).

## CI

[`.github/workflows/ssh-e2e.yml`](../../.github/workflows/ssh-e2e.yml) runs
`./scripts/up.sh --e2e` on `ubuntu-latest` for `main`, PRs that touch `src` /
`test` / `testenv` / `Project.toml`, and `workflow_dispatch`. Otherwise the
job `ubuntu-latest → ubuntu-24.04` is skipped (`e2e-gate` still runs). Ordinary
PR E2E does not upload Codecov. A `cut` PR sets `DSKQ_CODE_COVERAGE=1` and
uploads flag `e2e`. `Pkg.test()` still does not start Docker.

[`.github/workflows/ssh-e2e-daily.yml`](../../.github/workflows/ssh-e2e-daily.yml)
is **not** a PR check (schedule 04:00 JST + `workflow_dispatch`). It builds
`ghcr.io/<owner>/dskq-linux-ssh-worker:<sha>` (`DSKQ_SKIP_UP=1`), then E2E on
Ubuntu, `macos-15-intel` (Colima via [`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh)),
and WSL2, then tags `latest`. Linux daily uploads Codecov flag `e2e`. Make the
GHCR package public after the first push so forks can pull if needed.
