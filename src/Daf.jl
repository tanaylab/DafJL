"""
The `Daf.jl` package provides a uniform generic interface for accessing 1D and 2D data arranged along some set of axes.
This is a much-needed generalization of the [AnnData](https://pypi.org/project/anndata/) functionality. The key
features are:

  - The data model is based on (1) some axes with named entries, (2) vector data indexed by a single axis, (3) matrix
    data indexed by a pair of axes, and also (4) scalar data (anything not tied to some axis).
  - There is explicit control over 2D data layout (row or column major), and support for both dense and sparse matrices,
    both of which are crucial for performance.
  - A simple query language makes it easy to access the data, providing features such as slicing, aggregation, and
    filtering.
  - Support both in-memory and persistent data storage of "any" format (given an adapter implementation).
  - Out of the box, allow storing the data in memory, in `AnnData` objects (using `H5ad` files), directly inside
    [HDF5](https://www.hdfgroup.org/solutions/hdf5) files (using [`H5df`](@ref)), or as a collection of simple
    memory-mapped files in a directory (using `FilesDaf`), which works nicely with tools like `make` for automating
    computation pipelines.

The top-level `Daf` module re-exports all(most) everything from the sub-modules, so you can directly access any exported
symbol by `using Daf` (or `import Daf: MemoryStorage`), instead of having to import or use qualified names (such as
`Daf.Storage.MemoryStorage`).
"""
module Daf

using Reexport

include("generic.jl")

include("matrix_layouts.jl")
@reexport using Daf.MatrixLayouts

include("storage_types.jl")
@reexport using Daf.StorageTypes

include("messages.jl")
@reexport using Daf.Messages

include("registry.jl")
@reexport using Daf.Registry: EltwiseOperation, ReductionOperation

include("tokens.jl")
@reexport using Daf.Tokens

include("operations.jl")
@reexport using Daf.Operations

include("formats.jl")
@reexport using Daf.Formats

include("data.jl")
@reexport using Daf.Data

include("queries.jl")
@reexport using Daf.Queries

include("read_only.jl")
@reexport using Daf.ReadOnly

include("views.jl")
@reexport using Daf.Views

include("chains.jl")
@reexport using Daf.Chains

include("memory_format.jl")
@reexport using Daf.MemoryFormat

include("h5df_format.jl")
@reexport using Daf.H5dfFormat

include("files_format.jl")
@reexport using Daf.FilesFormat

include("anndata_format.jl")
@reexport using Daf.AnnDataFormat

include("contracts.jl")
@reexport using Daf.Contracts

include("computations.jl")
@reexport using Daf.Computations

include("copies.jl")
@reexport using Daf.Copies

include("concat.jl")
@reexport using Daf.Concat

include("adapters.jl")
@reexport using Daf.Adapters

include("example_data.jl")
@reexport using Daf.ExampleData

end # module
