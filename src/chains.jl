"""
View a chain of `Daf` data as a single data set. This allows creating a small `Daf` data set that contains extra (or
overriding) data on top of a larger read-only data set. In particular this allows creating several such incompatible
extra data sets (e.g., different groupings of cells to metacells), without having to duplicate the common (read only)
data.
"""
module Chains

export chain_reader
export chain_writer

using ..Formats
using ..GenericTypes
using ..Messages
using ..ReadOnly
using ..Readers
using ..StorageTypes
using ..Writers
using SparseArrays

import ..Formats.FormatReader
import ..Formats.Internal
import ..Formats.as_read_only_array
import ..Messages
import ..ReadOnly.DafReadOnlyWrapper

"""
    struct ReadOnlyChain <: DafReadOnly ... end

A wrapper for a chain of [`DafReader`](@ref) data, presenting them as a single `DafReadOnly`. When accessing the
content, the exposed value is that provided by the last data set that contains the data, that is, later data sets can
override earlier data sets. However, if an axis exists in more than one data set in the chain, then its entries must be
identical. This isn't typically created manually; instead call [`chain_reader`](@ref).
"""
struct ReadOnlyChain <: DafReadOnly
    internal::Internal
    dafs::Vector{DafReader}
end

"""
    struct WriteChain <: DafWriter ... end

A wrapper for a chain of [`DafReader`](@ref) data, with a final [`DafWriter`], presenting them as a single `DafWriter`.
When accessing the content, the exposed value is that provided by the last data set that contains the data, that is,
later data sets can override earlier data sets (where the writer has the final word). However, if an axis exists in more
than one data set in the chain, then its entries must be identical. This isn't typically created manually; instead call
[`chain_reader`](@ref).

Any modifications or additions to the chain are directed at the final writer. Deletions are only allowed for data that
exists only in this writer. That is, it is impossible to delete from a chain something that exists in any of the
readers; it is only possible to override it.
"""
struct WriteChain <: DafWriter
    internal::Internal
    dafs::Vector{DafReader}
    daf::DafWriter
end

"""
    chain_reader(dafs::AbstractVector{F}; name::Maybe{AbstractString} = nothing)::DafReader where {F <: DafReader}

Create a read-only chain wrapper of [`DafReader`](@ref)s, presenting them as a single `DafReader`. When accessing the
content, the exposed value is that provided by the last data set that contains the data, that is, later data sets can
override earlier data sets. However, if an axis exists in more than one data set in the chain, then its entries must be
identical. This isn't typically created manually; instead call [`chain_reader`](@ref).

!!! note

    While this verifies the axes are consistent at the time of creating the chain, it's no defense against modifying the
    chained data after the fact, creating inconsistent axes. *Don't do that*.
"""
function chain_reader(
    dafs::AbstractVector{F};
    name::Maybe{AbstractString} = nothing,
)::DafReadOnly where {F <: DafReader}
    if isempty(dafs)
        error("empty chain$(name_suffix(name))")
    end

    if length(dafs) == 1
        return read_only(dafs[1]; name = name)
    end

    if name === nothing
        name = join([daf.name for daf in dafs], ";")
        @assert name !== nothing
    end

    internal_dafs = reader_internal_dafs(dafs, name)
    return ReadOnlyChain(Internal(name), internal_dafs)
end

"""
    chain_writer(dafs::AbstractVector{F}; name::Maybe{AbstractString} = nothing)::DafWriter where {F <: DafReader}

Create a chain wrapper for a chain of [`DafReader`](@ref) data, presenting them as a single `DafWriter`. This acts
similarly to [`chain_reader`](@ref), but requires the final entry to be a [`DafWriter`](@ref). Any modifications or
additions to the chain are directed at this final writer.

!!! note

    Deletions are only allowed for data that exists only in the final writer. That is, it is impossible to delete from a
    chain something that exists in any of the readers; it is only possible to override it.
"""
function chain_writer(dafs::AbstractVector{F}; name::Maybe{AbstractString} = nothing)::DafWriter where {F <: DafReader}
    if isempty(dafs)
        error("empty chain$(name_suffix(name))")
    end

    if !(dafs[end] isa DafWriter)
        error("read-only final data: $(dafs[end].name)\n" * "in write chain$(name_suffix(name))")
    end

    if name === nothing
        if length(dafs) == 1
            return dafs[1]
        end
        name = join([daf.name for daf in dafs], ";")
        @assert name !== nothing
    end

    internal_dafs = reader_internal_dafs(dafs, name)
    reader = ReadOnlyChain(Internal(name), internal_dafs)
    return WriteChain(reader.internal, reader.dafs, dafs[end])
