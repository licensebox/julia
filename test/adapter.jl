using Licensebox, JSON3
function run(r)
    op=r["op"];product=r["product"]
    op=="derive" && return derive_binding(product,r["source"],r["raw_id"])
    op=="native" && return native_binding(product)
    op=="verify" && return verify_lease(r["token"],product,r["keys"],r["now"])
    c=Client(product,r["keys"];server=r["server"],directory=r["directory"],version="conformance",clock=()->r["now"],machine_binding=()->get(r,"binding",""),on_sign_in=(_,_)->nothing,ca_bundle=get(r,"ca_bundle",Licensebox.NetworkOptions.ca_roots_path()))
    try
        op=="lease" && return lease(c)
        op=="require" && return require(c,get(r,"module","core"))
        op=="repeat" && (require(c,"core");return require(c,"core"))
        op=="status" && return status(c)
        op=="sign_in" && return sign_in(c;timeout=3)
        op=="logout" && return logout(c)
        op=="modules" && return modules(c)
        op=="requests" && return requests(c)
        op=="request" && return request_access(c,["export"],"café – test")
        op=="access-link" && return access_link(c)
        op=="record" && (record(c,"export",true,.125);record(c,"export",false,.025);return nothing)
        error("unknown operation")
    finally close(c);end
end
r=JSON3.read(read(stdin,String),Dict{String,Any})
answer=try Dict("ok"=>true,"value"=>run(r))
catch e
    e isa LicenseboxError || rethrow()
    Dict("ok"=>false,"error"=>e.code,"detail"=>e.message)
end
println(JSON3.write(answer))
