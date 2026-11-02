#!/usr/bin/env bash
# Validate a YANG instance document (JSON or YAML) against the IOS XE 17.13.1 models (blueprint 2.7).
#
#   lab/yang/check.sh my-vlans.json            # full config validation (choices, ranges, keys, types)
#   lab/yang/check.sh my-vlans.yaml            # YAML is converted to JSON first
#   lab/yang/check.sh my-vlans.json xml        # additionally print the document as XML (NETCONF view)
#
# Modules are picked from the "module-name:" prefixes found in the file, so the document itself
# decides what gets loaded. Requires: models/ (fetch_models.sh), .venv with pyyaml, yanglint (brew libyang).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
M="$HERE/models/vendor/cisco/xe/17131"
[ $# -ge 1 ] || { sed -n '2,9p' "$0"; exit 1; }
[ -d "$M" ] || { echo "models missing - run $HERE/fetch_models.sh"; exit 1; }
src="$1"; fmt="${2:-}"

# YAML -> JSON (same tree, different syntax)
case "$src" in
  *.yaml|*.yml)
    json="$(mktemp -t yang-check).json"
    "$HERE/.venv/bin/python" -c 'import sys,yaml,json; json.dump(yaml.safe_load(open(sys.argv[1])),open(sys.argv[2],"w"),indent=2)' "$src" "$json"
    ;;
  *) json="$src" ;;
esac

# Every "module-name:" prefix (member names and identityref values) that exists as a model file
mods=()
for m in $(grep -oE '"[A-Za-z][A-Za-z0-9-]*:' "$json" | tr -d '":' | sort -u); do
  [ -f "$M/$m.yang" ] && mods+=("$M/$m.yang")
done
[ ${#mods[@]} -gt 0 ] || { echo "no module prefix found - is the top-level member namespace-qualified?"; exit 1; }

# Extra modules referenced by when/must expressions in the native model
extra=()
grep -q '"Cisco-IOS-XE-vlan:' "$json" && extra+=("$M/Cisco-IOS-XE-vtp.yang")
features=()
grep -q '"ietf-ip:' "$json" && features+=(-F ietf-ip:ipv4-non-contiguous-netmasks)

# -D: never search the current directory - pyang's own IETF modules in .venv would win
out=$(yanglint -D -p "$M" -t config ${features[@]+"${features[@]}"} ${fmt:+-f "$fmt"} \
  "${mods[@]}" ${extra[@]+"${extra[@]}"} "$json" 2>&1 | grep -v 'libyang warn' || true)
if grep -q 'err' <<<"$out"; then
  echo "INVALID: $src"; grep 'err' <<<"$out"; exit 1
fi
echo "VALID: $src"
[ -n "$fmt" ] && echo "$out"
exit 0
