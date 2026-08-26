# Docs

Documenter site for DistSSHQueue.jl. Sources live in `docs/src/`.

Layout (same headings as DistSSHKit; Queue verbs only — do not copy Kit
`go` / `drive` / `setup` pages):

- **Introduction** — `index.md`
- **First Steps** — `requirements.md`, `tutorial/`
- **User Guide** — `manual/`
- **API** — `api.md`

Placement tokens and Kit flags stay in the
[kit docs](https://yamanori99.github.io/DistSSHKit.jl/stable/).

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Output: `docs/build/`. Use `--project=docs` (not the package root).
