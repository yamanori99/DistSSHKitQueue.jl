# Tests

How this repo tests DistSSHKitQueue. Maintainer checklist: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the Queue checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl`. Aqua / JETLS / Documenter are not wired yet (no Kit E2E copy).
