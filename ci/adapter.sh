#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec julia --startup-file=no --project=. test/adapter.jl
