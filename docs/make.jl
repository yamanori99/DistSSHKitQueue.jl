using Documenter
using DistSSHKitQueue

DocMeta.setdocmeta!(DistSSHKitQueue, :DocTestSetup, :(using DistSSHKitQueue); recursive=true)

makedocs(;
    modules=[DistSSHKitQueue],
    authors="Takanori Yamamoto, Honoka Ampuku, and contributors",
    sitename="DistSSHKitQueue.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", nothing) == "true",
        canonical="https://yamanori99.github.io/DistSSHKitQueue.jl",
        edit_link="main",
        assets=["assets/custom.css"],
    ),
    pages=[
        "Introduction" => "index.md",
        "API" => "api.md",
    ],
    checkdocs=:none,
    warnonly=[:missing_docs, :docs_block, :cross_references],
)

deploydocs(;
    repo="github.com/yamanori99/DistSSHKitQueue.jl.git",
    devbranch="main",
    push_preview=true,
    versions=["dev" => "dev"],
)
