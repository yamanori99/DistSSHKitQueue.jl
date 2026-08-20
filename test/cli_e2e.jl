#!/usr/bin/env julia
# CLI + dskq wrapper + config store, local:1 only. Not part of Pkg.test().
#
#   DSKQ_CLI_E2E=1 julia --project=. test/cli_e2e.jl

using Test
using DistSSHKitQueue

const QUEUE_ROOT = abspath(joinpath(@__DIR__, ".."))

if get(ENV, "DSKQ_CLI_E2E", "") != "1"
    @info "Skipping CLI E2E (set DSKQ_CLI_E2E=1 to enable)"
    exit(0)
end

function wait_done(dskq, cfg; tries=600, sleep_s=0.2)
    for _ = 1:tries
        out = read(addenv(`$dskq status`, "DISTSSHKITQUEUE_CONFIG" => cfg), String)
        occursin("  done  ", out) && return out
        occursin("  failed  ", out) && return out
        sleep(sleep_s)
    end
    return read(addenv(`$dskq status`, "DISTSSHKITQUEUE_CONFIG" => cfg), String)
end

@testset "dskq setup submit status local:1" begin
    mktempdir() do d
        bindir = joinpath(d, "bin")
        cfg = joinpath(d, "config.toml")
        store = joinpath(d, "jobs.toml")
        jobdir = joinpath(d, "job")
        mkpath(jobdir)
        write(joinpath(jobdir, "Project.toml"), "[deps]\n")
        write(joinpath(jobdir, "hello.jl"), "println(\"cli-e2e\")\n")
        write(cfg, "store = $(repr(store))\n\n[env]\nDISTSSHKIT_YES = \"1\"\n")
        julia = DistSSHKitQueue.default_julia_bin()
        env = Dict(
            "DISTSSHKITQUEUE_CONFIG" => cfg,
            "DISTSSHKIT_YES" => "1",
            "DISTSSHKITQUEUE_NO_AUTOSERVE" => "1", # this test drives serve explicitly
        )
        withenv(env...) do
            @test DistSSHKitQueue.main([
                "setup",
                "--julia", julia,
                "--project", QUEUE_ROOT,
                "--bindir", bindir,
                "--config", cfg,
                "--write-only",
            ]) == 0
        end
        dskq = joinpath(bindir, "dskq")
        @test isfile(dskq)
        serve_cmd = addenv(`$dskq serve --interval 0.1`, env...)
        proc = run(serve_cmd; wait=false)
        try
            cd(jobdir) do
                submit = addenv(`$dskq submit go local:1 hello.jl`, env...)
                id = strip(read(submit, String))
                @test !isempty(id)
                out = wait_done(dskq, cfg)
                @test occursin(id, out)
                @test occursin("  done  ", out)
            end
        finally
            kill(proc)
            wait(proc)
        end
    end
end
