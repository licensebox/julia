#!/usr/bin/env bash
set -euo pipefail
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
mapfile -t libraries < <(julia --startup-file=no --project=. scripts/native-libraries.jl)
cmake -S ../native-src -B ../native-src/build-julia -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DCMAKE_INSTALL_LIBDIR=lib \
  "-Dpkgcfg_lib_PC_CURL_curl=${libraries[0]}" "-DCURL_LIBRARY=${libraries[0]}" "-DCURL_LIBRARY_RELEASE=${libraries[0]}" "-DCURL_LIBRARY_DEBUG=${libraries[0]}" "-DOPENSSL_CRYPTO_LIBRARY=${libraries[1]}"
cmake --build ../native-src/build-julia -j 2
cmake --install ../native-src/build-julia --prefix "$(dirname "$LICENSEBOX_LIB_DIR")"
julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
julia --startup-file=no --project=. test/tls_smoke.jl
python3 ../protocol/conformance/tls_transport.py --adapter bash ci/adapter.sh
