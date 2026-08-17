using Test
using DistSSHKitQueue

function _wait_state(h, id, st; tries=200)
    for _ in 1:tries
        job(h, id).state === st && return nothing
        sleep(0.01)
    end
    error("job $id stayed $(job(h, id).state), expected $st")
end

@testset "occupancy tokens" begin
    @test DistSSHKitQueue.demand_map(["local:2", "l:1"]) == Dict("local" => 3)
    @test DistSSHKitQueue.host_key("localhost") == "local"
end

@testset "true FIFO" begin
    started = String[]
    h = Hall(; slots=["mini:4"], runner=j -> (push!(started, j.id); sleep(0.05)))
    a = submit_go!(h, "a.jl", "mini:4")
    b = submit_go!(h, "b.jl", "mini:1")
    @test step!(h) == 1
    @test job(h, a).state === :running
    @test job(h, b).state === :queued
    @test occupancy(h).used["mini"] == 4
    _wait_state(h, a, :done)
    @test step!(h) == 1
    _wait_state(h, b, :done)
    @test started == [a, b]
end

@testset "pack consecutive jobs that fit" begin
    h = Hall(; slots=["mini:4"], runner=_ -> sleep(0.05))
    a = submit_go!(h, "a.jl", "mini:2")
    b = submit_go!(h, "b.jl", "mini:2")
    @test step!(h) == 2
    @test job(h, a).state === :running
    @test job(h, b).state === :running
    _wait_state(h, a, :done)
    _wait_state(h, b, :done)
end

@testset "cancel queued only" begin
    h = Hall(; slots=["local:2"], runner=_ -> sleep(0.05))
    a = submit_go!(h, "a.jl", "local:2")
    b = submit_go!(h, "b.jl", "local:2")
    @test cancel!(h, b)
    @test job(h, b).state === :cancelled
    @test step!(h) == 1
    @test !cancel!(h, a)
    _wait_state(h, a, :done)
end

@testset "kit throw does not stall the hall" begin
    h = Hall(; slots=["local:1"], runner=j -> startswith(j.script, "bad") ? error("boom") : nothing)
    a = submit_go!(h, "bad.jl", "local:1")
    b = submit_go!(h, "ok.jl", "local:1")
    @test step!(h) == 1
    _wait_state(h, a, :failed)
    @test occursin("boom", job(h, a).error)
    @test step!(h) == 1
    _wait_state(h, b, :done)
end

@testset "TOML store restart" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        ev = Base.Event()
        h = Hall(; slots=["local:1"], store=p, runner=_ -> wait(ev))
        id = submit_go!(h, "a.jl", "local:1")
        @test step!(h) == 1
        @test job(h, id).state === :running
        h2 = Hall(; slots=["local:1"], store=p, runner=_ -> nothing)
        load!(h2)
        notify(ev)
        @test job(h2, id).state === :failed
        @test occursin("head restarted", job(h2, id).error)
    end
end
