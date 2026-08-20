#!/usr/bin/env julia
# CLI + dskq wrapper + config store, local:1. Not part of Pkg.test().
# Covers explicit serve, auto-serve, cancel, teardown, and `--qhost` ssh argv.
#
#   DSKQ_CLI_E2E=1 julia --project=. test/cli_e2e.jl

using Test
using DistSSHKitQueue

const QUEUE_ROOT = abspath(joinpath(@__DIR__, ".."))

if get(ENV, "DSKQ_CLI_E2E", "") != "1"
    @info "Skipping CLI E2E (set DSKQ_CLI_E2E=1 to enable)"
    exit(0)
end

function wait_done(dskq, env; tries=600, sleep_s=0.2)
    for _ = 1:tries
        out = read(addenv(`$dskq status`, env...), String)
        occursin("  done  ", out) && return out
        occursin("  failed  ", out) && return out
        sleep(sleep_s)
    end
    return read(addenv(`$dskq status`, env...), String)
end

function stop_store_waiter(store::AbstractString)
    DistSSHKitQueue.stop_waiter!(store)
    return nothing
end

function write_fake_ssh(path::AbstractString, log::AbstractString)
    mkpath(dirname(path))
    write(
        path,
        """
#!/bin/sh
{
  for a in "\$@"; do
    printf '%s\\n' "\$a"
  done
  printf '%s\\n' "---"
} >> $(DistSSHKitQueue.sh_single_quote(log))
for a in "\$@"; do
  if [ "\$a" = "--version" ]; then
    printf '%s\\n' "julia version 1.12.7"
    exit 0
  fi
done
exit 0
""",
    )
    chmod(path, 0o755)
    return path
end

@testset "CLI E2E" begin
    mktempdir() do d
        bindir = joinpath(d, "bin")
        cfg = joinpath(d, "config.toml")
        store = joinpath(d, "jobs.toml")
        jobdir = joinpath(d, "job")
        mkpath(jobdir)
        write(joinpath(jobdir, "Project.toml"), "[deps]\n")
        write(joinpath(jobdir, "hello.jl"), "println(\"cli-e2e\")\n")
        write(joinpath(jobdir, "slow.jl"), "sleep(4)\n")
        write(cfg, "store = $(repr(store))\n\n[env]\nDISTSSHKIT_YES = \"1\"\n")
        julia = DistSSHKitQueue.default_julia_bin()
        baseenv = Dict(
            "DISTSSHKITQUEUE_CONFIG" => cfg,
            "DISTSSHKITQUEUE_STORE" => store,
            "DISTSSHKIT_YES" => "1",
        )
        withenv(baseenv..., "DISTSSHKITQUEUE_NO_AUTOSERVE" => "1") do
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

        @testset "setup submit status local:1 (explicit serve)" begin
            env = merge(baseenv, Dict("DISTSSHKITQUEUE_NO_AUTOSERVE" => "1"))
            serve_cmd = addenv(`$dskq serve --interval 0.1`, env...)
            proc = run(serve_cmd; wait=false)
            try
                cd(jobdir) do
                    id = strip(read(addenv(`$dskq submit go local:1 hello.jl`, env...), String))
                    @test !isempty(id)
                    out = wait_done(dskq, env)
                    @test occursin(id, out)
                    @test occursin("  done  ", out)
                end
            finally
                kill(proc)
                wait(proc)
            end
        end

        @testset "auto-serve submit and cancel queued" begin
            env = copy(baseenv)
            cd(jobdir) do
                id1 = strip(read(addenv(`$dskq submit go local:1 slow.jl`, env...), String))
                id2 = strip(read(addenv(`$dskq submit go local:1 hello.jl`, env...), String))
                @test !isempty(id1)
                c = strip(read(addenv(`$dskq cancel $id2`, env...), String))
                @test c == id2
                out = wait_done(dskq, env)
                @test occursin(id1, out)
                @test occursin("  done  ", out)
                st2 = read(addenv(`$dskq status`, env...), String)
                @test occursin(id2, st2)
                @test occursin("cancelled", st2)
            end
            stop_store_waiter(store)
        end

        @testset "--qhost HOST ssh argv (no remote exec)" begin
            log = joinpath(d, "ssh.log")
            fake = joinpath(d, "fakebin")
            write_fake_ssh(joinpath(fake, "ssh"), log)
            path = fake * ":" * get(ENV, "PATH", "")
            withenv(baseenv..., "PATH" => path) do
                @test DistSSHKitQueue.main([
                    "--qhost", "cluster-a",
                    "--remote-julia", julia,
                    "status",
                ]) == 0
            end
            dumped = read(log, String)
            @test occursin("cluster-a", dumped)
            @test occursin("DistSSHKitQueue", dumped)
            @test occursin("status", dumped)
        end
    end

    @testset "teardown -y after setup" begin
        mktempdir() do home
            data = joinpath(home, ".distsshkitqueue")
            bindir = joinpath(home, ".local", "bin")
            julia = DistSSHKitQueue.default_julia_bin()
            withenv("DISTSSHKITQUEUE_CONFIG" => nothing, "DISTSSHKITQUEUE_STORE" => nothing) do
                @test DistSSHKitQueue.main([
                    "setup",
                    "--julia", julia,
                    "--project", QUEUE_ROOT,
                    "--bindir", bindir,
                    "--config", joinpath(data, "config.toml"),
                    "--write-only",
                ]) == 0
                @test isfile(joinpath(bindir, "dskq"))
                @test DistSSHKitQueue.main([
                    "teardown",
                    "--home", home,
                    "-y",
                    "--write-only",
                ]) == 0
            end
            @test !isfile(joinpath(bindir, "dskq"))
            @test !isdir(data)
        end
    end
end
