#!/usr/bin/env julia
# Queue SSH E2E against testenv/docker-ssh workers. Not part of Pkg.test().
#
# Stages DistSSHKit `demos/` into testenv/example-job, setup! to the workers,
# then enqueue Kit go/drive jobs through the Queue waiter
# (same as CLI `submit go` / `submit drive`). The waiter runs
# DistSSHKit `execute!(…; detached=true)`.
#
# README CLI (`julia -m DistSSHKitQueue`) is test/e2e_readme_cli.jl: queue-host
# verbs locally, client `--qhost` over a loopback OpenSSH, Kit slots on
# docker-ssh (`dskq-w1:1`). Not a laptop + `local:N` topology.
#
# Table jobs are the four *file*/*echo* demos. `pipeline_pi.jl` /
# `pipeline_square.jl` call `go!` / `pipeline!` themselves — not Queue rows.
#
# Also: FIFO one-at-a-time, cancel-queued (skip that row, run the next).
#
#   testenv/docker-ssh/scripts/up.sh --e2e
#   DSKQ_SSH_E2E=1 julia --project=test test/e2e.jl

using Test
using Dates
using Sockets
using DistSSHKit
using DistSSHKitQueue

include(joinpath(@__DIR__, "e2e_readme_cli.jl"))

const QUEUE_ROOT = abspath(joinpath(@__DIR__, ".."))
const DOCKER_SSH = joinpath(QUEUE_ROOT, "testenv", "docker-ssh")
const JOB_PROJECT = joinpath(QUEUE_ROOT, "testenv", "example-job")
const REMOTE_ROOT = "/home/dev/dskq-e2e"

_e2e_enabled() = get(ENV, "DSKQ_SSH_E2E", "") == "1"

if !_e2e_enabled()
    @info "Skipping Queue SSH E2E (set DSKQ_SSH_E2E=1 to enable)"
    exit(0)
end

const SSH_CONFIG = joinpath(DOCKER_SSH, ".generated", "ssh_config")
const HOSTS_FILE = joinpath(DOCKER_SSH, ".generated", "hosts")

if !isfile(SSH_CONFIG) || !isfile(HOSTS_FILE)
    error("docker-ssh not ready: missing $(SSH_CONFIG). Run testenv/docker-ssh/scripts/up.sh")
end

function read_hosts(path)
    hosts = String[]
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, "#")) && continue
        push!(hosts, s)
    end
    return hosts
end

const HOSTS = read_hosts(HOSTS_FILE)
length(HOSTS) >= 1 || error("no hosts in $HOSTS_FILE")

const SSH_ENV = Dict(
    "DISTSSHKIT_YES" => "1",
    "DISTSSHKIT_QUIET" => get(ENV, "DISTSSHKIT_QUIET", "1"),
    "DISTRIBUTED_SSH_OPTS" => "-F $(SSH_CONFIG)",
    "DISTRIBUTED_REMOTE_PROJECT_ROOT" => REMOTE_ROOT,
)

function kit_root()::String
    p = pathof(DistSSHKit)
    p isa AbstractString || error("DistSSHKit is loaded without a file path")
    return dirname(dirname(String(p)))
end

function stage_kit_demos!(proj::AbstractString)
    kit = kit_root()
    for (subdir, names) in (
        ("without_kit", ("pi_file.jl", "pi_echo.jl")),
        ("with_kit", ("square_file.jl", "square_echo.jl")),
    )
        dest = joinpath(proj, "demos", subdir)
        mkpath(dest)
        for name in names
            src = joinpath(kit, "demos", subdir, name)
            isfile(src) || error("missing DistSSHKit demo: $src")
            cp(src, joinpath(dest, name); force = true)
        end
    end
    return nothing
end

"""Poll until `id` is terminal. Does not start a later queued job once `id` is done."""
function drive_until_terminal!(q, id; tries = 600, sleep_s = 0.2)
    terminal = (:done, :failed, :cancelled)
    for _ = 1:tries
        st = job(q, id).state
        st in terminal && return st
        step!(q)
        sleep(sleep_s)
    end
    return job(q, id).state
end

function enqueue_kit!(q, kind::Symbol, script::AbstractString, token::AbstractString; out::AbstractString, args::Vector{String})
    return submit!(
        q,
        script,
        String[token];
        kind = kind,
        project = JOB_PROJECT,
        remote = REMOTE_ROOT,
        output_dir = out,
        julia = "auto",
        args = args,
        yes = true,
        quiet = true,
    )
end

function find_named(dir, name::AbstractString)
    isdir(dir) || return nothing
    target = String(name)
    for (root, _, files) in walkdir(dir)
        for f in files
            f == target && return joinpath(root, f)
        end
    end
    return nothing
end

