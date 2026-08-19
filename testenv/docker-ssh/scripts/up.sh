#!/usr/bin/env bash
# Build once, then start docker-ssh workers (ports 2222 / 2223).
# Optional: ./scripts/up.sh --e2e  → also run the Queue SSH E2E from queue root.
#
# These containers are DistSSHKit go/drive targets. The Queue controller and the
# waiter run on this host during --e2e, not in a container.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUEUE_ROOT="$(cd "${ROOT}/../.." && pwd)"
RUN_E2E=0
LOCAL_IMAGE="local/dskq-linux-ssh-worker:latest"

for arg in "$@"; do
  case "$arg" in
    --e2e) RUN_E2E=1 ;;
    -h|--help)
      echo "usage: $0 [--e2e]"
      echo "  DSKQ_WORKER_IMAGE  pull this tag (skip compose build)"
      echo "  DSKQ_CODE_COVERAGE=1  e2e with --code-coverage=user"
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

cd "${ROOT}"

./scripts/gen-keys.sh

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "docker compose not found" >&2
  exit 1
fi

if [[ -n "${DSKQ_WORKER_IMAGE:-}" ]]; then
  docker pull "${DSKQ_WORKER_IMAGE}"
  docker tag "${DSKQ_WORKER_IMAGE}" "${LOCAL_IMAGE}"
else
  # Build a single service so logs are not interleaved (both share the image).
  "${COMPOSE[@]}" -f compose.yml build worker-1
fi

"${COMPOSE[@]}" -f compose.yml up -d --no-build
./scripts/wait-ready.sh
echo "Workers ready: dskq-w1 (2222), dskq-w2 (2223)"
echo "SSH config: ${ROOT}/.generated/ssh_config"

if [[ "$RUN_E2E" -eq 1 ]]; then
  export DSKQ_SSH_E2E=1
  cd "${QUEUE_ROOT}"
  julia_e2e=(julia --project=test --color=yes)
  if [[ "${DSKQ_CODE_COVERAGE:-}" == "1" ]]; then
    julia_e2e+=(--code-coverage=user)
  fi
  exec "${julia_e2e[@]}" test/e2e.jl
fi
