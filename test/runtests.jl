#!/usr/bin/env julia
# DistSSHKitQueue Pkg.test() entry.
# From a checkout of this directory as the active project:
#   julia --project=. -e 'using Pkg; Pkg.test()'

using Test
using DistSSHKitQueue

@testset "DistSSHKitQueue" verbose=true begin
    @test DistSSHKitQueue isa Module
end
