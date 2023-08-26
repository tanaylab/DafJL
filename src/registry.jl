"""
Registering element-wise and reduction operations is required, to allow them to be used in a query.

!!! note

    We do not re-export everything from here to the main `Daf` namespace, as it is only of interest for implementers of
    new query operations. Most users of `Daf` just stick with the (fairly comprehensive) list of built-in query
    operations so there's no need to pollute their namespace with these detail.
"""
module Registry

export compute_eltwise
export compute_reduction
export EltwiseOperation
export @query_operation
export ReductionOperation
export register_query_operation

using Daf.StorageTypes

# An operation in the global registry (used for parsing).
struct RegisteredOperation
    type::Type
    source_file::AbstractString
    source_line::Int
end

# Abstract interface for all query operations.
abstract type AbstractOperation end

"""
Abstract type for all element-wise operations.

An element-wise operation may be applied to matrix or vector data. It will preserve the shape of the data, but changes
the values, and possibly the data type of the elements. For example, `Abs` will compute the absolute value of each
element.

To implement a new such operation, the type is expected to be of the form:

    struct MyOperation <: EltwiseOperation
        ... optional parameters ...
    end
    @query_operation MyOperation

    MyOperation(context::QueryContext, parameters_assignments::Dict{String, QueryOperation})::MyOperation

The constructor should use `parse_parameter` for each of the parameters (for example, using `parse_number_assignment`).
In addition you will need to invoke [`@query_operation`](@ref) to register the operation so it can be used in a query,
and implement the functions listed below. See the query operations module for details and examples.
"""
abstract type EltwiseOperation <: AbstractOperation end

"""
    compute_eltwise(operation::EltwiseOperation, input::StorageMatrix)::StorageMatrix
    compute_eltwise(operation::EltwiseOperation, input::StorageVector)::StorageVector
    compute_eltwise(operation::EltwiseOperation, input_value::Number)::Number

Compute an [`EltwiseOperation`](@ref) `operation`.
"""
function compute_eltwise end

"""
Abstract type for all reduction operations.

A reduction operation may be applied to matrix or vector data. It will reduce (eliminate) one dimension of the data, and
possibly the result will have a different data type than the input. When applied to a vector, the operation will return
a scalar. When applied to a matrix, it assumes the matrix is in column-major layout, and will return a vector with one
entry per column, containing the result of reducing the column to a scalar.

To implement a new such operation, the type is expected to be of the form:

    struct MyOperation <: ReductionOperation
        ... optional parameters ...
    end

    MyOperation(context::QueryContext, parameters_assignments::Dict{String, QueryOperation})::MyOperation

The constructor should use `parse_parameter` for each of the parameters (for example, using typically
`parse_number_assignment`). In addition you will need to invoke [`@query_operation`](@ref) to register the operation so
it can be used in a query, and implement the functions listed below. See the query operations module for details and
examples.
"""
abstract type ReductionOperation <: AbstractOperation end

"""
    compute_reduction(operation::ReductionOperation, input::StorageMatrix)::StorageVector
    compute_reduction(operation::ReductionOperation, input::StorageVector)::Number

Compute an [`ReductionOperation`](@ref) `operation`.
"""
function compute_reduction end

# A global registry of all the known element-wise operations.
ELTWISE_REGISTERED_OPERATIONS = Dict{String, RegisteredOperation}()

# A global registry of all the known reduction operations.
REDUCTION_REGISTERED_OPERATIONS = Dict{String, RegisteredOperation}()

"""
    function register_query_operation(
        type::Type{T},
        source_file::AbstractString,
        source_line::Integer,
    )::Nothing where {T <: Union{EltwiseOperation, ReductionOperation}}

Register a specific operation so it would be available inside queries. This is required to be able to parse the
operation. This is idempotent (safe to invoke multiple times).

This isn't usually called directly. Instead, it is typically invoked by using the [`@query_operation`](@ref) macro.
"""
function register_query_operation(
    type::Type{T},
    source_file::AbstractString,
    source_line::Integer,
)::Nothing where {T <: Union{EltwiseOperation, ReductionOperation}}
    if T <: EltwiseOperation
        global ELTWISE_REGISTERED_OPERATIONS
        registered_operations = ELTWISE_REGISTERED_OPERATIONS
        kind = "eltwise"
    elseif T <: ReductionOperation
        global REDUCTION_REGISTERED_OPERATIONS
        registered_operations = REDUCTION_REGISTERED_OPERATIONS
        kind = "reduction"
    else
        @assert false  # untested
    end

    name = String(type.name.name)
    if name in keys(registered_operations)
        previous_registration = registered_operations[name]
        if previous_registration.type != type ||
           previous_registration.source_file != source_file ||
           previous_registration.source_line != source_line
            error(
                "conflicting registrations for the $(kind) operation: $(name)\n" *
                "1st in: $(previous_registration.source_file):$(previous_registration.source_line)\n" *
                "2nd in: $(source_file):$(source_line)",
            )
        end
    end

    registered_operations[name] = RegisteredOperation(type, source_file, source_line)
    return nothing
end

"""
    struct MyOperation <: EltwiseOperation  # Or <: ReductionOperation
        ...
    end
    @query_operation MyOperation

Automatically call [`register_query_operation`](@ref) for `MyOperation`.

Note this will import `Daf.Registry.register_query_operation`, so it may only be called from the top level scope of a
module.
"""
macro query_operation(operation_type_name)
    name_string = String(operation_type_name)
    name_reference = esc(operation_type_name)

    source_line = __source__.line
    file = __source__.file
    source_file = file == nothing ? "-" : String(file)

    module_name = Symbol("Daf_$(name_string)_$(source_line)")

    return quote
        import Daf.Registry.register_query_operation
        register_query_operation($name_reference, $source_file, $source_line)
    end
end

end