@testset "Queue SSH E2E (docker-ssh)" verbose = true begin
    withenv(SSH_ENV...) do
        kit = kit_root()
        @testset "pipeline_* demos are Kit API scripts, not Queue jobs" begin
            @test isfile(joinpath(kit, "demos", "without_kit", "pipeline_pi.jl"))
            @test isfile(joinpath(kit, "demos", "with_kit", "pipeline_square.jl"))
            pi_src = read(joinpath(kit, "demos", "without_kit", "pipeline_pi.jl"), String)
            sq_src = read(joinpath(kit, "demos", "with_kit", "pipeline_square.jl"), String)
            @test occursin("go!", pi_src)
            @test occursin("pipeline!", sq_src)
        end

        stage_kit_demos!(JOB_PROJECT)

        @testset "setup! deploys example job (Kit demos + DistSSHKit)" begin
            session = KitSession(
                project = JOB_PROJECT,
                workers = HOSTS,
                remote = REMOTE_ROOT,
                yes = true,
                quiet = true,
            )
            prep = setup!(session, :delete, :rsync, :instantiate)
            @test prep.ok
            @test length(prep.hosts) == length(HOSTS)
            @test all(h -> h.ok, prep.hosts)
        end

        mktempdir() do d
            host = HOSTS[1]
            token = "$(host):1"

            @testset "Kit go/drive demos through the waiter" begin
                cases = (
                    (
                        :go,
                        joinpath(JOB_PROJECT, "demos", "without_kit", "pi_file.jl"),
                        "pi_file",
                        ["64"],
                        "pi_results.txt",
                        "pi=",
                    ),
                    (
                        :go,
                        joinpath(JOB_PROJECT, "demos", "without_kit", "pi_echo.jl"),
                        "pi_echo",
                        ["64"],
                        nothing,
                        nothing,
                    ),
                    (
                        :drive,
                        joinpath(JOB_PROJECT, "demos", "with_kit", "square_file.jl"),
                        "square_file",
                        ["3"],
                        "square_results.csv",
                        "param,result",
                    ),
                    (
                        :drive,
                        joinpath(JOB_PROJECT, "demos", "with_kit", "square_echo.jl"),
                        "square_echo",
                        ["3"],
                        nothing,
                        nothing,
                    ),
                )
                for (kind, script, label, args, artifact, needle) in cases
                    @testset "$label" begin
                        case_store = joinpath(d, "store_$label.toml")
                        out = joinpath(JOB_PROJECT, "go_out", label)
                        isdir(out) && rm(out; recursive = true)
                        q = Queue(; store = case_store)
                        id = enqueue_kit!(q, kind, script, token; out = out, args = args)
                        @test job(q, id).kind === kind
                        waiter = Queue(; store = case_store)
                        load!(waiter)
                        st = drive_until_terminal!(waiter, id)
                        row = job(waiter, id)
                        st === :done || @warn "job not done" label state = st error = row.error
                        @test st === :done
                        @test row.kind === kind
                        if artifact !== nothing
                            found = find_named(out, artifact)
                            @test found !== nothing
                            if found !== nothing
                                @test occursin(needle, read(found, String))
                            end
                        end
                    end
                end
            end

            @testset "FIFO one Kit job at a time" begin
                store_fifo = joinpath(d, "fifo.toml")
                echo = joinpath(JOB_PROJECT, "demos", "without_kit", "pi_echo.jl")
                q = Queue(; store = store_fifo)
                out_a = joinpath(JOB_PROJECT, "go_out", "fifo_a")
                out_b = joinpath(JOB_PROJECT, "go_out", "fifo_b")
                isdir(out_a) && rm(out_a; recursive = true)
                isdir(out_b) && rm(out_b; recursive = true)
                a = enqueue_kit!(q, :go, echo, token; out = out_a, args = ["64"])
                b = enqueue_kit!(q, :go, echo, token; out = out_b, args = ["64"])
                @test step!(q) == 1
                @test job(q, a).state === :running
                @test job(q, b).state === :queued
                @test step!(q) == 0
                @test drive_until_terminal!(q, a) === :done
                @test step!(q) == 1
                @test drive_until_terminal!(q, b) === :done
                fa = job(q, a).finished_at
                sb = job(q, b).started_at
                @test fa isa DateTime && sb isa DateTime && fa <= sb
            end

            @testset "cancel queued skips that row" begin
                store_c = joinpath(d, "cancel.toml")
                echo = joinpath(JOB_PROJECT, "demos", "without_kit", "pi_echo.jl")
                h = Queue(; store = store_c)
                outs = [joinpath(JOB_PROJECT, "go_out", "skip_$i") for i = 1:3]
                for o in outs
                    isdir(o) && rm(o; recursive = true)
                end
                a = enqueue_kit!(h, :go, echo, token; out = outs[1], args = ["64"])
                b = enqueue_kit!(h, :go, echo, token; out = outs[2], args = ["64"])
                c = enqueue_kit!(h, :go, echo, token; out = outs[3], args = ["64"])
                @test cancel!(h, b)
                @test job(h, b).state === :cancelled
                @test step!(h) == 1
                @test job(h, a).state === :running
                @test !cancel!(h, a)
                @test drive_until_terminal!(h, a) === :done
                @test step!(h) == 1
                @test job(h, c).state === :running
                @test drive_until_terminal!(h, c) === :done
                @test job(h, b).state === :cancelled
                @test step!(h) == 0
            end
        end

        readme_cli_e2e(;
            queue_root = QUEUE_ROOT,
            docker_ssh = DOCKER_SSH,
            job_project = JOB_PROJECT,
            remote_root = REMOTE_ROOT,
            ssh_config = SSH_CONFIG,
            hosts = HOSTS,
        )
    end
end
