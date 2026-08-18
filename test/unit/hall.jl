using Test
using DistSSHKitQueue

function _wait_state(h, id, st; tries=200)
    for _ in 1:tries
        placeholder_get(h, id).state === st && return nothing
        sleep(0.01)
    end
    error("job $id stayed $(placeholder_get(h, id).state), expected $st")
end

@testset "occupancy tokens" begin
    @test DistSSHKitQueue.demand_map(["local:2", "l:1"]) == Dict("local" => 3)
    @test DistSSHKitQueue.host_key("localhost") == "local"
end

@testset "true FIFO" begin
    started = String[]
    h = Placeholder(; slots=["mini:4"], runner=j -> (push!(started, j.id); sleep(0.05)))
    a = placeholder!(h, "a.jl", "mini:4")
    b = placeholder!(h, "b.jl", "mini:1")
    @test placeholder_step!(h) == 1
    @test placeholder_get(h, a).state === :running
    @test placeholder_get(h, b).state === :queued
    @test placeholder_slots(h).used["mini"] == 4
    _wait_state(h, a, :done)
    @test placeholder_step!(h) == 1
    _wait_state(h, b, :done)
    @test started == [a, b]
end

@testset "pack consecutive jobs that fit" begin
    h = Placeholder(; slots=["mini:4"], runner=_ -> sleep(0.05))
    a = placeholder!(h, "a.jl", "mini:2")
    b = placeholder!(h, "b.jl", "mini:2")
    @test placeholder_step!(h) == 2
    @test placeholder_get(h, a).state === :running
    @test placeholder_get(h, b).state === :running
    _wait_state(h, a, :done)
    _wait_state(h, b, :done)
end

@testset "cancel queued only" begin
    h = Placeholder(; slots=["local:2"], runner=_ -> sleep(0.05))
    a = placeholder!(h, "a.jl", "local:2")
    b = placeholder!(h, "b.jl", "local:2")
    @test placeholder_cancel!(h, b)
    @test placeholder_get(h, b).state === :cancelled
    @test placeholder_step!(h) == 1
    @test !placeholder_cancel!(h, a)
    _wait_state(h, a, :done)
end

@testset "kit throw does not stall" begin
    h = Placeholder(; slots=["local:1"], runner=j -> startswith(j.script, "bad") ? error("boom") : nothing)
    a = placeholder!(h, "bad.jl", "local:1")
    b = placeholder!(h, "ok.jl", "local:1")
    @test placeholder_step!(h) == 1
    _wait_state(h, a, :failed)
    @test occursin("boom", placeholder_get(h, a).error)
    @test placeholder_step!(h) == 1
    _wait_state(h, b, :done)
end

@testset "drive=true sets kind" begin
    h = Placeholder(; slots=["local:1"], runner=_ -> nothing)
    id = placeholder!(h, "d.jl", "local:1"; drive=true)
    @test placeholder_get(h, id).kind === :drive
end

@testset "TOML store restart" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        ev = Base.Event()
        h = Placeholder(; slots=["local:1"], store=p, runner=_ -> wait(ev))
        id = placeholder!(h, "a.jl", "local:1")
        @test placeholder_step!(h) == 1
        @test placeholder_get(h, id).state === :running
        h2 = Placeholder(; slots=["local:1"], store=p, runner=_ -> nothing)
        placeholder_load!(h2)
        notify(ev)
        @test placeholder_get(h2, id).state === :failed
        @test occursin("head restarted", placeholder_get(h2, id).error)
    end
end
