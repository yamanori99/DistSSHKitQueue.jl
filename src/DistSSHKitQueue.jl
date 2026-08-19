"""
DistSSHKitQueue — small-lab job queue on DistSSHKit (`go` / `drive`).

Enqueue from the CLI with `submit go` / `submit drive` (Kit argv after that).
`serve` waits; `status` lists the table.

Design: [`DESIGN.md`](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/DESIGN.md).
Public Julia names are placeholders.
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
export serve!
export serve
export default_store_path
export main

include("DistSSHKitQueue/types.jl")
include("DistSSHKitQueue/store.jl")
include("DistSSHKitQueue/wait.jl")
include("DistSSHKitQueue/cli.jl")

if VERSION >= v"1.12"
    Base.eval(@__MODULE__, :(@main))
end

end # module DistSSHKitQueue
