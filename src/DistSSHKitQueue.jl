"""
DistSSHKitQueue — small-lab job queue on DistSSHKit (`go` / `drive`).

Design: [`DESIGN.md`](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/DESIGN.md).
The kitchen stays in DistSSHKit. This package is the hall (FIFO, occupancy,
long-lived head process).
"""
module DistSSHKitQueue

using Dates
using DistSSHKit
using TOML

export Hall
export QueueJob
export submit_go!
export submit_drive!
export jobs
export job
export cancel!
export step!
export run_head
export load!
export occupancy

include("DistSSHKitQueue/occupancy.jl")
include("DistSSHKitQueue/types.jl")
include("DistSSHKitQueue/store.jl")
include("DistSSHKitQueue/hall.jl")

end # module DistSSHKitQueue
