# Licensebox for Julia

Application licensing backed by the shared C core: native machine identity,
email sign-in, signed offline leases, silent renewal, module access, approval
requests and usage reporting. Linux is the initial runtime target.

Requirements: Julia 1.12+ and JSON3 1.14; Licensebox C >=0.2.0, OpenSSL 3, libcurl 7.85+ and
json-c. The native dependency is pinned in `native-version.txt` and updated by
the tested contract-sync workflow. No native code is downloaded at runtime.

## Install the native dependency

Clone this repository/tag. Install native development packages, then run:

```sh
sudo apt install build-essential cmake git libssl-dev libcurl4-openssl-dev libjson-c-dev
bash scripts/install-native.sh "$PWD/.native"
export LICENSEBOX_LIB_DIR="$PWD/.native/lib"
export LICENSEBOX_LIBRARY="$PWD/.native/lib/liblicensebox.so"
export LD_LIBRARY_PATH="$PWD/.native/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

Use that absolute native library directory when running the consuming app.
It may instead be installed in the system loader's normal search path.
The helper builds the pinned public C release without changing system folders.

## Authorize protected work

```julia
using Licensebox
client = Client("myapp", Dict("myapp-k1" => "YOUR_PUBLIC_VERIFICATION_KEY"); version="1.0")
try
    require(client, "export")
    # Protected work starts here.
finally
    close(client)
end
```

Install with `Pkg.add(url="https://github.com/licensebox/julia", rev="v0.2.0")`.
Registry registration is separate. Catch `LicenseboxError` and inspect `.code`.
Results are owned JSON values. Explicit `close` is recommended; a finalizer also
releases abandoned handles. Calls/close use a lock. The package preserves Julia
objects across native calls and converts callback failures back to exceptions.


Create one client per process. The complete API includes lease, require, local
status, explicit sign-in, logout, module discovery, access requests/listing,
private access links, and fixed command usage records. Rust/Julia use snake_case;
Java uses lowerCamelCase; .NET uses PascalCase. See source API signatures and the
conformance adapter for examples of every operation. Get product/module IDs and
**public verification keys** from the administrator. Never embed admin tokens,
private signing keys or copied installation keys.

Sign-in defaults to instructions on stderr; a callback can present them in your
UI. Cancellation is supported. Callback failures stop the operation and never
unwind into native code. Callbacks must not reenter the client. Clock/native
binding providers are trusted platform/testing seams, never end-user identity
overrides. Config strings and keys are copied by the native client.

## Errors and lifecycle

`machine_changed`, `seat_transferred`, `location_denied` and `location_unknown`
refuse protected work and persist across restart/offline use. Explicit sign-in
can transfer a seat; ordinary renewal cannot take one back. `module_denied`
means missing module access; `offline` means an expired lease could not renew;
`revoked` removes cached access. Always stop protected work on an error.

Each process silently renews on first protected use, bounded to three seconds.
A verified, unexpired cached lease permits offline use during transport/server
outages. Default allowance is 24 hours; there is no background heartbeat. Logout
retains installation identity. Native IDs stay local; only a product-scoped
digest is sent. Cloned/spoofed IDs and modified host software remain limitations:
this is not hardware attestation. Payments and billing are handled separately
by product administrators.

Build the native core with `scripts/install-native.sh` for the active Julia
runtime: it links against Julia's curl and the declared OpenSSL_jll. A generic
system-linked core may conflict with Julia's bundled libraries. Rebuild after
changing Julia runtimes. Callback exceptions and allocation ownership use the
normal Julia/native boundary. Other operating systems and browser/WASM are not
supported by this profile yet. Test/validation status is recorded in GitHub Actions; do not infer
platform support merely because a language runtime exists there.

See [shared protocol and tests](https://github.com/licensebox/protocol),
[the full roadmap](https://github.com/licensebox/protocol/blob/main/ROADMAP.md)
and [integration docs](https://licensebox.dev/docs). Administration remains in
the [Go CLI](https://github.com/licensebox/go) and web console.

MIT. Copyright © 2026 [Vijai Kumar](https://meshing.engineer).

The default trust bundle comes from Julia’s `NetworkOptions.ca_roots_path()`.
An explicit `ca_bundle` may select another PEM trust bundle; peer and hostname
verification remain mandatory.

Julia 1.12 or newer is required. Earlier runtimes bundle a different TLS backend
and are not supported by this native dependency profile.

## Optional explicit heartbeat

Use `heartbeat(client, "core")` for an explicit bounded renewal/checkpoint. The mandatory module must be nonempty. The result contains `lease` (the complete verified lease, preserving optional signed `heartbeat.interval_seconds`/`grace_seconds`) and `online` (whether this check renewed successfully online). Every invocation attempts renewal, including after a cached `Require`; it never starts interactive activation or transfers a seat. Eligible outages may return `online=false` only while the last verified signed lease remains unexpired. Refusals, missing modules and expired offline access remain errors.

Default Client/Lease/Require behavior is unchanged. No timer, task, thread or background heartbeat starts automatically. The application owns event-loop scheduling/checkpoints on the language runtime thread, and safe cancellation of protected work on refusal or the last verified expiry deadline. A failed check cannot extend that deadline. This is especially important for MATLAB, Wolfram/JLink and other runtimes whose callbacks must stay on their owning thread. The matching native C heartbeat API/contract is required.

Validate the feature against the candidate native core with `python3 ../protocol/conformance/heartbeat.py --adapter bash ci/adapter.sh` in addition to the existing full shared suite.
