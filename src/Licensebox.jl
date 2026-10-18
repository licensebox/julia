module Licensebox
using JSON3, Libdl, OpenSSL_jll
export Client, LicenseboxError, require, lease, status, sign_in, logout,
       modules, requests, request_access, access_link, record, derive_binding,
       native_binding, verify_lease

struct LicenseboxError <: Exception
    code::String
    message::String
end
Base.showerror(io::IO,e::LicenseboxError)=print(io,"licensebox: ",e.message)
const library=Ref{Ptr{Cvoid}}(C_NULL)
const library_lock=ReentrantLock()
function sym(name)
    lock(library_lock) do
        if library[]==C_NULL
            # Build with this runtime's curl and the declared OpenSSL_jll,
            # preserving Julia callback/unwinding support in the main namespace.
            library[]=Libdl.dlopen(get(ENV,"LICENSEBOX_LIBRARY","liblicensebox.so"))
        end
        Libdl.dlsym(library[],name)
    end
end
function argument(s::AbstractString)
    occursin('\0',s) && throw(LicenseboxError("invalid_argument","NUL byte in argument"))
    String(s)
end
native_text(p)=p==C_NULL ? "" : unsafe_string(p)
function result_error(code,handle=C_NULL)
    name=native_text(ccall(sym(:lb_result_code),Cstring,(Cint,),code))
    handle==C_NULL && return LicenseboxError(name,name)
    name=="invalid_argument" && return LicenseboxError(name,name)
    saved=native_text(ccall(sym(:lb_error_code),Cstring,(Ptr{Cvoid},),handle))
    message=native_text(ccall(sym(:lb_error_message),Cstring,(Ptr{Cvoid},),handle))
    LicenseboxError(saved=="ok" ? name : saved,isempty(message) ? name : message)
end
function owned_json(p)
    p==C_NULL && throw(LicenseboxError("protocol_error","missing native result"))
    try
        JSON3.read(unsafe_string(p),Any)
    finally
        ccall(sym(:lb_free),Cvoid,(Ptr{Cvoid},),p)
    end
end
mutable struct CallbackState
    on_sign_in::Any
    clock::Any
    machine_binding::Any
    cancelled::Any
    failure::Any
end
struct NativeCallbacks
    context::Ptr{Cvoid}
    on_sign_in::Ptr{Cvoid}
    clock::Ptr{Cvoid}
    machine_binding::Ptr{Cvoid}
    cancelled::Ptr{Cvoid}
end
function signin_callback(p::Ptr{Cvoid},url::Cstring,code::Cstring)::Cvoid
    state=unsafe_pointer_to_objref(p)::CallbackState
    try state.on_sign_in(unsafe_string(url),unsafe_string(code))
    catch err;state.failure=err;end
    nothing
end
function clock_callback(p::Ptr{Cvoid})::Cdouble
    state=unsafe_pointer_to_objref(p)::CallbackState
    try
        value=Float64(state.clock())
        isfinite(value) || error("invalid clock result")
        return value
    catch err;state.failure=err;return 0.0;end
end
function binding_callback(p::Ptr{Cvoid},out::Ptr{UInt8},capacity::Csize_t)::Cint
    state=unsafe_pointer_to_objref(p)::CallbackState
    try
        value=argument(state.machine_binding())
        ncodeunits(value)<capacity || return 1
        GC.@preserve value unsafe_copyto!(out,pointer(value),ncodeunits(value))
        unsafe_store!(out,0x00,ncodeunits(value)+1)
        return 0
    catch err;state.failure=err;return 1;end
end
function cancel_callback(p::Ptr{Cvoid})::Cint
    state=unsafe_pointer_to_objref(p)::CallbackState
    state.failure!==nothing && return 1
    try return state.cancelled===nothing ? 0 : Cint(Bool(state.cancelled()))
    catch err;state.failure=err;return 1;end
end
mutable struct Client
    handle::Ptr{Cvoid}
    state::CallbackState
    mutex::ReentrantLock
    busy::Bool