end

function reader_internal_dafs(dafs::AbstractVector{F}, name::AbstractString)::Vector{DafReader} where {F}
    axes_entries = Dict{AbstractString, Tuple{AbstractString, AbstractStringVector}}()
    internal_dafs = Vector{DafReader}()
    for daf in dafs
        if daf isa DafReadOnlyWrapper
            daf = daf.daf
        end
        push!(internal_dafs, daf)
        for axis in axis_names(daf)
            new_axis_entries = get_axis(daf, axis)
            old_axis_entries = get(axes_entries, axis, nothing)
            if old_axis_entries === nothing
                axes_entries[axis] = (daf.name, new_axis_entries)
            elseif new_axis_entries != old_axis_entries
                error(
                    "different entries for the axis: $(axis)\n" *
                    "in the daf data: $(old_axis_entries[1])\n" *
                    "and the daf data: $(daf.name)\n" *
                    "in the chain: $(name)",
                )
            end
        end
    end
    return internal_dafs
end

function name_suffix(name::Maybe{AbstractString})::String
    if name === nothing
        return ""
    else
        return ": $(name)"
    end
end

function Formats.with_write_lock(action::Function, chain::WriteChain)::Any
    return Formats.with_write_lock(action, chain.daf)
end

AnyChain = Union{ReadOnlyChain, WriteChain}

function Formats.format_has_scalar(chain::AnyChain, name::AbstractString)::Bool
    for daf in chain.dafs
        has_scalar = Formats.with_read_lock(daf) do
            return Formats.format_has_scalar(daf, name)
        end
        if has_scalar
            return true
        end
    end
    return false
end

function Formats.format_set_scalar!(chain::WriteChain, name::AbstractString, value::StorageScalar)::Nothing
    set_scalar!(chain.daf, name, value)
    return nothing
end

function Formats.format_delete_scalar!(chain::WriteChain, name::AbstractString; for_set::Bool)::Nothing
    if !for_set
        for daf in chain.dafs[1:(end - 1)]
            Formats.with_read_lock(daf) do
                if Formats.format_has_scalar(daf, name)
                    error(
                        "failed to delete the scalar: $(name)\n" *
                        "from the daf data: $(chain.daf.name)\n" *
                        "of the chain: $(chain.name)\n" *  # NOLINT
                        "because it exists in the earlier: $(daf.name)",
                    )
                end
            end
        end
    end
    delete_scalar!(chain.daf, name; must_exist = false, _for_set = for_set)
    return nothing
end

function Formats.format_get_scalar(chain::AnyChain, name::AbstractString)::StorageScalar
    for daf in reverse(chain.dafs)
        value = Formats.with_read_lock(daf) do
            if Formats.format_has_scalar(daf, name)
                return Formats.get_scalar_through_cache(daf, name)
            else
                return nothing
            end
        end
        if value !== nothing
            return value
        end
    end
    @assert false
end

function Formats.format_scalar_names(chain::AnyChain)::AbstractStringSet
    return reduce(
        union,
        [
            Formats.with_read_lock(daf) do
                return Formats.get_through_cache(daf, Formats.scalar_names_cache_key(), AbstractStringSet) do
                    return Formats.format_scalar_names(daf)
                end
            end for daf in chain.dafs
        ],
    )
end

function Formats.format_has_axis(chain::AnyChain, axis::AbstractString; for_change::Bool)::Bool
    for daf in chain.dafs
        has_axis = Formats.with_read_lock(daf) do
            return Formats.format_has_axis(daf, axis; for_change = for_change)
        end
        if has_axis
            return true
        end
        for_change = false
    end
    return false
end

function Formats.format_add_axis!(chain::WriteChain, axis::AbstractString, entries::AbstractStringVector)::Nothing
    add_axis!(chain.daf, axis, entries)
    return nothing
end

