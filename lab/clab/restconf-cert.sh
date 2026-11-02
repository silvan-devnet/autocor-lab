#!/usr/bin/env bash
# Create the self-signed RESTCONF certificate on every cEOS node of the lab (run on the lab host after
# `containerlab deploy`). EOS exec commands cannot live in a startup config, hence this script.
# Retries until RESTCONF reports "running": right after boot the CLI answers before the PKI is
# ready ("% PKI not ready"). Idempotent: an existing certificate is regenerated.
set -uo pipefail
for c in $(docker ps --filter label=clab-node-kind=arista_ceos --filter label=containerlab=autocor --format '{{.Names}}'); do
  n=${c##*-}
  for _ in $(seq 40); do
    docker exec "$c" Cli -p 15 -c "security pki key generate rsa 2048 restconf.key
security pki certificate generate self-signed restconf.crt key restconf.key validity 3650 parameters common-name $n" >/dev/null 2>&1
    if docker exec "$c" Cli -p 15 -c "show management api restconf" 2>/dev/null | grep -q "Server: running"; then
      echo "$n: RESTCONF running on 6020"; continue 2
    fi
    sleep 5
  done
  echo "$n: RESTCONF NOT running - check 'show management api restconf'"; exit 1
done
