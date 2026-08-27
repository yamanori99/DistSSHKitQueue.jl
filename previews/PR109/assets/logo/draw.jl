# DistSSHQueue mark (static). Light PNG has paper; SVG is transparent.
# Pin: docs/src/assets/logo/Project.toml + Manifest.toml
#   julia --project=docs/src/assets/logo -e 'using Pkg; Pkg.instantiate()'
#   julia --project=docs/src/assets/logo docs/src/assets/logo/draw.jl
#   julia --project=docs/src/assets/logo docs/src/assets/logo/draw.jl --png
# SVG is the reproducible deliverable. --png needs Cairo / rsvg locally.

using Luxor

const WANT_PNG = "--png" in ARGS

const OUT = @__DIR__
const ASSETS = dirname(OUT)
const SOCIAL = joinpath(ASSETS, "social")
const INK = (0.07, 0.08, 0.10)
const PLUM = (0.584, 0.345, 0.698)
const PAPER = (1.0, 1.0, 1.0)
const NIGHT = (0.06, 0.07, 0.08)
const INK_ON_DARK = (0.96, 0.97, 0.98)

const SIDE = 30.0
const GAP = 3.4
const STROKE = 2.0
const RADIUS = 2.6
const CUT = 0.22
const OPTICAL_DX = 0.015
const BEZ = 0.5522847498
const CANVAS = 512
const MARGIN = 0.18

const SOCIAL_W, SOCIAL_H = 1280, 640
const SAFE_X, SAFE_Y = 100, 60
const MARK_SIZE = 340
const MARK_GAP = 40
const MARK_Y = clamp((SOCIAL_H - MARK_SIZE) ÷ 2, SAFE_Y, SOCIAL_H - SAFE_Y - MARK_SIZE)
const TITLE = "DistSSHQueue.jl"
const TAGLINE_1 = "A Julia queue where jobs take turns"
const TAGLINE_2 = "on shared machines over SSH."
const TEXT_BLOCK_H = 168
const TEXT_TOP = MARK_Y + (MARK_SIZE - TEXT_BLOCK_H) ÷ 2
const TITLE_Y = TEXT_TOP + 40
const TAGLINE_Y1 = TITLE_Y + 64
const TAGLINE_Y2 = TAGLINE_Y1 + 38
const TITLE_SIZE = 76
const TAGLINE_SIZE = 28
const FONT = "'Helvetica Neue', Helvetica, Arial, sans-serif"
# Helvetica Neue Heavy 76 / Medium 28 (macOS). Pinned so CI does not remetric.
const TITLE_ADV = 570.223
const TAGLINE_ADV = 461.552
const TEXT_ADV = max(TITLE_ADV, TAGLINE_ADV)
# SVG font-weight 800 reads a bit wider than the pinned Heavy advance, so
# the lockup sits slightly right; nudge left.
const LOCKUP_DX = -14
# Square slot is MARK_SIZE. The strip is inset so it does not fill the
# slot width; the leftover is the gap to the type (Kit's nested logo
# also has padding inside 340).
const MARK_FIT = 0.78
# Slot center reads a little low; title center reads high. Weight toward the slot.
const MARK_CY = (TITLE_Y + 2 * (MARK_Y + MARK_SIZE / 2)) / 3
const MARK_SLOT_Y = MARK_CY - MARK_SIZE / 2

pal_light() = (; dark=false, bg=PAPER, q=PLUM, ue=INK, last=INK)
pal_dark() = (; dark=true, bg=NIGHT, q=PLUM, ue=INK_ON_DARK, last=INK_ON_DARK)

function layout_row(; n=5)
    xs = ntuple(i -> (i - 1) * (SIDE + GAP), n)
    return (; xs, total=xs[n] + SIDE)
end

function mod_rect(x0, i)
    xl = x0 + (i - 1) * (SIDE + GAP)
    return (; xl, xr=xl + SIDE, yt=-SIDE, yb=0.0)
end

function stroke_ue!()
    setline(STROKE)
    setlinecap("butt")
    setlinejoin("round")
end