function Formats.format_delete_axis!(chain::WriteChain, axis::AbstractString)::Nothing
    for daf in chain.dafs[1:(end - 1)]
        Formats.with_read_lock(daf) do
            if Formats.format_has_axis(daf, axis; for_change = false)
                error(
                    "failed to delete the axis: $(axis)\n" *
                    "from the daf data: $(chain.daf.name)\n" *
                    "of the chain: $(chain.name)\n" *  # NOLINT
                    "because it exists in the earlier: $(daf.name)",
                )
            end
        end
    end
    delete_axis!(chain.daf, axis)
    return nothing
end

function Formats.format_axis_names(chain::AnyChain)::AbstractStringSet
    return reduce(union, [
        Formats.with_read_lock(daf) do
            return Formats.get_axis_names_through_cache(daf)
        end for daf in chain.dafs
    ])
end

function Formats.format_get_axis(chain::AnyChain, axis::AbstractString)::AbstractStringVector
    for daf in reverse(chain.dafs)
        axis_entries = Formats.with_read_lock(daf) do
            if Formats.format_has_axis(daf, axis; for_change = false)
                return Formats.get_axis_through_cache(daf, axis)
            else
                return nothing
            end
        end
        if axis_entries !== nothing
            return axis_entries
        end
    end
    @assert false
end

function Formats.format_axis_length(chain::AnyChain, axis::AbstractString)::Int64
    for daf in chain.dafs
        axis_length = Formats.with_read_lock(daf) do
            if Formats.format_has_axis(daf, axis; for_change = false)
                return Formats.format_axis_length(daf, axis)
            else
                return nothing
            end
        end
        if axis_length !== nothing
            return axis_length
        end
    end
    @assert false
end

function Formats.format_has_vector(chain::AnyChain, axis::AbstractString, name::AbstractString)::Bool
    for daf in chain.dafs
        has_vector = Formats.with_read_lock(daf) do
            return Formats.format_has_axis(daf, axis; for_change = false) && Formats.format_has_vector(daf, axis, name)
        end
        if has_vector
            return true
        end
    end
    return false
end

function Formats.format_set_vector!(
    chain::WriteChain,
    axis::AbstractString,
    name::AbstractString,
    vector::Union{StorageScalar, StorageVector},
)::Nothing
    if !Formats.format_has_axis(chain.daf, axis; for_change = false)
        add_axis!(chain.daf, axis, Formats.get_axis_through_cache(chain, axis))
    end
    set_vector!(chain.daf, axis, name, vector)
    return nothing
end

function Formats.format_get_empty_dense_vector!(
    chain::WriteChain,
    axis::AbstractString,
    name::AbstractString,
    eltype::Type{T},
)::AbstractVector{T} where {T <: StorageNumber}
    if !Formats.format_has_axis(chain.daf, axis; for_change = false)
        add_axis!(chain.daf, axis, Formats.get_axis_through_cache(chain, axis))
    end
    return get_empty_dense_vector!(chain.daf, axis, name, eltype; overwrite = true)
end

function Formats.format_get_empty_sparse_vector!(
    chain::WriteChain,
    axis::AbstractString,
    name::AbstractString,
    eltype::Type{T},
    nnz::StorageInteger,
    indtype::Type{I},
)::Tuple{AbstractVector{I}, AbstractVector{T}, Any} where {T <: StorageNumber, I <: StorageInteger}
    if !Formats.format_has_axis(chain.daf, axis; for_change = false)
        add_axis!(chain.daf, axis, Formats.get_axis_through_cache(chain, axis))
    end
    return get_empty_sparse_vector!(chain.daf, axis, name, eltype, nnz, indtype)
end

function Formats.format_filled_empty_sparse_vector!(
    chain::WriteChain,
    axis::AbstractString,
    name::AbstractString,
    extra::Any,
    filled::SparseVector{T, I},
)::Nothing where {T <: StorageNumber, I <: StorageInteger}
    Formats.format_filled_empty_sparse_vector!(chain.daf, axis, name, extra, filled)
    return nothing
end

function Formats.format_delete_vector!(
    chain::WriteChain,
    axis::AbstractString,
    name::AbstractString;
    for_set::Bool,
)::Nothing
    if !for_set
        for daf in chain.dafs[1:(end - 1)]
            Formats.with_read_lock(daf) do
                if Formats.format_has_axis(daf, axis; for_change = false) && Formats.format_has_vector(daf, axis, name)
                    error(
                        "failed to delete the vector: $(name)\n" *
                        "of the axis: $(axis)\n" *
                        "from the daf data: $(chain.daf.name)\n" *
                        "of the chain: $(chain.name)\n" *  # NOLINT
                        "because it exists in the earlier: $(daf.name)",
                    )
                end
            end
        end
    end
    if Formats.format_has_axis(chain.daf, axis; for_change = false) && Formats.format_has_vector(chain.daf, axis, name)
        delete_vector!(chain.daf, axis, name; _for_set = for_set)
    end
    return nothing
