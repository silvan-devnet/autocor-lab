#!/usr/bin/env python3
"""RESTCONF inventory collector: writes /data/inventory.json and /data/index.html every INTERVAL s."""
import json
import os
import time

import requests
import urllib3

urllib3.disable_warnings()  # lab only: self-signed certificate on cEOS

DEVICES = os.environ.get("DEVICES", "172.20.20.11,172.20.20.12").split(",")
AUTH = (os.environ["CEOS_USER"], os.environ["CEOS_PASSWORD"])
INTERVAL = int(os.environ.get("INTERVAL", "30"))
HEADERS = {"Accept": "application/yang-data+json"}


def restconf_get(host, path):
    url = f"https://{host}:6020/restconf/data/{path}"
    resp = requests.get(url, auth=AUTH, headers=HEADERS, verify=False, timeout=10)
    resp.raise_for_status()
    return resp.json()


def leaf(body, name):
    for key, value in body.items():
        if key == name or key.endswith(":" + name):
            return value
    return None


def collect():
    rows = []
    for host in DEVICES:
        try:
            system = restconf_get(host, "openconfig-system:system/state")
            chassis = restconf_get(host, "openconfig-platform:components/component=Chassis/state")
            rows.append({"host": host, "hostname": leaf(system, "hostname"), "model": leaf(chassis, "part-no"),
                         "serial": leaf(chassis, "serial-no"), "software": leaf(system, "software-version")})
        except requests.RequestException as err:
            rows.append({"host": host, "error": str(err)})
    return rows


def write(rows):
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with open("/data/inventory.json", "w") as f:
        json.dump({"updated": stamp, "devices": rows}, f, indent=2)
    cells = "".join(f"<tr><td>{r['host']}</td><td>{r.get('hostname', '')}</td><td>{r.get('serial', r.get('error', ''))}</td>"
                    f"<td>{r.get('software', '')}</td></tr>" for r in rows)
    with open("/data/index.html", "w") as f:
        f.write(f"<h1>Lab-Inventar</h1><p>Stand {stamp}</p><table border=1>"
                f"<tr><th>Host</th><th>Hostname</th><th>Serial</th><th>Software</th></tr>{cells}</table>")


while True:
    rows = collect()
    write(rows)
    print(f"collected {len(rows)} devices, {sum('error' in r for r in rows)} errors", flush=True)
    time.sleep(INTERVAL)
