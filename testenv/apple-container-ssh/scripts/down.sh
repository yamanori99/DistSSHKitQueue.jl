#!/usr/bin/env bash
# Stop and remove Apple-container Queue workers (leave buildkit alone).
set -euo pipefail

if ! command -v container >/dev/null 2>&1; then
  echo "container CLI not found (Apple container)" >&2
  exit 1
fi

for name in dskq-worker-1 dskq-worker-2; do
  container stop "${name}" >/dev/null 2>&1 || true
  container rm "${name}" >/dev/null 2>&1 || true
done
echo "Removed dskq-worker-1 and dskq-worker-2 (if they existed)"
