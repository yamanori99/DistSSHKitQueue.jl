# Tests

How this repo tests DistSSHKitQueue. Maintainer checklist: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the Queue checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl`. CI runs the same on Julia 1.12. SSH E2E is `testenv/docker-ssh/scripts/up.sh --e2e` (PR / main, path-gated). JETLS is `./.github/jetls-check.sh`. Aqua is `./.github/aqua-check.sh` (not `Pkg.test()`, not CI yet). Documenter is local `docs/make.jl`.