end
"""Client(product, keys; version, directory, server, on_sign_in, cancelled).
clock and machine_binding are trusted platform/testing seams, never user input.
Keep one client per process. Close it explicitly with close(client).
"""
function Client(product::AbstractString,keys::AbstractDict;version="",directory=nothing,server=nothing,
                on_sign_in=nothing,clock=nothing,machine_binding=nothing,cancelled=nothing)
    options=Dict{String,Any}("product"=>argument(product),"keys"=>keys,"version"=>argument(version))
    directory!==nothing && (options["directory"]=argument(directory))
    server!==nothing && (options["server"]=argument(server))
    state=CallbackState(on_sign_in,clock,machine_binding,cancelled,nothing)
    callbacks=NativeCallbacks(pointer_from_objref(state),
       on_sign_in===nothing ? C_NULL : @cfunction(signin_callback,Cvoid,(Ptr{Cvoid},Cstring,Cstring)),
       clock===nothing ? C_NULL : @cfunction(clock_callback,Cdouble,(Ptr{Cvoid},)),
       machine_binding===nothing ? C_NULL : @cfunction(binding_callback,Cint,(Ptr{Cvoid},Ptr{UInt8},Csize_t)),
       @cfunction(cancel_callback,Cint,(Ptr{Cvoid},)))
    output=Ref{Ptr{Cvoid}}(C_NULL)
    code=GC.@preserve state ccall(sym(:lb_client_create_json),Cint,(Cstring,Ref{NativeCallbacks},Ref{Ptr{Cvoid}}),JSON3.write(options),callbacks,output)
    code==0 || throw(result_error(code))
    client=Client(output[],state,ReentrantLock(),false)
    finalizer(close,client)
    client
end
function Base.close(client::Client)
    lock(client.mutex) do
        client.busy && throw(ArgumentError("callbacks must not reenter the client"))
        if client.handle!=C_NULL
            ccall(sym(:lb_client_destroy),Cvoid,(Ptr{Cvoid},),client.handle)
            client.handle=C_NULL
        end
    end
    nothing
end
function call(client::Client,operation,args=Dict())
    lock(client.mutex) do
        client.handle==C_NULL && throw(ArgumentError("client is closed"))
        client.busy && throw(ArgumentError("callbacks must not reenter the client"))
        client.busy=true
        output=Ref{Ptr{UInt8}}(C_NULL)
        try
            code=GC.@preserve client ccall(sym(:lb_client_call_json),Cint,(Ptr{Cvoid},Cstring,Cstring,Ref{Ptr{UInt8}}),client.handle,operation,JSON3.write(args),output)
            if client.state.failure!==nothing || code!=0
                ccall(sym(:lb_free),Cvoid,(Ptr{Cvoid},),output[])
                if client.state.failure!==nothing
                    err=client.state.failure;client.state.failure=nothing;throw(err)
                end
                throw(result_error(code,client.handle))
            end
            owned_json(output[])
        finally
            client.busy=false
        end
    end
end
lease(c::Client)=call(c,"lease")
require(c::Client,module_name::AbstractString)=call(c,"require",Dict("module"=>argument(module_name)))
status(c::Client)=call(c,"status")
sign_in(c::Client;timeout=0.0)=call(c,"sign_in",Dict("timeout"=>timeout))
logout(c::Client)=call(c,"logout")
modules(c::Client)=call(c,"modules")
requests(c::Client)=call(c,"requests")
request_access(c::Client,names::AbstractVector,note::AbstractString="")=call(c,"request",Dict("modules"=>names,"note"=>argument(note)))
access_link(c::Client)=call(c,"access-link")
record(c::Client,command::AbstractString,success::Bool,elapsed::Real)=call(c,"record",Dict("command"=>argument(command),"success"=>success,"elapsed"=>elapsed))
function derive_binding(product::AbstractString,source::AbstractString,raw::AbstractString)
    p=argument(product);s=argument(source);r=String(rstrip(raw,'\0'))
    occursin('\0',r) && throw(LicenseboxError("identity_unavailable","invalid native identifier"))
    out=zeros(UInt8,128)
    code=ccall(sym(:lb_derive_binding),Cint,(Cstring,Cstring,Cstring,Ptr{UInt8},Csize_t),p,s,r,out,length(out))
    code==0 || throw(result_error(code))
    GC.@preserve out unsafe_string(pointer(out))
end
function native_binding(product::AbstractString)
    out=zeros(UInt8,128)
    code=ccall(sym(:lb_native_binding),Cint,(Cstring,Ptr{UInt8},Csize_t),argument(product),out,length(out))
    code==0 || throw(result_error(code))
    GC.@preserve out unsafe_string(pointer(out))
end
function verify_lease(token::AbstractString,product::AbstractString,keys::AbstractDict,now::Real)
    out=Ref{Ptr{UInt8}}(C_NULL)
    code=ccall(sym(:lb_verify_lease_json),Cint,(Cstring,Cstring,Cstring,Cdouble,Ref{Ptr{UInt8}}),argument(token),argument(product),JSON3.write(keys),now,out)
    if code!=0;ccall(sym(:lb_free),Cvoid,(Ptr{Cvoid},),out[]);throw(result_error(code));end
    owned_json(out[])
end
end
