# Docker SSH workers (Queue happy-path E2E)

Real OpenSSH + rsync Linux workers for a DistSSHKitQueue end-to-end run. These
containers are **DistSSHKit `go` / `drive` targets** (`host:N`), not the queue
host. The queue host and the waiter run on the host during `--e2e`.

Adapted from DistSSHKit's `testenv/docker-ssh` (same worker image shape), kept
independent in this repo. `Pkg.test()` does **not** start Docker or run this.

## What the E2E proves

The host is both **queue host** and **client**. The waiter calls DistSSHKit
`execute!(…; detached=true)` (Kit child master). The flow in [`test/e2e.jl`](../../test/e2e.jl):

1. Copy DistSSHKit `demos/` file/echo scripts into `example-job` (not `pipeline_*`;
   those call `go!` / `pipeline!` themselves).
2. `setup!` deploys that project to the workers (rsync + instantiate).
3. Enqueue each remaining demo (same contract as `submit go` / `submit drive`) and
   drive the waiter to `:done`.
4. FIFO: two queued Kit jobs, one running at a time.
5. Cancel the middle queued row; waiter skips it and runs the next.
6. `result_path` is Kit’s collected tree; peek it on the queue host (no second collect).

## Layout

| Path | Role |
| --- | --- |
| [`Dockerfile`](Dockerfile) / [`start.sh`](start.sh) | Worker image (sshd, rsync, git, Julia 1.12 via juliaup) |
| [`compose.yml`](compose.yml) | Two workers (`worker-1` / `worker-2`) |
| [`scripts/gen-keys.sh`](scripts/gen-keys.sh) | Controller + inter-worker keys, SSH config |
| [`scripts/up.sh`](scripts/up.sh) | Keys → build → up → wait (`--e2e` also runs the suite) |
| [`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh) | macOS Intel GitHub runner: Lima + Colima |
| [`scripts/wait-ready.sh`](scripts/wait-ready.sh) | BatchMode SSH + Julia probe |
| [`scripts/down.sh`](scripts/down.sh) | Compose down |
| `.generated/` | gitignored SSH config / keys (created by scripts) |

SSH Host aliases (written to `.generated/ssh_config`):

- `dskq-w1` → `127.0.0.1:2222` user `dev`
- `dskq-w2` → `127.0.0.1:2223` user `dev`

On macOS, ports publish on `127.0.0.1` (Docker Desktop / Colima defaults) so
macOS Local Network Privacy does not block SSH from the queue host.

## Local use (macOS, Linux, or WSL2)

Requires Docker Compose. From this directory:

```bash
./scripts/up.sh --e2e    # workers + Queue E2E (runs test/e2e.jl from repo root)
./scripts/up.sh          # workers only
./scripts/down.sh
```

Manual smoke (no suite): after workers are up, on the queue host:

```bash
julia --project=../.. -m DistSSHKitQueue setup --write-only   # once; from repo root use --project=.
# put SSH opts in ~/.distsshkitqueue/config.toml [env], then:
julia --project=../.. -m DistSSHKitQueue submit go SCRIPT.jl dskq-w1:1
julia --project=../.. -m DistSSHKitQueue status
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
build, `DSKQ_PUSH_IMAGE=<tag>` tags and pushes that image.

## CI

[`.github/workflows/ssh-e2e.yml`](../../.github/workflows/ssh-e2e.yml) runs
`./scripts/up.sh --e2e` on `ubuntu-latest` for `main`, PRs that touch `src` /
`test` / `testenv` / `Project.toml`, and `workflow_dispatch`. CI sets
`DSKQ_CODE_COVERAGE=1` (`--code-coverage=user`) and uploads flag `e2e` to Codecov.
`Pkg.test()` still does not start Docker.

[`.github/workflows/ssh-e2e-daily.yml`](../../.github/workflows/ssh-e2e-daily.yml)
is **not** a PR check (schedule 04:00 JST + `workflow_dispatch`). It builds
`ghcr.io/<owner>/dskq-linux-ssh-worker:<sha>`, runs E2E on Ubuntu, `macos-15-intel`
(Colima via [`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh)), and WSL2,
then tags `latest`. Daily does not upload Codecov. Make the GHCR package public
after the first push so forks can pull if needed.
