# Tests

How this repo tests DistSSHKitQueue. Maintainer checklist: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the Queue checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl`. CI runs the same on Julia 1.12 with Codecov (`pkgtest`). SSH E2E is `testenv/docker-ssh/scripts/up.sh --e2e` (PR / main, path-gated; Codecov `e2e` when `DSKQ_CODE_COVERAGE=1`). CLI E2E (`-m DistSSHKitQueue` + `local:1`, auto-serve / cancel / watch / `--qhost` / teardown; not Docker): `DSKQ_CLI_E2E=1 julia --project=. test/cli_e2e.jl` (also a PR CI job). JETLS is `./.github/jetls-check.sh`. Aqua is `./.github/aqua-check.sh` (not `Pkg.test()`, not CI yet). Documenter is local `docs/make.jl`.
