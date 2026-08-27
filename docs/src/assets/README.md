# Logo & social-preview assets

The mark is original geometry (no Julia dots). MIT, same as the package.

There is no SMIL / GIF bake. The source is `logo/draw.jl` with a **pinned**
Luxor env (`logo/Project.toml` + `logo/Manifest.toml`). Do not `Pkg.add`
Luxor into the package or docs project.

```text
assets/
  custom.css
  README.md
  logo.svg              Documenter light (copy of logo/logo-static.svg)
  logo-dark.svg         Documenter dark (copy of logo/logo-dark-static.svg)
  logo/
    Project.toml        Luxor pin
    Manifest.toml
    draw.jl             source (logo + social SVG)
    logo-static.svg     README light (`#gh-light-mode-only`)
    logo-dark-static.svg
    logo-static.png     local `--png`
    logo-dark-static.png
  social/
    social-preview-static.svg
    social-preview-static.png   GitHub OG 1280×640 (`--png`)
```

Documenter only discovers `logo.svg` / `logo-dark.svg` at this directory’s
top level. Do not edit those copies by hand.

GitHub README uses `#gh-light-mode-only` / `#gh-dark-mode-only` on
`logo/logo-static.svg` / `logo/logo-dark-static.svg`.

Upload `social/social-preview-static.png` under GitHub → Settings → Social
preview.

```bash
julia --project=docs/src/assets/logo -e 'using Pkg; Pkg.instantiate()'
julia --project=docs/src/assets/logo docs/src/assets/logo/draw.jl
julia --project=docs/src/assets/logo docs/src/assets/logo/draw.jl --png   # rasters
```

CI (`.github/workflows/assets-draw.yml`) re-runs the SVG draw when this tree
changes and fails if committed SVGs drift. PNG is not pixel-compared.

Needs [Luxor](https://github.com/JuliaGraphics/Luxor.jl) **4.5** via the pin
above, not a global `] add`.
