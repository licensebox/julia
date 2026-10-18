using Licensebox,Test
@testset "FFI ownership and fail-closed arguments" begin
    @test_throws LicenseboxError Client("bad\0product",Dict())
    @test_throws LicenseboxError derive_binding("demo","linux-machine-id","hostname")
    @test_throws LicenseboxError derive_binding("demo","linux-machine-id","0123456789abcdef\0garbage")
    c=Client("demo",Dict("test"=>"A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg");server="http://127.0.0.1:1",machine_binding=()->error("synthetic callback failure"))
    try
        GC.gc()
        @test_throws ErrorException require(c,"core")
    finally close(c);end
    @test_throws ArgumentError status(c)
    close(c) # idempotent disposal
end

@testset "Explicit heartbeat ownership and no activation" begin
    mktempdir() do directory
        c=Client("demo",Dict("test-key"=>"A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg");directory=directory,server="http://127.0.0.1:1")
        try
            try heartbeat(c,"core"); @test false
            catch error; @test error isa LicenseboxError && error.code=="not_signed_in"; end
        finally close(c);end
        @test_throws ArgumentError heartbeat(c,"core")
    end
end
