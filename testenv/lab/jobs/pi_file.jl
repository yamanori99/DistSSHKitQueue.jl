#!/usr/bin/env julia
# Queue happy-path go job. Imports no kit and no queue (DESIGN: go job files
# stay plain). Monte Carlo π; writes pi_results.txt into the slot output dir
# that DistSSHKit sets, so `go!(output_dir=)` collects it to the controller.
#
#   julia --project=testenv/lab -m DistSSHKitQueue go testenv/lab/jobs/pi_file.jl dskq-w1:1

using Random

function main()
    n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1000

    env = strip(get(ENV, "DISTRIBUTED_OUTPUT_DIR", ""))
    outdir = isempty(env) ? joinpath(@__DIR__, "output") : env
    mkpath(outdir)

    Random.seed!(42)

    inside = 0
    for _ in 1:n
        x, y = rand(), rand()
        if x * x + y * y <= 1.0
            inside += 1
        end
    end
    pi_hat = 4.0 * inside / n

    out_path = joinpath(outdir, "pi_results.txt")
    write(out_path, "n=$n inside=$inside pi=$pi_hat\n")
    println("wrote pi=$pi_hat to $out_path")
end

main()
