# Tests

How this repo tests DistSSHKitQueue. Maintainer checklist: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the Queue checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl`. CI runs the same on Julia 1.12. Later SSH E2E borrows DistSSHKit `testenv/docker-ssh` workers; do not copy that tree. Aqua / JETLS / Documenter are not wired.