end

function Formats.format_vector_names(chain::AnyChain, axis::AbstractString)::AbstractStringSet
    return reduce(
        union,
        [
            Formats.with_read_lock(daf) do
                return Formats.format_vector_names(daf, axis)
            end for daf in chain.dafs if Formats.format_has_axis(daf, axis; for_change = false)
        ],
    )
end

function Formats.format_get_vector(chain::AnyChain, axis::AbstractString, name::AbstractString)::StorageVector
    for daf in reverse(chain.dafs)
        vector = Formats.with_read_lock(daf) do
            if Formats.format_has_axis(daf, axis; for_change = false) && Formats.format_has_vector(daf, axis, name)
                return as_read_only_array(Formats.get_vector_through_cache(daf, axis, name))
            else
                return nothing
            end
        end
        if vector !== nothing
            return vector
        end
    end
    @assert false
end

function Formats.format_has_matrix(
    chain::AnyChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
    name::AbstractString;
    for_relayout::Bool = false,
)::Bool
    for daf in reverse(chain.dafs)
        has_matrix = Formats.with_read_lock(daf) do
            if Formats.format_has_axis(daf, rows_axis; for_change = false) &&
               Formats.format_has_axis(daf, columns_axis; for_change = false) &&
               Formats.format_has_matrix(daf, rows_axis, columns_axis, name; for_relayout = for_relayout)
                return true
            elseif for_relayout
                return false  # untested
            else
                return nothing
            end
        end
        if has_matrix !== nothing
            return has_matrix
        end
    end
    return false
end

function Formats.format_set_matrix!(
    chain::WriteChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
    name::AbstractString,
    matrix::Union{StorageNumber, StorageMatrix},
)::Nothing
    for axis in (rows_axis, columns_axis)
        if !Formats.format_has_axis(chain.daf, axis; for_change = false)
            add_axis!(chain.daf, axis, Formats.get_axis_through_cache(chain, axis))
        end
    end
    set_matrix!(chain.daf, rows_axis, columns_axis, name, matrix; relayout = false)
    return nothing
end

function Formats.format_get_empty_dense_matrix!(
    chain::WriteChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
    name::AbstractString,
    eltype::Type{T},
)::AbstractMatrix{T} where {T <: StorageNumber}
    for axis in (rows_axis, columns_axis)
        if !Formats.format_has_axis(chain.daf, axis; for_change = false)
            add_axis!(chain.daf, axis, Formats.get_axis_through_cache(chain, axis))
        end
    end
    return get_empty_dense_matrix!(chain.daf, rows_axis, columns_axis, name, eltype)
end

function Formats.format_get_empty_sparse_matrix!(
    chain::WriteChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
    name::AbstractString,
    eltype::Type{T},
    nnz::StorageInteger,
    indtype::Type{I},
)::Tuple{AbstractVector{I}, AbstractVector{I}, AbstractVector{T}, Any} where {T <: StorageNumber, I <: StorageInteger}
    for axis in (rows_axis, columns_axis)
        if !Formats.format_has_axis(chain.daf, axis; for_change = false)
            add_axis!(chain.daf, axis, Formats.get_axis_through_cache(chain, axis))
        end
    end
    return get_empty_sparse_matrix!(chain.daf, rows_axis, columns_axis, name, eltype, nnz, indtype)
end

function Formats.format_filled_empty_sparse_matrix!(
    chain::WriteChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
    name::AbstractString,
    extra::Any,
    filled::SparseMatrixCSC{T, I},
)::Nothing where {T <: StorageNumber, I <: StorageInteger}
    Formats.format_filled_empty_sparse_matrix!(chain.daf, rows_axis, columns_axis, name, extra, filled)
    return nothing
end

function Formats.format_relayout_matrix!(
    chain::WriteChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
    name::AbstractString,
)::Nothing
    relayout_matrix!(chain.daf, rows_axis, columns_axis, name)
    return nothing
end

