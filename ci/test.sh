#!/usr/bin/env bash
set -euo pipefail
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
