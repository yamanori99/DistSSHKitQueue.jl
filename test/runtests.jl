#!/usr/bin/env julia
# DistSSHKitQueue Pkg.test() entry: unit + integration.
# Does not include test/e2e.jl (real SSH; DSKQ_SSH_E2E=1 / up.sh --e2e).
# From a checkout of this directory as the active project:
#   julia --project=. -e 'using Pkg; Pkg.test()'
#
# Top-level `include`s (inside `@testset`s, not functions) so JETLS follows them.

using Test
using DistSSHKitQueue

include(joinpath(@__DIR__, "support.jl"))
install_serve_reaper!()

@testset "DistSSHKitQueue" verbose=true begin
    @testset "unit" verbose=true begin
        include(joinpath(@__DIR__, "unit", "queue.jl"))
        include(joinpath(@__DIR__, "unit", "config.jl"))
    end
    @testset "integration" verbose=true begin
        include(joinpath(@__DIR__, "integration", "cli.jl"))
    end
end
