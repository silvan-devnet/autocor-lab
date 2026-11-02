#!/usr/bin/env bash
# Fetch the YANG models for blueprint 2.7/1.3 (not stored in Git, ~66 MB) and set up pyang.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d models ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/YangModels/yang models
  git -C models sparse-checkout set vendor/cisco/xe/17131 standard/ietf/RFC
fi
[ -x .venv/bin/pyang ] || { uv venv -q .venv && uv pip install -q --python .venv/bin/python pyang pyyaml; }
command -v yanglint >/dev/null || echo "yanglint missing: brew install libyang"
.venv/bin/pyang --version