function sq_u!(m; color)
    d = STROKE / 2
    r = min(RADIUS, (SIDE - STROKE) / 5)
    k = BEZ * r
    xl, xr = m.xl + d, m.xr - d
    yt, yb = m.yt + d, m.yb - d
    setcolor(color...)
    stroke_ue!()
    newpath()
    move(Point(xl, yt))
    line(Point(xl, yb - r))
    curve(Point(xl, yb - r + k), Point(xl + r - k, yb), Point(xl + r, yb))
    line(Point(xr - r, yb))
    curve(Point(xr - r + k, yb), Point(xr, yb - r + k), Point(xr, yb - r))
    line(Point(xr, yt))
    strokepath()
end

function sq_e_play!(m; color, fill=false)
    setcolor(color...)
    cy = (m.yt + m.yb) / 2
    if fill
        poly(
            [Point(m.xl, m.yt), Point(m.xr, cy), Point(m.xl, m.yb)];
            action=:fill,
            close=true,
        )
        return
    end
    d = STROKE / 2
    xl, xr, yt, yb = m.xl + d, m.xr - d, m.yt + d, m.yb - d
    stroke_ue!()
    setlinecap("round")
    poly(
        [Point(xl, yt), Point(xr, (yt + yb) / 2), Point(xl, yb)];
        action=:stroke,
        close=true,
    )
end

function draw_ueue!(x0, pal)
    kinds = (:u, :e, :u, :e)
    for (j, kind) in enumerate(kinds)
        m = mod_rect(x0, j + 1)
        if kind == :u
            sq_u!(m; color=pal.ue)
        else
            sq_e_play!(m; color=(j == 4 ? pal.last : pal.ue), fill=(j == 4))
        end
    end
end

function draw_q!(x0, pal)
    m = mod_rect(x0, 1)
    r = min(RADIUS, SIDE / 4)
    cut = SIDE * CUT
    k = BEZ * r
    x0r, x1, y0, y1 = m.xl, m.xr, m.yt, m.yb
    setcolor(pal.q...)
    newpath()
    move(Point(x0r + r, y0))
    line(Point(x1 - r, y0))
    curve(Point(x1 - r + k, y0), Point(x1, y0 + r - k), Point(x1, y0 + r))
    line(Point(x1, y1 - cut))
    line(Point(x1 - cut, y1))
    line(Point(x0r + r, y1))
    curve(Point(x0r + r - k, y1), Point(x0r, y1 - r + k), Point(x0r, y1 - r))
    line(Point(x0r, y0 + r))
    curve(Point(x0r, y0 + r - k), Point(x0r + r - k, y0), Point(x0r + r, y0))
    closepath()
    fillpath()
end

function layout_mark()
    L = layout_row()
    cx = L.total / 2
    cy = -SIDE / 2
    x0 = -cx + L.total * OPTICAL_DX
    return (; L, x0, w=L.total, h=SIDE, cy)
end

function draw_mark!(pal)
    g = layout_mark()
    @layer begin
        translate(0, -g.cy)
        draw_q!(g.x0, pal)
        draw_ueue!(g.x0, pal)
    end
end

function mark!(; pal, canvas=CANVAS, margin=MARGIN, paint_bg=true)
    paint_bg && background(pal.bg...)
    g = layout_mark()
    s = canvas * (1 - 2 * margin) / max(g.w, g.h)
    @layer begin
        scale(s)
        draw_mark!(pal)
    end
end

function save_mark(name, pal)
    if WANT_PNG
        Drawing(CANVAS, CANVAS, joinpath(OUT, "$name.png"))
        origin()
        mark!(; pal, paint_bg=true)
        finish()
    end
    Drawing(CANVAS, CANVAS, joinpath(OUT, "$name.svg"))
    origin()
    mark!(; pal, paint_bg=false)
    finish()
    println("wrote $name")
end

function install_documenter!()
    pairs = (
        "logo-static.svg" => "logo.svg",
        "logo-dark-static.svg" => "logo-dark.svg",
    )
    for (src, dst) in pairs
        from = joinpath(OUT, src)
        to = joinpath(ASSETS, dst)
        cp(from, to; force=true)
        println("copied $dst")
    end
