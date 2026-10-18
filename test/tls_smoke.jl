# Check HTTPS using the core's Julia-compatible curl dependency. No licensing API,
# account data, activation or credentials are involved in this public GET.
using Licensebox, Test
function discard(_::Ptr{Cvoid},size::Csize_t,count::Csize_t,context::Ptr{Cvoid})::Csize_t
    size*count
end
handle=ccall(Licensebox.sym(:curl_easy_init),Ptr{Cvoid},())
@test handle!=C_NULL
try
    @test ccall(Licensebox.sym(:curl_easy_setopt),Cint,(Ptr{Cvoid},Cint,Cstring),handle,10002,"https://licensebox.dev/llms.txt")==0
    @test ccall(Licensebox.sym(:curl_easy_setopt),Cint,(Ptr{Cvoid},Cint,Clong),handle,13,30)==0
    @test ccall(Licensebox.sym(:curl_easy_setopt),Cint,(Ptr{Cvoid},Cint,Clong),handle,64,1)==0
    @test ccall(Licensebox.sym(:curl_easy_setopt),Cint,(Ptr{Cvoid},Cint,Clong),handle,81,2)==0
    callback=@cfunction(discard,Csize_t,(Ptr{Cvoid},Csize_t,Csize_t,Ptr{Cvoid}))
    @test ccall(Licensebox.sym(:curl_easy_setopt),Cint,(Ptr{Cvoid},Cint,Ptr{Cvoid}),handle,20011,callback)==0
    @test ccall(Licensebox.sym(:curl_easy_perform),Cint,(Ptr{Cvoid},),handle)==0
finally
    ccall(Licensebox.sym(:curl_easy_cleanup),Cvoid,(Ptr{Cvoid},),handle)
end
println("PASS: verified HTTPS using the Julia-compatible native dependency")
