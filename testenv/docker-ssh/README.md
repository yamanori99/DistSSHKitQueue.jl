# Docker SSH workers (Queue happy-path E2E)

Real OpenSSH + rsync Linux workers for a DistSSHKitQueue end-to-end run. These
containers are **DistSSHKit `go` / `drive` targets** (`host:N`), not the Queue
controller. The controller and the waiter run on the host during `--e2e`.

Adapted from DistSSHKit's `testenv/docker-ssh` (same worker image shape), kept
independent in this repo. `Pkg.test()` does **not** start Docker or run this.

## What the E2E proves

The host is both **controller** and **orderer** (first slice: the waiter calls
`go!` / `drive!` in-process). The flow in [`test/e2e.jl`](../../test/e2e.jl):

1. Copy DistSSHKit `demos/` file/echo scripts into `example-job` (not `pipeline_*`;
   those call `go!` / `pipeline!` themselves).
2. `setup!` deploys that project to the workers (rsync + instantiate).
3. Enqueue each remaining demo (same as CLI `submit go` / `submit drive`) and drive the waiter to `:done`.
4. FIFO: two queued Kit jobs, one running at a time.
5. Cancel the middle queued row; waiter skips it and runs the next.
2. Enqueue a `go` job into the Queue store (orderer side; CLI: `submit go`).
3. Drive the waiter (`placeholder_step!`); it runs `go!` on the worker.
4. Job reaches `:done`; `result_path` is the collected batch root.
5. Peek (`status`) + fetch (read the collected file on the controller).

## Layout

| Path | Role |
| --- | --- |
| [`Dockerfile`](Dockerfile) / [`start.sh`](start.sh) | Worker image (sshd, rsync, git, Julia 1.12 via juliaup) |
| [`compose.yml`](compose.yml) | Two workers (`worker-1` / `worker-2`) |
| [`scripts/gen-keys.sh`](scripts/gen-keys.sh) | Controller + inter-worker keys, SSH config |
| [`scripts/up.sh`](scripts/up.sh) | Keys → build → up → wait (`--e2e` also runs the suite) |
| [`scripts/wait-ready.sh`](scripts/wait-ready.sh) | BatchMode SSH + Julia probe |
| [`scripts/down.sh`](scripts/down.sh) | Compose down |
| `.generated/` | gitignored SSH config / keys (created by scripts) |

SSH Host aliases (written to `.generated/ssh_config`):

- `dskq-w1` → `127.0.0.1:2222` user `dev`
- `dskq-w2` → `127.0.0.1:2223` user `dev`

On macOS, ports publish on `127.0.0.1` (Docker Desktop / Colima defaults) so
macOS Local Network Privacy does not block SSH from the controller.

## Local use (macOS, Linux, or WSL2)

Requires Docker Compose. From this directory:

```bash
./scripts/up.sh --e2e    # workers + Queue E2E (runs test/e2e.jl from repo root)
./scripts/up.sh          # workers only
./scripts/down.sh
```

Manual smoke (no suite):

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
of building locally.

## CI

[`.github/workflows/ssh-e2e.yml`](../../.github/workflows/ssh-e2e.yml) runs
`./scripts/up.sh --e2e` on `ubuntu-latest` for `main`, PRs that touch `src` /
`test` / `testenv` / `Project.toml`, and `workflow_dispatch`. `Pkg.test()` still
does not start Docker. No GHCR bake, no daily macOS / WSL controllers (those
stay DistSSHKit's).
