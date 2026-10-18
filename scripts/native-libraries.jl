using LibCURL,Libdl,OpenSSL_jll
println(Libdl.dlpath(LibCURL.libcurl))
println(Libdl.dlpath(OpenSSL_jll.libcrypto))