function Formats.format_delete_matrix!(
    chain::WriteChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
    name::AbstractString;
    for_set::Bool,
)::Nothing
    if !for_set
        for daf in chain.dafs[1:(end - 1)]
            Formats.with_read_lock(daf) do
                if Formats.format_has_axis(daf, rows_axis; for_change = false) &&
                   Formats.format_has_axis(daf, columns_axis; for_change = false) &&
                   Formats.format_has_matrix(daf, rows_axis, columns_axis, name)
                    error(
                        "failed to delete the matrix: $(name)\n" *
                        "for the rows axis: $(rows_axis)\n" *
                        "and the columns axis: $(columns_axis)\n" *
                        "from the daf data: $(chain.daf.name)\n" *
                        "of the chain: $(chain.name)\n" *  # NOLINT
                        "because it exists in the earlier: $(daf.name)",
                    )
                end
            end
        end
    end
    if Formats.format_has_axis(chain.daf, rows_axis; for_change = false) &&
       Formats.format_has_axis(chain.daf, columns_axis; for_change = false) &&
       Formats.format_has_matrix(chain.daf, rows_axis, columns_axis, name)
        delete_matrix!(chain.daf, rows_axis, columns_axis, name; relayout = false, _for_set = for_set)
    end
    return nothing
end

function Formats.format_matrix_names(
    chain::AnyChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
)::AbstractStringSet
    return reduce(
        union,
        [
            Formats.get_matrix_names_through_cache(daf, rows_axis, columns_axis) for
            daf in chain.dafs if Formats.format_has_axis(daf, rows_axis; for_change = false) &&
            Formats.format_has_axis(daf, columns_axis; for_change = false)
        ],
    )
end

function Formats.format_get_matrix(
    chain::AnyChain,
    rows_axis::AbstractString,
    columns_axis::AbstractString,
    name::AbstractString,
)::StorageMatrix
    for daf in reverse(chain.dafs)
        matrix = Formats.with_read_lock(daf) do
            if Formats.format_has_axis(daf, rows_axis; for_change = false) &&
               Formats.format_has_axis(daf, columns_axis; for_change = false) &&
               Formats.format_has_matrix(daf, rows_axis, columns_axis, name)
                return as_read_only_array(Formats.get_matrix_through_cache(daf, rows_axis, columns_axis, name))
            else
                return nothing
            end
        end
        if matrix !== nothing
            return matrix
        end
    end
    @assert false
end

function Formats.format_description_header(::ReadOnlyChain, indent::AbstractString, lines::Vector{String})::Nothing
    push!(lines, "$(indent)type: ReadOnly Chain")
    return nothing
end

function Formats.format_description_header(::WriteChain, indent::AbstractString, lines::Vector{String})::Nothing
    push!(lines, "$(indent)type: Write Chain")
    return nothing
end

function Formats.format_description_footer(
    chain::AnyChain,
    indent::AbstractString,
    lines::Vector{String},
    cache::Bool,
    deep::Bool,
)::Nothing
    if deep
        push!(lines, "$(indent)chain:")
        for daf in chain.dafs
            Formats.with_read_lock(daf) do
                description(daf, indent * "  ", lines, cache, deep)  # NOJET
                return nothing
            end
        end
    end
    return nothing
end

function Formats.format_get_version_counter(chain::AnyChain, version_key::Formats.DataKey)::UInt32
    version_counter = UInt32(0)
    for daf in chain.dafs
        version_counter += Formats.with_read_lock(daf) do
            return Formats.format_get_version_counter(daf, version_key)
        end
    end
    return version_counter
end

function Formats.format_increment_version_counter(chain::WriteChain, version_key::DataKey)::Nothing
    Formats.format_increment_version_counter(chain.daf, version_key)
    return nothing
end

function Messages.depict(value::ReadOnlyChain; name::Maybe{AbstractString} = nothing)::String
    if name === nothing
        name = value.name  # NOLINT
    end
    return "ReadOnly Chain $(name)"
end

function Messages.depict(value::WriteChain; name::Maybe{AbstractString} = nothing)::String
    if name === nothing
        name = value.name  # NOLINT
    end
    return "Write Chain $(name)"
end

function ReadOnly.read_only(daf::ReadOnlyChain; name::Maybe{AbstractString} = nothing)::ReadOnlyChain
    if name === nothing
        return daf
    else
        return ReadOnlyChain(Formats.renamed_internal(daf.internal, name), daf.dafs)
    end
end

end # module
