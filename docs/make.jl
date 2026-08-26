using Documenter
using DistSSHQueue

DocMeta.setdocmeta!(DistSSHQueue, :DocTestSetup, :(using DistSSHQueue); recursive=true)

makedocs(;
    modules=[DistSSHQueue],
    authors="Takanori Yamamoto, Honoka Ampuku, and contributors",
    sitename="DistSSHQueue.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", nothing) == "true",
        canonical="https://yamanori99.github.io/DistSSHQueue.jl",
        edit_link="main",
        assets=["assets/custom.css"],
    ),
    pages=[
        "Introduction" => "index.md",
        "First Steps" => [
            "Requirements" => "requirements.md",
            "Prepare" => "tutorial/prepare.md",
            "First job" => "tutorial/client.md",
        ],
        "User Guide" => [
            "Overview" => "manual/index.md",
            "submit" => "manual/submit.md",
            "status" => "manual/status.md",
            "fetch" => "manual/fetch.md",
            "hosts" => "manual/hosts.md",
            "serve" => "manual/serve.md",
            "setup" => "manual/setup.md",
        ],
        "API" => "api.md",
    ],
    checkdocs=:none,
    warnonly=[:missing_docs, :docs_block, :cross_references],
)

deploydocs(;
    repo="github.com/yamanori99/DistSSHQueue.jl.git",
    devbranch="main",
    push_preview=true,
    versions=["stable" => "v^", "v#.#", "dev" => "dev"],
)
