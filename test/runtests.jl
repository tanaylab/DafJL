using Test

using Base: elsize
using Base.MathConstants
using Daf
using ExceptionUnwrapping
using LinearAlgebra
using NamedArrays
using NestedTests
using SparseArrays
using Statistics
using TestContexts

test_prefixes(ARGS)

inefficient_action_policy(ErrorPolicy)

function dedent(string::AbstractString)::String
    lines = split(string, "\n")[1:(end - 1)]
    first_non_space = nothing
    for line in lines
        line_non_space = findfirst(character -> character != ' ', line)
        if first_non_space == nothing || (line_non_space != nothing && line_non_space < first_non_space)
            first_non_space = line_non_space
        end
    end
    if first_non_space == nothing
        return string  # untested
    else
        return join([line[first_non_space:end] for line in lines], "\n")
    end
end

function with_unwrapping_exceptions(action::Function)::Any
    try
        return action()
    catch exception
        while true
            if exception isa CompositeException
                inner_exception = exception.exceptions[1]
            elseif exception isa TaskFailedException
                inner_exception = unwrap_exception_to_root(exception)
            else
                inner_exception = exception
            end
            if inner_exception === exception
                throw(exception)
            end
            exception = inner_exception
        end
    end
end

#function test_similar(left::Any, right::Any)::Nothing
#    @test "$(left)" == "$(right)"
#    return nothing
#end

include("matrix_layouts.jl")
include("messages.jl")
include("data.jl")
include("tokens.jl")
include("queries.jl")
include("registry.jl")
include("views.jl")
include("chains.jl")
include("contracts.jl")
include("computations.jl")
include("copies.jl")
include("adapters.jl")
include("example_data.jl")
