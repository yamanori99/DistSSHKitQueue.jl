using Test
using DistSSHKitQueue

function _wait_state(h, id, st; tries=200)
    for _ in 1:tries
        placeholder_get(h, id).state === st && return nothing
        sleep(0.01)
    end
    error("job $id stayed $(placeholder_get(h, id).state), expected $st")
end

@testset "true FIFO one at a time" begin
    started = String[]
    h = Placeholder(; runner=j -> (push!(started, j.id); sleep(0.05)))
    a = placeholder!(h, "a.jl", "worker:4")
    b = placeholder!(h, "b.jl", "worker:1")
    @test placeholder_step!(h) == 1
    @test placeholder_get(h, a).state === :running
    @test placeholder_get(h, b).state === :queued
    @test placeholder_step!(h) == 0
    _wait_state(h, a, :done)
    @test placeholder_step!(h) == 1
    _wait_state(h, b, :done)
    @test started == [a, b]
end

@testset "cancel queued only" begin
    h = Placeholder(; runner=_ -> sleep(0.05))
    a = placeholder!(h, "a.jl", "local:2")
    b = placeholder!(h, "b.jl", "local:2")
    @test placeholder_cancel!(h, b)
    @test placeholder_get(h, b).state === :cancelled
    @test placeholder_step!(h) == 1
    @test !placeholder_cancel!(h, a)
    _wait_state(h, a, :done)
end

@testset "kit throw does not stall" begin
    h = Placeholder(; runner=j -> startswith(j.script, "bad") ? error("boom") : nothing)
    a = placeholder!(h, "bad.jl", "local:1")
    b = placeholder!(h, "ok.jl", "local:1")
    @test placeholder_step!(h) == 1
    _wait_state(h, a, :failed)
    @test occursin("boom", something(placeholder_get(h, a).error, ""))
    @test placeholder_step!(h) == 1
    _wait_state(h, b, :done)
end

@testset "drive=true sets kind" begin
    h = Placeholder(; runner=_ -> nothing)
    id = placeholder!(h, "d.jl", "local:1"; drive=true)
    @test placeholder_get(h, id).kind === :drive
end

@testset "TOML store restart" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        ev = Base.Event()
        h = Placeholder(; store=p, runner=_ -> wait(ev))
        id = placeholder!(h, "a.jl", "local:1")
        @test placeholder_step!(h) == 1
        @test placeholder_get(h, id).state === :running
        h2 = Placeholder(; store=p, runner=_ -> nothing)
        placeholder_load!(h2)
        notify(ev)
        _wait_state(h, id, :done)
        @test placeholder_get(h2, id).state === :failed
        @test occursin("serve restarted", something(placeholder_get(h2, id).error, ""))
    end
end

@testset "kit ok=false is failed" begin
    @test_throws ErrorException DistSSHKitQueue.require_kit_ok(:go, (ok=false,))
    @test DistSSHKitQueue.require_kit_ok(:go, (ok=true, output_dir="/tmp/out")) === nothing
    @test DistSSHKitQueue.kit_result_path((ok=true, output_dir="/tmp/out")) == "/tmp/out"
    h = Placeholder(; runner=_ -> error("DistSSHKit go failed (ok=false)"))
    id = placeholder!(h, "a.jl", "local:1")
    @test placeholder_step!(h) == 1
    _wait_state(h, id, :failed)
end

@testset "result_path from runner and kwargs" begin
    h = Placeholder(; runner=_ -> "/tmp/kit-out")
    id = placeholder!(h, "a.jl", "local:1"; output_dir="/tmp/unused")
    @test placeholder_step!(h) == 1
    _wait_state(h, id, :done)
    @test placeholder_get(h, id).result_path == "/tmp/kit-out"

    h2 = Placeholder(; runner=_ -> nothing)
    id2 = placeholder!(h2, "b.jl", "local:1"; output_dir="/tmp/bag")
    @test placeholder_step!(h2) == 1
    _wait_state(h2, id2, :done)
    @test placeholder_get(h2, id2).result_path == "/tmp/bag"
end

@testset "orderer enqueue keeps running row" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        ev = Base.Event()
        h = Placeholder(; store=p, runner=_ -> wait(ev))
        a = placeholder!(h, "a.jl", "local:1")
        @test placeholder_step!(h) == 1
        h2 = Placeholder(; store=p, runner=_ -> nothing)
        b = placeholder!(h2, "b.jl", "worker:2")
        rows = DistSSHKitQueue.load_jobs_raw(p)
        @test placeholder_get(h, a).state === :running
        @test any(j -> j.id == b && j.state === :queued, rows)
        @test any(j -> j.id == a && j.state === :running, rows)
        notify(ev)
        _wait_state(h, a, :done)
    end
end

@testset "CLI help and Kit go enqueue" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        withenv("DISTSSHKITQUEUE_STORE" => p) do
            @test DistSSHKitQueue.main(["-h"]) == 0
            @test DistSSHKitQueue.main(["status"]) == 0
            @test DistSSHKitQueue.cli_go(["worker:4", "job.jl"]) == 0
            jobs = DistSSHKitQueue.load_jobs_raw(p)
            @test length(jobs) == 1
            @test jobs[1].kind === :go
            @test jobs[1].script == "job.jl"
            @test jobs[1].hosts == ["worker:4"]
            @test jobs[1].state === :queued
        end
    end
end
