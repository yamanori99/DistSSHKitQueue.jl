"""
DistSSHKitQueue — small-lab job queue on DistSSHKit (`go` / `drive`).

Design: [`DESIGN.md`](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/DESIGN.md).
Public names are placeholders until the CLI exists.
"""
module DistSSHKitQueue

using Dates
using DistSSHKit
using TOML

export Placeholder
export PlaceholderJob
export placeholder!
export placeholder_list
export placeholder_get
export placeholder_cancel!
export placeholder_step!
export placeholder_head
export placeholder_load!
export placeholder_slots

include("DistSSHKitQueue/occupancy.jl")
include("DistSSHKitQueue/types.jl")
include("DistSSHKitQueue/store.jl")
include("DistSSHKitQueue/hall.jl")

end # module DistSSHKitQueue
