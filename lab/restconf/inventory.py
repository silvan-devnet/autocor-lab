#!/usr/bin/env python3
import os
import sys

import requests
import urllib3

urllib3.disable_warnings() # lab only

DEVICES = ["172.20.20.11", "172.20.20.12"]
AUTH = (os.environ["CEOS_USER"], os.environ["CEOS_PASSWORD"])
HEADERS = {"Accept": "application/yang-data+json"}

def restconf_get(host, path):
    """GET one resource and return the parsed JSON body (raises on HTTP
errors)."""
    url = f"https://{host}:6020/restconf/data/{path}"
    resp = requests.get(url, auth=AUTH, headers=HEADERS, verify=False, timeout=10)
    resp.raise_for_status()
    return resp.json()

def leaf(body, name):
    """Return a leaf value whether or not the device prefixes it with the module name."""
    for key, value in body.items():
        if key == name or key.endswith(":" + name):
            return value
    return None


def main():
    print(f"{'host':15} {'hostname':10} {'model':10} {'serial':34} software")
    for host in DEVICES:
        try:
            system = restconf_get(host, "openconfig-system:system/state")
            chassis = restconf_get(host, "openconfig-platform:components/component=Chassis/state")
        except requests.RequestException as err:
            print(f"{host:15} ERROR {err}", file=sys.stderr)
            continue
        print(f"{host:15} {leaf(system, 'hostname'):10} {leaf(chassis, 'part-no'):10} "
              f"{leaf(chassis, 'serial-no'):34} {leaf(system, 'software-version')}")


if __name__ == "__main__":
    main()
