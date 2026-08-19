using Test
using DistSSHKit
using DistSSHKitQueue

function _wait_state(q, id, st; tries=200)
    for _ in 1:tries
        job(q, id).state === st && return nothing
        sleep(0.01)
    end
    error("job $id stayed $(job(q, id).state), expected $st")
end

@testset "true FIFO one at a time" begin
    started = String[]
    q = Queue(; runner=j -> (push!(started, j.id); sleep(0.05)))
    a = submit!(q, "a.jl", "worker:4")
    b = submit!(q, "b.jl", "worker:1")
    @test step!(q) == 1
    @test job(q, a).state === :running
    @test job(q, b).state === :queued
    @test step!(q) == 0
    _wait_state(q, a, :done)
    @test step!(q) == 1
    _wait_state(q, b, :done)
    @test started == [a, b]
end

@testset "cancel queued only" begin
    q = Queue(; runner=_ -> sleep(0.05))
    a = submit!(q, "a.jl", "local:2")
    b = submit!(q, "b.jl", "local:2")
    @test cancel!(q, b)
    @test job(q, b).state === :cancelled
    @test step!(q) == 1
    @test !cancel!(q, a)
    _wait_state(q, a, :done)
end

@testset "kit throw does not stall" begin
    q = Queue(; runner=j -> basename(j.script) == "bad.jl" ? error("boom") : nothing)
    a = submit!(q, "bad.jl", "local:1")
    b = submit!(q, "ok.jl", "local:1")
    @test step!(q) == 1
    _wait_state(q, a, :failed)
    @test occursin("boom", something(job(q, a).error, ""))
    @test step!(q) == 1
    _wait_state(q, b, :done)
end

@testset "kind=:drive" begin
    q = Queue(; runner=_ -> nothing)
    id = submit!(q, "d.jl", "local:1"; kind=:drive)
    j = job(q, id)
    @test j.kind === :drive
    @test haskey(j.kwargs, "project")
    @test !haskey(j.kwargs, "path_anchor")
    gid = submit!(q, "g.jl", "local:1")
    g = job(q, gid)
    @test g.kind === :go
    @test g.kwargs["path_anchor"] == g.kwargs["project"]
end

@testset "TOML store restart" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        ev = Base.Event()
        q = Queue(; store=p, runner=_ -> wait(ev))
        id = submit!(q, "a.jl", "local:1")
        @test step!(q) == 1
        @test job(q, id).state === :running
        q2 = Queue(; store=p, runner=_ -> nothing)
        load!(q2)
        notify(ev)
        _wait_state(q, id, :done)
        @test job(q2, id).state === :failed
        @test occursin("serve restarted", something(job(q2, id).error, ""))
    end
end

@testset "kit ok=false is failed" begin
    @test_throws ErrorException DistSSHKitQueue.require_kit_ok(:go, (ok=false,))
    @test DistSSHKitQueue.require_kit_ok(:go, (ok=true, output_dir="/tmp/out")) === nothing
    @test DistSSHKitQueue.kit_result_path((ok=true, output_dir="/tmp/out")) == "/tmp/out"
    q = Queue(; runner=_ -> error("DistSSHKit go failed (ok=false)"))
    id = submit!(q, "a.jl", "local:1")
    @test step!(q) == 1
    _wait_state(q, id, :failed)
end

@testset "result_path from runner and kwargs" begin
    q = Queue(; runner=_ -> "/tmp/kit-out")
    id = submit!(q, "a.jl", "local:1"; output_dir="/tmp/unused")
    @test step!(q) == 1
    _wait_state(q, id, :done)
    @test job(q, id).result_path == "/tmp/kit-out"

    q2 = Queue(; runner=_ -> nothing)
    id2 = submit!(q2, "b.jl", "local:1"; output_dir="/tmp/bag")
    @test step!(q2) == 1
    _wait_state(q2, id2, :done)
    @test job(q2, id2).result_path == "/tmp/bag"
end

@testset "orderer enqueue keeps running row" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        ev = Base.Event()
        q = Queue(; store=p, runner=_ -> wait(ev))
        a = submit!(q, "a.jl", "local:1")
        @test step!(q) == 1
        q2 = Queue(; store=p, runner=_ -> nothing)
        b = submit!(q2, "b.jl", "worker:2")
        rows = DistSSHKitQueue.read_jobs(p)
        @test job(q, a).state === :running
        @test any(j -> j.id == b && j.state === :queued, rows)
        @test any(j -> j.id == a && j.state === :running, rows)
        notify(ev)
        _wait_state(q, a, :done)
    end
end

@testset "CLI help and Kit go enqueue" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        jobdir = mktempdir()
        write(joinpath(jobdir, "Project.toml"), "[deps]\n")
        write(joinpath(jobdir, "job.jl"), "1\n")
        write(joinpath(jobdir, "alias.jl"), "1\n")
        write(joinpath(jobdir, "drv.jl"), "1\n")
        withenv("DISTSSHKITQUEUE_STORE" => p, "DISTRIBUTED_PROJECT_ROOT" => nothing) do
            cd(jobdir) do
                proj = DistSSHKit.canonical_local_path(pwd())
                @test DistSSHKitQueue.main(["-h"]) == 0
                @test DistSSHKitQueue.main(["status"]) == 0
                @test DistSSHKitQueue.main(["submit", "go", "worker:4", "job.jl"]) == 0
                rows = DistSSHKitQueue.read_jobs(p)
                @test length(rows) == 1
                @test rows[1].kind === :go
                @test rows[1].script == DistSSHKit.canonical_local_path(joinpath(pwd(), "job.jl"))
                @test rows[1].hosts == ["worker:4"]
                @test rows[1].state === :queued
                @test rows[1].kwargs["project"] == proj
                @test DistSSHKitQueue.main(["go", "local:1", "alias.jl"]) == 0
                @test DistSSHKitQueue.main(["submit", "drive", "local:2", "drv.jl"]) == 0
                rows = DistSSHKitQueue.read_jobs(p)
                @test length(rows) == 3
                @test rows[2].kind === :go
                @test rows[2].script == DistSSHKit.canonical_local_path(joinpath(pwd(), "alias.jl"))
                @test rows[3].kind === :drive
                @test rows[3].script == DistSSHKit.canonical_local_path(joinpath(pwd(), "drv.jl"))
                @test rows[3].hosts == ["local:2"]
                @test rows[3].kwargs["project"] == proj
            end
        end
    end
end
