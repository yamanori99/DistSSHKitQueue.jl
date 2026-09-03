using Test
using DistSSHKit
using DistSSHQueue

function _wait_fetch_state(q, id, want::Symbol; tries::Int=200)
    for _ = 1:tries
        job(q, id).state === want && return nothing
        sleep(0.01)
    end
    error("job $(id) did not reach $(want) (have $(job(q, id).state))")
end

@testset "fetch relpath is the inverse of stage" begin
    stage = "/qh/.distsshqueue/stage/abc"
    id = "96392aaa-4387-5ffe-07ee-8f69406890bb"
    remote = stage * "/src/.distsshkit/go/S_20260101T000000_" * id
    rel = DistSSHQueue.fetch_relpath(remote, stage)
    @test rel == "src/.distsshkit/go/S_20260101T000000_" * id
    mktempdir() do d
        proj = joinpath(d, "job")
        mkpath(proj)
        dest = DistSSHQueue.fetch_dest(proj, rel)
        @test dest == DistSSHKit.canonical_local_path(joinpath(proj, rel))
        @test DistSSHQueue.path_has_distsshkit(dest)
    end
    @test_throws ArgumentError DistSSHQueue.fetch_relpath("/tmp/other", stage)
    @test DistSSHQueue.fetch_relpath("/a/.distsshkit/go/S", "/") == "a/.distsshkit/go/S"
    @test DistSSHQueue._rel_under("/a/b.jl", "/") == "a/b.jl"
    @test_throws ArgumentError DistSSHQueue.fetch_dest("/tmp/job", "out/custom")
end

@testset "fetch_source exact id and states" begin
    mktempdir() do d
        proj = joinpath(d, "job")
        mkpath(proj)
        script = joinpath(proj, "S.jl")
        write(script, "1\n")
        queued_store = joinpath(d, "queued.toml")
        q = Queue(; store=queued_store, runner=_ -> nothing)
        queued = submit!(q, script, "parent:1")
        @test_throws ArgumentError DistSSHQueue.fetch_source(queued; store=queued_store)
        @test_throws ArgumentError DistSSHQueue.fetch_source("no-such-id"; store=queued_store)

        store = joinpath(d, "jobs.toml")
        hold = Base.Event()
        leaf = Ref{String}()
        q2 = Queue(; store=store, runner=function (_)
            wait(hold)
            return leaf[]
        end)
        running = submit!(q2, script, "parent:1")
        leaf[] = joinpath(proj, ".distsshkit", "go", "S_t_" * running)
        mkpath(leaf[])
        @test step!(q2) == 1
        for _ = 1:200
            job(q2, running).state === :running && break
            sleep(0.01)
        end
        @test job(q2, running).state === :running
        notify(hold)
        _wait_fetch_state(q2, running, :done)
        line = DistSSHQueue.fetch_source(running; store=store)
        st, path = DistSSHQueue.parse_fetch_source(line)
        @test st === :done
        @test path == leaf[]
        DistSSHQueue.require_fetchable_leaf(running, path)
        custom = joinpath(proj, "out")
        @test_throws ArgumentError DistSSHQueue.require_fetchable_leaf(running, custom)
    end
end

@testset "fetch CLI identity on the queue host" begin
    mktempdir() do d
        proj = joinpath(d, "job")
        mkpath(proj)
        script = joinpath(proj, "S.jl")
        write(script, "1\n")
        store = joinpath(d, "jobs.toml")
        idbox = Ref{String}()
        q = Queue(; store=store, runner=function (_)
            leaf = joinpath(proj, ".distsshkit", "go", "S_t_" * idbox[])
            mkpath(leaf)
            write(joinpath(leaf, "kit.result"), "ok\n")
            return leaf
        end)
        id = submit!(q, script, "parent:1")
        idbox[] = id
        @test step!(q) == 1
        _wait_fetch_state(q, id, :done)
        want = DistSSHKit.canonical_local_path(joinpath(proj, ".distsshkit", "go", "S_t_" * id))
        withenv(
            "DISTSSHQUEUE_STORE" => store,
            "DISTSSHQUEUE_CONFIG" => joinpath(d, "missing.toml"),
            "DISTSSHQUEUE_HOST" => nothing,
            "DISTSSHQUEUE_NO_STAGE" => "1",
            "DISTRIBUTED_PROJECT_ROOT" => proj,
            "DISTSSHKIT_TEST_SSH" => nothing,
        ) do
            code, out, err = capture_stdio() do
                DistSSHQueue.main(["fetch", id])
            end
            @test code == 0
            @test isempty(err) || !occursin("Error:", err)
            @test strip(out) == want
            code_q, _, err_q = capture_stdio() do
                DistSSHQueue.main(["fetch", "no-such-id"])
            end
            @test code_q == 1
            @test occursin("unknown job", err_q)
            code_r, _, err_r = capture_stdio() do
                DistSSHQueue.main(["qhost:h", "fetch", id])
            end
            @test code_r == 1
            @test occursin("rsync", err_r)
            code_e, _, err_e = capture_stdio() do
                DistSSHQueue.main(["fetch"])
            end
            @test code_e == 1
            @test occursin("need a job id", err_e)
        end
    end
end

@testset "qhost submit ticket is not a Kit leaf" begin
    mktempdir() do d
        proj = joinpath(d, "job")
        mkpath(proj)
        script = joinpath(proj, "S.jl")
        write(script, "1\n")
        id = "96392aaa-4387-5ffe-07ee-8f69406890bb"
        @test DistSSHQueue.job_id_from_submit_stdout("Queued  1\n") === nothing
        @test DistSSHQueue.job_id_from_submit_stdout(id * "\n") == id
        dest = DistSSHQueue.write_submit_ticket(
            proj, id * "\n"; script=script, qhost="mini",
        )
        @test dest == DistSSHQueue.submit_ticket_path(proj, id)
        @test isfile(dest)
        body = read(dest, String)
        @test occursin("id = ", body)
        @test occursin("S.jl", body)
        @test occursin("qhost = \"mini\"", body)
        @test !occursin("/go/", dest)
        @test !occursin("/drive/", dest)
        @test DistSSHQueue.write_submit_ticket(proj, "not-an-id\n") === nothing
    end
end
