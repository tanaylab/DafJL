using Daf

function test_storage_scalar(storage::AbstractStorage)::Nothing
    @test !has_scalar(storage, "version")
    @test length(scalar_names(storage)) == 0

    @test_throws "missing scalar: version in the storage: memory" get_scalar(storage, "version")
    @test get_scalar(storage, "version"; default = (3, 4)) == (3, 4)

    @test_throws "missing scalar: version in the storage: memory" delete_scalar!(storage, "version")
    delete_scalar!(storage, "version"; must_exist = false)

    set_scalar!(storage, "version", (1, 2))
    @test_throws "existing scalar: version in the storage: memory" set_scalar!(storage, "version", (4, 5))

    @test length(scalar_names(storage)) == 1
    @test "version" in scalar_names(storage)

    @test get_scalar(storage, "version") == (1, 2)
    @test get_scalar(storage, "version"; default = (3, 4)) == (1, 2)

    delete_scalar!(storage, "version")
    @test !has_scalar(storage, "version")
    @test length(scalar_names(storage)) == 0

    return nothing
end

function test_storage_axis(storage::AbstractStorage)::Nothing
    @test !has_axis(storage, "cell")
    @test_throws "missing axis: cell in the storage: memory" get_axis(storage, "cell")
    delete_axis!(storage, "cell"; must_exist = false)
    @test length(axis_names(storage)) == 0

    repeated_cell_names = vec(["cell1", "cell1", "cell3"])
    @test_throws "non-unique entries for new axis: cell in the storage: memory" add_axis!(
        storage,  # only seems untested
        "cell",  # only seems untested
        repeated_cell_names,  # only seems untested
    )

    cell_names = vec(["cell1", "cell2", "cell3"])
    add_axis!(storage, "cell", cell_names)
    @test length(axis_names(storage)) == 1
    @test "cell" in axis_names(storage)

    @test has_axis(storage, "cell")
    @test axis_length(storage, "cell") == 3
    @test get_axis(storage, "cell") === cell_names

    @test_throws "existing axis: cell in the storage: memory" add_axis!(storage, "cell", cell_names)

    delete_axis!(storage, "cell")
    @test !has_axis(storage, "cell")
    @test_throws "missing axis: cell in the storage: memory" delete_axis!(storage, "cell")
    @test length(axis_names(storage)) == 0

    return nothing
end

function test_storage_vector(storage::AbstractStorage)::Nothing
    @test_throws "missing axis: cell in the storage: memory" has_vector(storage, "cell", "age")
    @test_throws "missing axis: cell in the storage: memory" vector_names(storage, "cell")
    @test_throws "missing axis: cell in the storage: memory" delete_vector!(storage, "cell", "age")
    @test_throws "missing axis: cell in the storage: memory" get_vector(storage, "cell", "age")
    @test_throws "missing axis: cell in the storage: memory" set_vector!(storage, "cell", "age", vec([0 1 2]))

    add_axis!(storage, "cell", vec(["cell0", "cell1", "cell3"]))
    @test !has_vector(storage, "cell", "age")
    @test length(vector_names(storage, "cell")) == 0
    @test_throws "missing vector: age for the axis: cell in the storage: memory" delete_vector!(storage, "cell", "age")
    delete_vector!(storage, "cell", "age"; must_exist = false)
    @test_throws "missing vector: age for the axis: cell in the storage: memory" get_vector(storage, "cell", "age")
    @test_throws "value length: 2 is different from axis: cell length: 3 in the storage: storage_name" set_vector!(
        storage,  # only seems untested
        "cell",  # only seems untested
        "age",  # only seems untested
        vec([0 1]),  # only seems untested
    )
    @test_throws "" get_vector(storage, "cell", "age"; default = vec([1 2]))
    @test get_vector(storage, "cell", "age"; default = vec([1 2 3])) == vec([1 2 3])
    @test get_vector(storage, "cell", "age"; default = 1) == vec([1 1 1])

    set_vector!(storage, "cell", "age", vec([0 1 2]))
    @test_throws "existing vector: age for the axis: cell in the storage: memory" set_vector!(
        storage,  # only seems untested
        "cell",  # only seems untested
        "age",  # only seems untested
        vec([1 2 3]),  # only seems untested
    )
    @test length(vector_names(storage, "cell")) == 1
    @test "age" in vector_names(storage, "cell")
    @test get_vector(storage, "cell", "age") == vec([0 1 2])

    delete_vector!(storage, "cell", "age")
    @test !has_vector(storage, "cell", "age")

    set_vector!(storage, "cell", "age", vec([0 1 2]))
    @test has_vector(storage, "cell", "age")
    delete_axis!(storage, "cell")
    add_axis!(storage, "cell", vec(["cell0", "cell1"]))
    @test !has_vector(storage, "cell", "age")

    return nothing
end

struct BadStorage <: AbstractStorage
    BadStorage() = new()
end

struct LyingStorage <: AbstractStorage
    lie::Bool
end

function Storage.has_scalar(storage::LyingStorage, name::String)::Bool
    return storage.lie
end

function Storage.has_axis(storage::LyingStorage, axis::String)::Bool
    return storage.lie
end

function Storage.vector_names(storage::LyingStorage, axis::String)::AbstractSet{String}
    return Set{String}()
end

@testset "storage" begin
    @testset "bad_storage" begin
        bad_storage = BadStorage()

        @test_throws "missing method: storage_name for storage type: BadStorage" storage_name(bad_storage)
        @test_throws "missing method: has_scalar for storage type: BadStorage" has_scalar(bad_storage, "version")
        @test_throws "missing method: scalar_names for storage type: BadStorage" scalar_names(bad_storage)
        @test_throws "missing method: has_axis for storage type: BadStorage" has_axis(bad_storage, "cell")
        @test_throws "missing method: axis_names for storage type: BadStorage" axis_names(bad_storage)

        bad_storage = LyingStorage(true)

        @test_throws "missing method: unsafe_delete_scalar! for storage type: LyingStorage" delete_scalar!(
            bad_storage,
            "version",
        )
        @test_throws "missing method: unsafe_get_scalar for storage type: LyingStorage" get_scalar(
            bad_storage,
            "version",
        )
        @test_throws "missing method: unsafe_delete_axis! for storage type: LyingStorage" delete_axis!(
            bad_storage,
            "cell",
        )
        @test_throws "missing method: unsafe_get_axis for storage type: LyingStorage" get_axis(bad_storage, "cell")
        @test_throws "missing method: unsafe_axis_length for storage type: LyingStorage" axis_length(
            bad_storage,
            "cell",
        )
        @test_throws "missing method: unsafe_has_vector for storage type: LyingStorage" has_vector(
            bad_storage,
            "cell",
            "age",
        )
        @test_throws "missing method: unsafe_has_vector for storage type: LyingStorage" get_vector(
            bad_storage,
            "cell",
            "age",
        )

        bad_storage = LyingStorage(false)

        delete_scalar!(bad_storage, "version"; must_exist = false)
        @test get_scalar(bad_storage, "version"; default = (1, 2)) == (1, 2)
        @test_throws "missing method: unsafe_set_scalar! for storage type: LyingStorage" set_scalar!(
            bad_storage,
            "version",
            (1, 2),
        )
        @test_throws "missing method: unsafe_add_axis! for storage type: LyingStorage" add_axis!(
            bad_storage,
            "cell",
            vec(["cell0"]),
        )
    end

    @testset "memory" begin
        storage = MemoryStorage("memory")
        @test storage_name(storage) == "memory"
        test_storage_scalar(storage)
        test_storage_axis(storage)
        test_storage_vector(storage)
    end
end
