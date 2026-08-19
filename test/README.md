# Tests

How this repo tests DistSSHKitQueue. Maintainer checklist: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the Queue checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl`. CI runs the same on Julia 1.12. SSH E2E is `testenv/docker-ssh/scripts/up.sh --e2e` (not CI). JETLS is `./.github/jetls-check.sh`. Aqua / Documenter are not wired.