end

function social_lockup_x()
    g = layout_mark()
    s = MARK_SIZE * MARK_FIT / g.w
    ink_left = MARK_SIZE / 2 + s * g.x0
    group_w = MARK_SIZE + MARK_GAP + TEXT_ADV - ink_left
    side = (SOCIAL_W - group_w) / 2
    mark_x = round(Int, side - ink_left + LOCKUP_DX)
    return (; mark_x, text_x=mark_x + MARK_SIZE + MARK_GAP)
end

function svg_inner(svg::AbstractString)
    s = strip(svg)
    if startswith(s, "<?xml")
        i = findfirst("?>", s)
        i !== nothing && (s = lstrip(s[last(i) + 1:end]))
    end
    m = match(r"^<svg[^>]*>([\s\S]*)</svg>\s*$", s)
    m === nothing && error("could not strip outer <svg>")
    return m.captures[1]
end

function write_mark_slot(path)
    Drawing(MARK_SIZE, MARK_SIZE, path)
    origin()
    g = layout_mark()
    s = MARK_SIZE * MARK_FIT / g.w
    @layer begin
        scale(s)
        draw_mark!(pal_light())
    end
    finish()
end

function build_social(inner)
    x = social_lockup_x()
    slot_y = round(MARK_SLOT_Y; digits=3)
    return """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="$(SOCIAL_W)" height="$(SOCIAL_H)" viewBox="0 0 $(SOCIAL_W) $(SOCIAL_H)">
  <!-- social-preview-static: 1280×640; safe $(SAFE_X)×$(SAFE_Y); mark | title lockup -->
  <rect width="$(SOCIAL_W)" height="$(SOCIAL_H)" fill="#ffffff"/>
  <svg x="$(x.mark_x)" y="$(slot_y)" width="$(MARK_SIZE)" height="$(MARK_SIZE)" viewBox="0 0 $(MARK_SIZE) $(MARK_SIZE)">
$(inner)
  </svg>
  <text x="$(x.text_x)" y="$(TITLE_Y)" dominant-baseline="middle" fill="#0f172a" font-family="$(FONT)" font-size="$(TITLE_SIZE)" font-weight="800">$(TITLE)</text>
  <text x="$(x.text_x)" y="$(TAGLINE_Y1)" dominant-baseline="middle" fill="#475569" font-family="$(FONT)" font-size="$(TAGLINE_SIZE)" font-weight="500">$(TAGLINE_1)</text>
  <text x="$(x.text_x)" y="$(TAGLINE_Y2)" dominant-baseline="middle" fill="#475569" font-family="$(FONT)" font-size="$(TAGLINE_SIZE)" font-weight="500">$(TAGLINE_2)</text>
</svg>
"""
end

function raster_social!(svg_path, png_path)
    rsvg = Sys.which("rsvg-convert")
    if rsvg === nothing
        for p in ("/opt/homebrew/bin/rsvg-convert", "/usr/local/bin/rsvg-convert")
            isfile(p) && (rsvg = p; break)
        end
    end
    if rsvg !== nothing
        run(`$rsvg -w $(SOCIAL_W) -h $(SOCIAL_H) -o $png_path $svg_path`)
        return
    end
    Drawing(SOCIAL_W, SOCIAL_H, png_path)
    placeimage(readsvg(svg_path), Point(0, 0))
    finish()
end

function save_social()
    mkpath(SOCIAL)
    slot = joinpath(SOCIAL, ".mark-slot.svg")
    write_mark_slot(slot)
    svg_path = joinpath(SOCIAL, "social-preview-static.svg")
    write(svg_path, build_social(svg_inner(read(slot, String))))
    rm(slot)
    WANT_PNG && raster_social!(svg_path, joinpath(SOCIAL, "social-preview-static.png"))
    println("wrote social-preview-static")
end

function main()
    save_mark("logo-static", pal_light())
    save_mark("logo-dark-static", pal_dark())
    install_documenter!()
    save_social()
end

main()
