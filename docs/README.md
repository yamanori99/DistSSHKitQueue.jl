# Docs

Documenter site for DistSSHKitQueue.jl. Sources live in `docs/src/`.

- **Introduction** — `index.md` (CLI sketch; full verb table stays in the repo README)
- **API** — `api.md`

Do not copy DistSSHKit's tutorial/manual. Placement tokens stay in the kit docs.

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Output: `docs/build/`. Use `--project=docs` (not the package root).
