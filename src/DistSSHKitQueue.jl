"""
DistSSHKitQueue — small-lab job queue on DistSSHKit (`go` / `drive`).

Design: [`DESIGN.md`](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/DESIGN.md).
The kitchen stays in DistSSHKit. This package is the hall (FIFO, occupancy,
long-lived head process). Not registered yet.
"""
module DistSSHKitQueue

using DistSSHKit

# Public surface grows with DESIGN.md. Keep job files free of DistSSHKit imports.

end # module DistSSHKitQueue
