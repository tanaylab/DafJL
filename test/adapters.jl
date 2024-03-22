nested_test("adapters") do
    daf = MemoryDaf(; name = "memory!")
    set_scalar!(daf, "INPUT", 1)
    result = adapter(viewer(daf; data = ["input" => ": INPUT"]); data = ["OUTPUT" => ": output"]) do adapted
        set_scalar!(adapted, "output", get_scalar(adapted, "input"))
        return 7
    end
    @test result == 7
    @test get_scalar(daf, "OUTPUT") == 1
end
