#!/usr/bin/env julia
# Queue happy-path E2E against testenv/docker-ssh workers. Not part of Pkg.test().
#
# Proves the first-slice contract end to end with real SSH:
#   setup! deploys the lab project to the workers (DistSSHKit)
#   → enqueue a `go` job into the Queue store (orderer side)
#   → drive the waiter (controller side); it calls go! on the worker
#   → job reaches :done, result_path is the collected batch root
#   → peek (status) + fetch (read the collected file on the controller)
#
#   testenv/docker-ssh/scripts/up.sh --e2e
#   DSKQ_SSH_E2E=1 julia --project=test test/e2e.jl   # workers already up
#
# The host is the controller and the orderer. The containers are only
# DistSSHKit go/drive targets (host:N), never the Kit master.

using Test
using Dates
using DistSSHKit
using DistSSHKitQueue

const QUEUE_ROOT = abspath(joinpath(@__DIR__, ".."))
const DOCKER_SSH = joinpath(QUEUE_ROOT, "testenv", "docker-ssh")
const LAB_PROJECT = joinpath(QUEUE_ROOT, "testenv", "lab")
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

# ENV overlay so DistSSHKit reaches the containers via the generated SSH config.
const SSH_ENV = Dict(
    "DISTSSHKIT_YES" => "1",
    "DISTSSHKIT_QUIET" => get(ENV, "DISTSSHKIT_QUIET", "1"),
    "DISTRIBUTED_SSH_OPTS" => "-F $(SSH_CONFIG)",
    "DISTRIBUTED_REMOTE_PROJECT_ROOT" => REMOTE_ROOT,
)

"""Poll the store-backed waiter until `id` reaches a terminal state."""
function drive_until_terminal!(h, id; tries=600, sleep_s=0.2)
    terminal = (:done, :failed, :cancelled)
    for _ in 1:tries
        placeholder_step!(h)
        st = placeholder_get(h, id).state
        st in terminal && return st
        sleep(sleep_s)
    end
    return placeholder_get(h, id).state
end

@testset "Queue SSH E2E (docker-ssh)" verbose = true begin
    withenv(SSH_ENV...) do
        @testset "setup! deploys lab project to workers" begin
            session = KitSession(
                project = LAB_PROJECT,
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
            store = joinpath(d, "jobs.toml")
            out_dir = joinpath(d, "go_out")
            job_script = joinpath(LAB_PROJECT, "jobs", "pi_file.jl")
            host = HOSTS[1]

            @testset "orderer enqueues a go job" begin
                h = Placeholder(; store = store)
                id = placeholder!(
                    h,
                    job_script,
                    "$(host):1";
                    project = LAB_PROJECT,
                    remote = REMOTE_ROOT,
                    output_dir = out_dir,
                    julia = "auto",
                    args = ["20000"],
                    yes = true,
                    quiet = true,
                )
                rows = DistSSHKitQueue.load_jobs_raw(store)
                @test length(rows) == 1
                @test rows[1].id == id
                @test rows[1].state === :queued
                @test rows[1].kind === :go
            end

            local finished_id = ""
            @testset "controller waiter runs it to :done" begin
                h = Placeholder(; store = store)
                placeholder_load!(h)
                rows = placeholder_list(h)
                @test length(rows) == 1
                id = rows[1].id
                finished_id = id
                st = drive_until_terminal!(h, id)
                job = placeholder_get(h, id)
                @test st === :done
                @test job.result_path !== nothing
                @test job.result_path == DistSSHKit.canonical_local_path(out_dir)
            end

            @testset "peek + fetch the collected result" begin
                # Peek: status renders the terminal row with its result_path.
                buf = IOBuffer()
                DistSSHKitQueue.print_status(store; io = buf)
                text = String(take!(buf))
                @test occursin(finished_id, text)
                @test occursin(":done", text) || occursin("done", text)

                # Fetch: the collected batch root is on the controller (host).
                collected = joinpath(out_dir, host, "pi_results.txt")
                @test isfile(collected)
                @test occursin("pi=", read(collected, String))
            end
        end
    end
end
