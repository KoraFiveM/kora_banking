#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lua test/client.lua
lua test/contracts.lua
lua test/server.lua
