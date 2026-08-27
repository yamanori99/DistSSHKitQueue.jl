# Logo & social-preview assets

The mark is original geometry (no Julia dots). MIT, same as the package.

There is no SMIL / GIF bake. Edit `logo/draw.jl` and regenerate.

```text
assets/
  custom.css
  README.md
  logo.svg              Documenter light (copy of logo/logo-static.svg)
  logo-dark.svg         Documenter dark (copy of logo/logo-dark-static.svg)
  logo/
    draw.jl             source (logo + social)
    logo-static.svg     README light (`#gh-light-mode-only`)
    logo-dark-static.svg
    logo-static.png
    logo-dark-static.png
  social/
    social-preview-static.svg
    social-preview-static.png   GitHub OG 1280×640
```

Documenter only discovers `logo.svg` / `logo-dark.svg` at this directory’s
top level. Do not edit those copies by hand.

GitHub README uses `#gh-light-mode-only` / `#gh-dark-mode-only` on
`logo/logo-static.svg` / `logo/logo-dark-static.svg`.

Upload `social/social-preview-static.png` under GitHub → Settings → Social
preview.

```bash
julia docs/src/assets/logo/draw.jl
```

Needs [Luxor](https://github.com/JuliaGraphics/Luxor.jl).
