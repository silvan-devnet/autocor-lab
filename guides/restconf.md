---
title: "RESTCONF gegen Arista cEOS in ContainerLab"
description: "AUTOCOR 1.3: RESTCONF nach RFC 8040 Schritt für Schritt"
---

> [!info] Geführtes Mitmachen
> Jeder Schritt: **abtippen → ausführen → mit „Erwartet“ vergleichen**. Am Ende jedes Teils kommt ein kurzer **Selbsttest** ohne Vorlage, die Lösung ist zugeklappt. Alle Schritte, auch die Zwischenetappen der Python-Skripte, wurden am 26.10. und 29.10.2026 gegen das Lab geprüft. Ausgangszustand nach dem Deploy: nur VLAN 1, Ethernet1 geroutet ohne IP, keine ACL.
>

> [!warning] cEOS ist nicht IOS XE
> Die Prüfung denkt in **IOS XE** (`Cisco-IOS-XE-native`, RFC-konform). cEOS spricht **OpenConfig** und weicht an einigen Stellen von RFC 8040 ab (Abschnitt 2). Hier lernst du Methoden, URLs und Fehlerbilder am echten Gerät. Die IOS-XE-Form übst du in Teil I auf dem Papier.

## 1. RESTCONF in 5 Minuten (RFC 8040)

RESTCONF ist HTTP auf YANG-Datenbäumen: dieselben Modelle wie NETCONF, aber mit REST-Methoden und JSON oder XML.

### Ressourcen

| URL | Inhalt |
|---|---|
| `/.well-known/host-meta` | Discovery: sagt dem Client, unter welchem Pfad RESTCONF liegt |
| `/restconf` | Root mit `data`, `operations`, `yang-library-version` |
| **`/restconf/data`** | der **Datastore** (Konfiguration + Zustand), hier passiert fast alles |
| `/restconf/operations` | RPCs und Actions (z. B. `save-config`), Aufruf per POST |
| `/restconf/data/ietf-yang-library:modules-state` | welche Module und Revisionen das Gerät kann |

### URL-Aufbau (dieselbe Präfixregel wie in Übung 2.7)

```
https://<host>[:port]/restconf/data/<modul>:<top>/<kind>/<liste>=<key1>,<key2>/<augment-modul>:<knoten>
```

- Präfix `modul:` am ersten Knoten und bei jedem Namespace-Wechsel (augment).
- Ein Listeneintrag wird über `=` adressiert, mehrere Schlüssel trennt ein **Komma** in der Reihenfolge des `key`-Statements.
- Sonderzeichen werden **prozentkodiert**: `/` → `%2F`, `,` → `%2C`, `:` → `%3A`. Aus `GigabitEthernet0/0/1` wird `interface=GigabitEthernet0%2F0%2F1`.

### Methoden ↔ NETCONF ↔ Statuscodes

| Methode | Wirkung | NETCONF | Erfolg (RFC) | typische Fehler |
|---|---|---|---|---|
| **GET** | lesen | `<get>` / `<get-config>` | 200 | 404, 401 |
| **POST** | **anlegen** eines Kindes. Existiert es schon → Fehler | `operation="create"` | **201** | **409 Conflict** |
| **PUT** | **ersetzen** oder anlegen: Das Ziel ist danach **genau** der Körper | `operation="replace"` | 201 / 204 | 400 |
| **PATCH** | **zusammenführen** (merge): nur Genanntes ändert sich | `operation="merge"` | 204 (oder 200) | 400, 404 |
| **DELETE** | löschen | `operation="delete"` | 204 | 404 |

Header: `Accept: application/yang-data+json` und bei Körpern zusätzlich `Content-Type: application/yang-data+json`. Für XML gilt `application/yang-data+xml`.

**Körper nach RFC 8040:** Bei PUT und PATCH steht der **Zielknoten selbst**, also der letzte Knoten der URL, an oberster Stelle. Beispiel: `PUT …/vlan-list=10` → `{"Cisco-IOS-XE-vlan:vlan-list": [{"id": 10, "name": "CLIENTS"}]}`.

### Query-Parameter

`depth=…` (Tiefe), `content=config|nonconfig|all`, `fields=a/b;c`, `with-defaults=report-all`, `insert=first|last|before|after` + `point=` (für `ordered-by user`-Listen).

## 2. Das Lab und die Abweichungen von cEOS

| | |
|---|---|
| Geräte | **ceos1** 172.20.20.11 · **ceos2** 172.20.20.12 (Arista cEOS 4.32.0F) · srl1 172.20.20.21 (hier nicht gebraucht) |
| RESTCONF | `https://<ip>:6020/restconf/data/…`, selbstsigniertes Zertifikat |
| Login | `$CEOS_USER` / `$CEOS_PASSWORD` aus `.env` (Lab-Standard von containerlab) |
| Verkabelung | ceos1 Et1 ↔ ceos2 Et1 (**geroutet**) · ceos1 Et2 ↔ srl1 (Switchport) |
| Modelle | OpenConfig: `openconfig-interfaces`, `-network-instance` (VLANs, Routing), `-acl`, `-platform`, `-system`, `-lldp` |

**Am Gerät geprüfte Abweichungen von RFC 8040:**

| RFC 8040 / IOS XE | cEOS 4.32 | Folge |
|---|---|---|
| PUT/PATCH-Körper = **Zielknoten** | Körper = **Kinder** des Ziels | RFC-Form gibt `400 … unexpected element` |
| Erfolg 201 / 204 | immer **200** | In Skripten `resp.ok` prüfen |
| POST auf Existierendes → **409** | **200** (wirkt wie Merge) | kein Konflikt-Test möglich |
| `/restconf`, `ietf-yang-library` | **404** | Modelle mit `pyang` lesen |
| `depth`, `content`, `fields` | **ignoriert** | nur Theorie |
| Präfix nur bei Namespace-Wechsel (RFC 7951) | **jedes** Leaf mit Präfix | Code muss beide Formen lesen |
| identityref-Schlüssel in der URL mit Präfix | Agent trennt am `:` | Schlüssel ohne Präfix (`acl-set=MGMT-IN,ACL_IPV4`) oder über die Liste im Körper |
| — | **OSPF wird mit `200` quittiert, aber nicht angelegt.** MTU gibt ehrlich `500` (`l2 mtu` gibt es auf cEOS nicht) | Teil G: `200` heißt nicht „angewendet“ |

## 3. Vorbereitung

Starte das Lab wie in der [Lab-Einrichtung](lab-setup.md) beschrieben. Dort sind auch die zwei Terminal-Tabs und die `.env` erklärt.

Im **Lab-Tab** einmal pro Sitzung, im Hauptordner des Repos:

```bash
set -a; . ./.env; set +a
rc() { curl -sk -u "$CEOS_USER:$CEOS_PASSWORD" -H 'Accept: application/yang-data+json' -H 'Content-Type: application/yang-data+json' -w '\n%{http_code}\n' "$@"; }
R1=https://172.20.20.11:6020/restconf/data
R2=https://172.20.20.12:6020/restconf/data
```

**Was passiert:**
- `set -a; . ./.env; set +a` lädt `CEOS_USER` und `CEOS_PASSWORD` als Umgebungsvariablen.
- `rc` ist eine Abkürzung für curl mit Login, beiden JSON-Headern und dem HTTP-Statuscode in der letzten Zeile. `-k` akzeptiert das selbstsignierte Zertifikat, nur im Lab.
- `R1` und `R2` sind die Basis-URLs der beiden Geräte.

> [!tip] Lange Antworten bei PATCH und PUT
> cEOS schickt nach jedem PATCH/PUT den **kompletten neuen Stand** des Ziels zurück. Das ist kein Fehler. Entscheidend ist die **letzte Zeile mit dem Statuscode**.

### nano in 2 Minuten

`^` steht für **Ctrl**, `M-` für **Meta**. Das ist die Option-Taste, wenn im Terminal „Option als Meta“ aktiv ist, sonst zuerst **Esc**, dann die Taste.

| Taste | Wirkung |
|---|---|
| **^O**, Enter | speichern |
| **^X** | beenden (bei Änderungen `Y`/`N`) |
| **^K** / **^U** | Zeile ausschneiden / einfügen (mehrmals ^K = mehrere Zeilen) |
| **M-A** + Pfeile, dann **^K** | Block markieren und ausschneiden |
| **^W** / **M-W** | suchen / nächster Treffer |
| **^\\** | suchen und ersetzen |
| **M-U** / **M-E** | rückgängig / wiederholen |
| **^_** | zu Zeilennummer springen (bei `line 23` in Python-Fehlern) |
| **^C** | aktuelle Zeile anzeigen |
| **^G** | Hilfe |

Für Python startest du nano so:

```bash
nano -ET4 -l datei.py
```

`-E` wandelt Tabs in Leerzeichen, `-T4` setzt die Tabbreite auf 4, `-l` zeigt Zeilennummern.

Python-Skripte startest du im aktivierten venv direkt mit `python datei.py`. Lade dort vorher ebenfalls die `.env` (`set -a; . ./.env; set +a` im Hauptordner des Repos), die Skripte lesen die Zugangsdaten aus der Umgebung.

## 4. Teil B: Discovery und Asset Management

**Ziel:** Hostname, Software und Seriennummer beider cEOS lesen, erst mit curl, dann als Python-Inventar.

### Schritt 1: Wo liegt RESTCONF?

```bash
curl -sk -u "$CEOS_USER:$CEOS_PASSWORD" https://172.20.20.11:6020/.well-known/host-meta
```

**Was passiert:** RFC 8040 schreibt vor, dass ein Client unter `/.well-known/host-meta` erfragen kann, wo RESTCONF liegt.

**Erwartet:** XML mit `<Link rel='restconf' href='/restconf'/>`. Die Daten liegen also unter `/restconf/data`.

### Schritt 2: Ganzen Container lesen

```bash
curl -sk -u "$CEOS_USER:$CEOS_PASSWORD" -H 'Accept: application/yang-data+json' $R1/openconfig-system:system/state | jq .
```

**Was passiert:** `openconfig-system:system` ist der oberste Knoten mit Modulpräfix, `state` ist sein Kind (ohne Präfix, gleicher Namespace). `Accept` verlangt JSON nach RFC 7951. `| jq .` formatiert die Ausgabe. Hier nimmst du curl statt `rc`, weil die Statuszeile `jq` stören würde.

**Erwartet:** viele Leafs, darunter `openconfig-system:hostname` und `openconfig-system:software-version`. Das ist das Vorgehen: erst den Container lesen, dann gezielt das Leaf.

### Schritt 3: Nur ein Leaf

```bash
rc $R1/openconfig-system:system/state/hostname
rc $R1/openconfig-system:system/state/software-version
```

**Was passiert:** Hängst du den Leaf-Namen an, kommt nur dieses eine Feld zurück.

**Erwartet:** `{"openconfig-system:hostname":"ceos1"}` mit `200` darunter, dann `4.32.0F-…`. cEOS setzt `openconfig-system:` vor jedes Feld. Nach RFC 7951 gehört der Präfix nur an den obersten Knoten. Daran denkst du in Python.

### Schritt 4: In eine Liste greifen

```bash
curl -sk -u "$CEOS_USER:$CEOS_PASSWORD" -H 'Accept: application/yang-data+json' $R1/openconfig-platform:components | jq -r '.["openconfig-platform:component"][].name'
rc $R1/openconfig-platform:components/component=Chassis/state/serial-no
```

**Was passiert:** `components` enthält die Liste `component* [name]`. Der erste Befehl zeigt alle Namen. `component=Chassis` adressiert **einen Eintrag** über seinen Schlüssel. Das ist die Kernregel: `<liste>=<schlüssel>` und bei zwei Schlüsseln `<liste>=<w1>,<w2>`.

**Erwartet:** Namen wie `Chassis`, `Aboot`, `EOS`, danach eine Seriennummer. Sie ist bei cEOS zufällig und ändert sich bei jedem Deploy.

### Schritt 5: Fehlerfälle

```bash
rc $R1/openconfig-platform:components/component=Chasis/state/serial-no
curl -sk -o /dev/null -w '%{http_code}\n' -u admin:falsch $R1/openconfig-system:system/state/hostname
```

**Was passiert:** Einmal ein Tippfehler im Schlüssel, einmal ein falsches Passwort.

**Erwartet:** `404` (Ressource gibt es nicht) und `401` (Anmeldung falsch). In der Prüfung musst du diese beiden sicher auseinanderhalten.

### Schritt 6: `inventory.py`, Etappe 1 – Kopf und Konstanten

Im **Editor-Tab**:

```bash
cd "$(git rev-parse --show-toplevel)/lab/restconf"
nano -ET4 -l inventory.py
```

```python
#!/usr/bin/env python3
"""Asset inventory via RESTCONF: hostname, model, serial, software."""
import os
import sys

import requests
import urllib3

urllib3.disable_warnings()  # lab only: self-signed certificate on cEOS

DEVICES = ["172.20.20.11", "172.20.20.12"]
AUTH = (os.environ["CEOS_USER"], os.environ["CEOS_PASSWORD"])
HEADERS = {"Accept": "application/yang-data+json"}

print("ok, credentials for", AUTH[0])
```

**Was passiert:**
- `requests` ist die HTTP-Bibliothek.
- `disable_warnings()` blendet die Zertifikatswarnung aus (nur im Lab).
- `os.environ[...]` liest die Zugangsdaten aus der `.env`. So stehen keine Passwörter im Code, das ist Blueprint 3.6.

Speichern (^O, Enter), beenden (^X), ausführen:

```bash
python inventory.py
```

**Erwartet:** `ok, credentials for admin`.

### Schritt 7: Etappe 2 – GET-Funktion

Die `print`-Zeile löschst du mit **^K**. Dann ergänzt du:

```python
def restconf_get(host, path):
    """GET one resource and return the parsed JSON body (raises on HTTP errors)."""
    url = f"https://{host}:6020/restconf/data/{path}"
    resp = requests.get(url, auth=AUTH, headers=HEADERS, verify=False, timeout=10)
    resp.raise_for_status()
    return resp.json()


print(restconf_get("172.20.20.11", "openconfig-system:system/state/hostname"))
```

**Was passiert:**
- `verify=False` entspricht `curl -k`.
- `timeout=10` gehört immer dazu, sonst hängt das Skript bei einem toten Gerät.
- `raise_for_status()` wirft bei 4xx/5xx eine Exception.
- `resp.json()` macht aus dem Text ein Dict.

**Erwartet:** `{'openconfig-system:hostname': 'ceos1'}`.

### Schritt 8: Etappe 3 – Leaf mit und ohne Präfix

Die Test-`print`-Zeile löschst du wieder und ergänzt:

```python
def leaf(body, name):
    """Return a leaf value whether or not the device prefixes it with the module name."""
    for key, value in body.items():
        if key == name or key.endswith(":" + name):
            return value
    return None
```

**Was passiert:** `leaf()` findet `"openconfig-system:hostname"` (cEOS) genauso wie `"hostname"` (RFC-konform). Das Skript läuft damit auf beiden Gerätearten.

### Schritt 9: Etappe 4 – Hauptprogramm

Ans Ende der Datei:

```python
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
```

**Was passiert:**
- Pro Gerät gibt es zwei GETs auf ganze Container. Das sind weniger Aufrufe als einer pro Leaf.
- `except requests.RequestException` fängt Verbindungsfehler, Timeouts und dank `raise_for_status` auch 401/404 ab.
- `continue` sorgt dafür, dass ein kaputtes Gerät die anderen nicht stoppt.
- `{…:15}` setzt die Spaltenbreite.
- `if __name__ == "__main__"` startet `main()` nur bei direktem Aufruf.

**Erwartet:** zwei Zeilen `ceos1`/`ceos2` mit `cEOSLab`, Seriennummer und `4.32.0F-…`.

### Schritt 10: Fehlerfall im Skript

```bash
CEOS_PASSWORD=falsch python inventory.py
```

**Erwartet:** je Gerät `ERROR 401 Client Error: Unauthorized …`, und das Skript läuft trotzdem bis zum Ende.

> [!question]- Selbsttest Teil B: Wer hängt an ceos1 Ethernet1?
> Lies per RESTCONF den **Systemnamen des LLDP-Nachbarn** an ceos1 Ethernet1 (Modul `openconfig-lldp`, Pfad `lldp/interfaces/interface=…/neighbors`). Lies erst die Liste und dann gezielt das Leaf.
>
> **Lösung:**
> ```bash
> curl -sk -u "$CEOS_USER:$CEOS_PASSWORD" -H 'Accept: application/yang-data+json' $R1/openconfig-lldp:lldp/interfaces/interface=Ethernet1/neighbors | jq .
> rc $R1/openconfig-lldp:lldp/interfaces/interface=Ethernet1/neighbors/neighbor=1/state/system-name
> ```
> Erwartet: `{"openconfig-lldp:system-name":"ceos2"}`. Die Liste `neighbor` hat den Schlüssel `id`, hier `1`. LLDP ist ein schneller Weg zur Topologie für ein Inventar.

## 5. Teil C: PATCH – nur ein Leaf ändern

**Ziel:** Die Beschreibung von Ethernet1 setzen und sehen, warum die RFC-Form auf cEOS scheitert.

### Schritt 1: Ist-Zustand lesen

```bash
I=openconfig-interfaces:interfaces/interface=Ethernet1
rc $R1/$I/config
```

**Was passiert:** `I` ist eine Shell-Variable für den langen Pfad, damit die nächsten Befehle kurz bleiben. Du liest den `config`-Container von Ethernet1.

**Erwartet:** `name`, `type` (`iana-if-type:ethernetCsmacd`), `mtu` 0, noch keine `description`.

### Schritt 2: PATCH in RFC-Form

```bash
rc -X PATCH -d '{"openconfig-interfaces:config":{"description":"to ceos2"}}' $R1/$I/config
```

**Was passiert:**
- `-X PATCH` wählt die Methode, `-d` übergibt den Körper.
- Nach RFC 8040 steht der **Zielknoten** (`config`, mit Präfix) an oberster Stelle. So würdest du es bei IOS XE machen.

**Erwartet:** `400` mit `An unexpected element "config" is present`. cEOS will die Form aus Schritt 3.

### Schritt 3: PATCH in cEOS-Form

```bash
rc -X PATCH -d '{"description":"to ceos2"}' $R1/$I/config
rc $R1/$I/config/description
```

**Was passiert:** Der Körper enthält nur die **Kinder** von `config`. PATCH ist ein Merge, also bleiben `name`, `type` und `mtu` unberührt.

**Erwartet:** `200`, danach `{"openconfig-interfaces:description":"to ceos2"}`.

> [!question]- Selbsttest Teil C
> Setz auf **ceos2** die Beschreibung von Ethernet1 auf `to ceos1` und lies nur dieses Leaf zurück. Wie sähe der Körper nach RFC 8040 aus?
>
> **Lösung:**
> ```bash
> rc -X PATCH -d '{"description":"to ceos1"}' $R2/$I/config
> rc $R2/$I/config/description
> ```
> RFC-Form (IOS XE): `{"openconfig-interfaces:config": {"description": "to ceos1"}}` auf dieselbe URL.

## 6. Teil D: VLANs – PATCH, PUT, DELETE

**Ziel:** VLANs auf beiden Geräten anlegen, einen Access-Port setzen und erleben, dass PUT ersetzt.

### Schritt 1: Modell ansehen (Editor-Tab)

```bash
cd "$(git rev-parse --show-toplevel)/lab/yang"
M=models/vendor/cisco/xe/17131
.venv/bin/pyang -f tree -p $M --tree-path /network-instances/network-instance/vlans --tree-depth 6 $M/openconfig-network-instance.yang
```

**Was passiert:** pyang zeigt den Baum (wie in Übung 2.7).

**Erwartet:** `vlan* [vlan-id]` mit `vlan-id -> ../config/vlan-id`. Der Schlüssel ist ein **leafref** auf `config/vlan-id`, deshalb steht er im Körper **zweimal**. OpenConfig trennt außerdem immer `config` (rw) und `state` (ro).

### Schritt 2: Zwei VLANs mit einem PATCH (Lab-Tab)

```bash
V=openconfig-network-instance:network-instances/network-instance=default/vlans
for R in $R1 $R2; do
  rc -X PATCH -d '{"vlan":[{"vlan-id":10,"config":{"vlan-id":10,"name":"CLIENTS"}},{"vlan-id":20,"config":{"vlan-id":20,"name":"VOICE"}}]}' $R/$V
done
```

**Was passiert:**
- Die URL `network-instance=default` adressiert die Default-Instanz, in OpenConfig liegen dort die VLANs.
- Der Körper enthält das Kind `vlan` als **Liste** mit zwei Einträgen.
- Die `for`-Schleife schickt denselben Aufruf an beide Geräte.

**Erwartet:** zweimal `200` (nach RFC wäre es `204`).

### Schritt 3: Access-Port

```bash
rc -X PATCH -d '{"interface-mode":"ACCESS","access-vlan":10}' "$R1/openconfig-interfaces:interfaces/interface=Ethernet2/openconfig-if-ethernet:ethernet/openconfig-vlan:switched-vlan/config"
```

**Was passiert:** Hier wechselt der Namespace zweimal: `openconfig-if-ethernet:ethernet` und `openconfig-vlan:switched-vlan` sind Augments, deshalb tragen sie einen Präfix. Das ist dieselbe Regel wie in Übung 2.7.

**Erwartet:** `200`.

### Schritt 4: PUT ersetzt

```bash
rc -X PUT -d '{"vlan-id":20}' $R1/$V/vlan=20/config
rc $R1/$V/vlan=20/config/name
```

**Was passiert:** PUT macht das Ziel **genau** zum Körper. `name` fehlt im Körper, also fliegt es raus.

**Erwartet:** `{"openconfig-network-instance:name":"VLAN0020"}`. Der Name ist auf den Default zurückgefallen. Das ist die klassische Prüfungsfalle bei „ändere nur …“.

### Schritt 5: Mit PATCH reparieren

```bash
rc -X PATCH -d '{"name":"VOICE"}' $R1/$V/vlan=20/config
```

**Erwartet:** `200` mit `"name":"VOICE"`.

### Schritt 6: DELETE

```bash
rc -X DELETE $R2/$V/vlan=20
rc $R2/$V/vlan=20
rc -X DELETE $R2/$V/vlan=20
```

**Was passiert:** Löschen, prüfen, dann noch einmal löschen.

**Erwartet:** `200` (nach RFC `204`), dann `404`, dann wieder `404`, weil nichts mehr zu löschen ist.

### Schritt 7: Gegenprobe per CLI

```bash
docker exec clab-autocor-ceos1 Cli -p 15 -c "show vlan"
docker exec clab-autocor-ceos2 Cli -p 15 -c "show vlan"
```

**Erwartet:** ceos1 hat 10 `CLIENTS` (Et2) und 20 `VOICE`, ceos2 nur 10 `CLIENTS`.

> [!question]- Selbsttest Teil D
> Benenne auf ceos2 VLAN 10 in `PFLEGE` um. Welche Methode nimmst du, und was würde ein PUT mit nur `{"name":"PFLEGE"}` auf `vlan=10/config` riskieren?
>
> **Lösung:**
> ```bash
> rc -X PATCH -d '{"name":"PFLEGE"}' $R2/$V/vlan=10/config
> ```
> PATCH, weil nur ein Leaf geändert werden soll. Ein PUT ersetzt den ganzen `config`-Container. Fehlt dort etwas, das das Modell oder Gerät braucht (hier `vlan-id`), fällt es weg oder der Aufruf scheitert.

## 7. Teil E: Loopback, gerouteter Link, Ping

**Ziel:** Routing einschalten, Interfaces anlegen und IPs setzen, die Erreichbarkeit prüfen.

### Schritt 1: Routing einschalten

```bash
for R in $R1 $R2; do
  rc -X PATCH -d '{"arista-netinst-augments:ipv4-routing-enabled":true}' $R/openconfig-network-instance:network-instances/network-instance=default/config
done
```

**Was passiert:** `ip routing` ist bei Arista ein **herstellereigenes Augment** (`arista-netinst-augments:`). So sehen Vendor-Erweiterungen von OpenConfig aus.

**Erwartet:** zweimal `200`.

### Schritt 2: Loopback0 anlegen

```bash
for i in 1 2; do
  R=$([ $i = 1 ] && echo $R1 || echo $R2)
  rc -X PATCH -d "{\"interface\":[{\"name\":\"Loopback0\",\"config\":{\"name\":\"Loopback0\",\"type\":\"iana-if-type:softwareLoopback\",\"description\":\"router-id\"},\"subinterfaces\":{\"subinterface\":[{\"index\":0,\"config\":{\"index\":0},\"openconfig-if-ip:ipv4\":{\"addresses\":{\"address\":[{\"ip\":\"$i.$i.$i.$i\",\"config\":{\"ip\":\"$i.$i.$i.$i\",\"prefix-length\":32}}]}}}]}}]}" $R/openconfig-interfaces:interfaces
done
```

**Was passiert:**
- Loopback0 gibt es noch nicht. Du patchst deshalb **eine Ebene höher** auf `interfaces` und schickst den neuen Listeneintrag mit.
- Die IP sitzt in OpenConfig auf `subinterface` `0` im Augment `openconfig-if-ip:ipv4`.
- `type` ist ein **identityref** und braucht den Präfix im Wert (`iana-if-type:`).
- Weil `$i` eingesetzt werden muss, steht der Körper in doppelten Anführungszeichen. Jedes `"` im JSON wird deshalb als `\"` geschrieben.

**Erwartet:** zweimal `200`.

### Schritt 3: IP auf Ethernet1

```bash
for i in 1 2; do
  R=$([ $i = 1 ] && echo $R1 || echo $R2)
  rc -X PATCH -d "{\"address\":[{\"ip\":\"10.255.12.$i\",\"config\":{\"ip\":\"10.255.12.$i\",\"prefix-length\":30}}]}" "$R/openconfig-interfaces:interfaces/interface=Ethernet1/subinterfaces/subinterface=0/openconfig-if-ip:ipv4/addresses"
done
```

**Was passiert:** Ethernet1 existiert schon, also patchst du direkt auf `addresses`.

**Erwartet:** zweimal `200`.

### Schritt 4: Ping

```bash
docker exec clab-autocor-ceos1 Cli -p 15 -c "ping 10.255.12.2 repeat 2"
```

**Erwartet:** `2 packets transmitted, 2 received, 0% packet loss`.

> [!note] Switchport-Falle
> Auf einem **Switchport** nimmt cEOS eine IP per RESTCONF an (`200`, sie steht sogar in der Running-Config), aktiviert sie aber nicht. Deshalb ist Et1 in der Startkonfiguration auf `no switchport` gesetzt.

> [!question]- Selbsttest Teil E
> Lies per RESTCONF alle IPv4-Adressen von Loopback0 auf ceos1.
>
> **Lösung:**
> ```bash
> rc $R1/openconfig-interfaces:interfaces/interface=Loopback0/subinterfaces/subinterface=0/openconfig-if-ip:ipv4/addresses
> ```
> Erwartet: `1.1.1.1` mit `prefix-length` 32, im `state` steht `origin` `STATIC`.

## 8. Teil F: Extended ACL

**Ziel:** Diese CLI per RESTCONF anlegen, einen Eintrag gezielt lesen und löschen.

```
ip access-list MGMT-IN
   10 permit tcp 172.20.20.0/24 any eq ssh
   20 deny ip any any log
```

### Schritt 1: Modell ansehen (Editor-Tab)

```bash
cd "$(git rev-parse --show-toplevel)/lab/yang"
M=models/vendor/cisco/xe/17131
.venv/bin/pyang -f tree -p $M --tree-path /acl/acl-sets/acl-set --tree-depth 7 $M/openconfig-acl.yang
```

**Erwartet:** `acl-set* [name type]`, also **zwei** Schlüssel. Darunter `acl-entries/acl-entry* [sequence-id]` mit den Containern `ipv4`, `transport` und `actions`.

### Schritt 2: ACL anlegen (Lab-Tab)

```bash
rc -X PATCH -d '{"acl-set":[{"name":"MGMT-IN","type":"openconfig-acl:ACL_IPV4","config":{"name":"MGMT-IN","type":"openconfig-acl:ACL_IPV4"},"acl-entries":{"acl-entry":[{"sequence-id":10,"config":{"sequence-id":10},"ipv4":{"config":{"source-address":"172.20.20.0/24","protocol":"openconfig-packet-match-types:IP_TCP"}},"transport":{"config":{"destination-port":22}},"actions":{"config":{"forwarding-action":"openconfig-acl:ACCEPT"}}},{"sequence-id":20,"config":{"sequence-id":20},"ipv4":{"config":{"source-address":"0.0.0.0/0"}},"actions":{"config":{"forwarding-action":"openconfig-acl:DROP","log-action":"openconfig-acl:LOG_SYSLOG"}}}]}}]}' $R1/openconfig-acl:acl/acl-sets
docker exec clab-autocor-ceos1 Cli -p 15 -c "show running-config section ip access-list MGMT-IN"
```

**Was passiert:**
- `type`, `protocol`, `forwarding-action` und `log-action` sind identityrefs, deshalb steht der Präfix im Wert.
- Eintrag 20 hat `ipv4` mit `0.0.0.0/0` für „any“.

**Erwartet:** `200`, dann genau die beiden CLI-Zeilen von oben.

### Schritt 3: Einen Eintrag lesen, zwei Schlüssel in der URL

```bash
rc $R1/openconfig-acl:acl/acl-sets/acl-set=MGMT-IN,ACL_IPV4/acl-entries/acl-entry=20/config
rc $R1/openconfig-acl:acl/acl-sets/acl-set=MGMT-IN,openconfig-acl:ACL_IPV4
```

**Was passiert:** `acl-set=MGMT-IN,ACL_IPV4` enthält beide Schlüssel in der Reihenfolge des `key`-Statements.

**Erwartet:** `{"openconfig-acl:sequence-id":20}`. Die zweite Zeile mit Präfix im Schlüssel liefert `404`. Das ist eine cEOS-Eigenheit, nach RFC wäre der Präfix korrekt.

### Schritt 4: Eintrag löschen

```bash
rc -X DELETE $R1/openconfig-acl:acl/acl-sets/acl-set=MGMT-IN,ACL_IPV4/acl-entries/acl-entry=20
docker exec clab-autocor-ceos1 Cli -p 15 -c "show running-config section ip access-list MGMT-IN"
```

**Erwartet:** `200`, und in der CLI steht nur noch Zeile 10.

### Schritt 5: Fehlerfall – Pflichtfeld von Arista

```bash
rc -X PATCH -d '{"acl-set":[{"name":"BAD","type":"openconfig-acl:ACL_IPV4","config":{"name":"BAD","type":"openconfig-acl:ACL_IPV4"},"acl-entries":{"acl-entry":[{"sequence-id":10,"config":{"sequence-id":10},"actions":{"config":{"forwarding-action":"openconfig-acl:DROP"}}}]}}]}' $R1/openconfig-acl:acl/acl-sets
```

**Erwartet:** `400 … description leaf is required if ipv4/ipv6/l2 containers are not present`. Gerätespezifische Regeln stehen nicht im Modell, sie zeigen sich nur in Fehlermeldungen oder der Herstellerdoku.

> [!question]- Selbsttest Teil F
> Ergänze in `MGMT-IN` einen Eintrag **15**: `permit tcp 172.20.20.0/24 any eq https`. Und zwar, ohne die ACL neu zu schicken.
>
> **Lösung:**
> ```bash
> rc -X PATCH -d '{"acl-entry":[{"sequence-id":15,"config":{"sequence-id":15},"ipv4":{"config":{"source-address":"172.20.20.0/24","protocol":"openconfig-packet-match-types:IP_TCP"}},"transport":{"config":{"destination-port":443}},"actions":{"config":{"forwarding-action":"openconfig-acl:ACCEPT"}}}]}' $R1/openconfig-acl:acl/acl-sets/acl-set=MGMT-IN,ACL_IPV4/acl-entries
> docker exec clab-autocor-ceos1 Cli -p 15 -c "show running-config section ip access-list MGMT-IN"
> ```
> Erwartet: `15 permit tcp 172.20.20.0/24 any eq https`. Das Ziel ist `acl-entries`, der Körper enthält das Kind `acl-entry` mit dem neuen Eintrag.

## 9. Teil G: Wenn `200` lügt

**Ziel:** Ein ehrlicher Fehler gegen einen stillen. Erleben, dass ein Erfolgscode nichts über die Wirkung aussagt.

### Schritt 1: Der ehrliche Fehler – MTU

```bash
rc -X PATCH -d '{"mtu":9000}' $R1/openconfig-interfaces:interfaces/interface=Ethernet1/config
rc $R1/openconfig-interfaces:interfaces/interface=Ethernet1/config/mtu
```

**Was passiert:** Der OpenConfig-Agent übersetzt dein JSON in CLI-Befehle und schickt sie an EOS. Für die MTU ist das `l2 mtu 9000`, und das kennt cEOS nicht.

**Erwartet:** **`500`** mit `Unavailable command (not supported on this hardware platform) … 'l2 mtu 9000' failed`, danach weiterhin `mtu` `0`. Ein `5xx` heißt „Fehler auf der Geräteseite“. Unangenehm, aber ehrlich: Du erfährst, dass nichts passiert ist.

### Schritt 2: Der stille Fehler – OSPF

```bash
rc -X PATCH -d '{"protocol":[{"identifier":"openconfig-policy-types:OSPF","name":"OSPF","config":{"identifier":"openconfig-policy-types:OSPF","name":"OSPF"},"ospfv2":{"global":{"config":{"router-id":"1.1.1.1"}}}}]}' $R1/openconfig-network-instance:network-instances/network-instance=default/protocols
docker exec clab-autocor-ceos1 Cli -p 15 -c "show running-config section router ospf"
```

**Erwartet:** `200`, aber in der CLI **kein** `router ospf`.

### Schritt 3: Ins Agentenprotokoll schauen

```bash
docker exec clab-autocor-ceos1 bash -c 'grep -i ospf /var/log/agents/OpenConfig-* | tail -5'
```

**Was passiert:** Der OpenConfig-Agent von EOS protokolliert jede Anfrage. Dort siehst du, was angekommen ist.

> [!question]- Selbsttest Teil G
> Wie stellst du in einem Automatisierungsskript sicher, dass eine Änderung wirklich wirkt?
>
> **Lösung:** Nach jedem schreibenden Aufruf ein **GET** auf genau das geänderte Leaf und mit dem Soll vergleichen („read-after-write“). Bei Routing zusätzlich den **operativen Zustand** prüfen (Nachbarn, Routen), z. B. mit pyATS (Blueprint 3.4). Ein `2xx` heißt nur: „Anfrage angenommen“.
>
> Weitere Erkenntnisse aus dem Test vom 26.10.: OSPF über die URL (`protocol=openconfig-policy-types:OSPF,1`) gibt `404 invalid name "OSPF,1"`, weil der Agent den Schlüssel am Doppelpunkt trennt. Mit `%3A` kommt dasselbe. OSPF ist auf cEOS 4.32 per OpenConfig nicht konfigurierbar, für IOS XE siehe Teil I.

## 10. Teil H: Idempotentes VLAN-Skript

**Ziel:** Ein Skript, das VLANs aus einer YAML-Datei auf die Geräte bringt und beim zweiten Lauf nichts mehr ändert. Ausgangslage ist der Stand nach Teil D: ceos1 hat VLAN 10/20, ceos2 VLAN 10. Falls du in D den Selbsttest gemacht hast, heißt VLAN 10 auf ceos2 `PFLEGE`. Das Skript benennt es dann zurück, gut so.

### Schritt 1: Die Soll-Datei

```bash
cd "$(git rev-parse --show-toplevel)/lab/restconf"
nano -ET4 -l vlans.yaml
```

```yaml
# Desired VLANs per device (management IP -> {vlan-id: name})
172.20.20.11:
  10: CLIENTS
  20: VOICE
  30: PRINTER
172.20.20.12:
  10: CLIENTS
  30: PRINTER
```

**Was passiert:** Ein Dict von Geräten. Je Gerät gibt es ein Dict `vlan-id → name`. YAML liest `10` als Zahl, so wie das Gerät die `vlan-id` liefert.

### Schritt 2: Etappe 1 – Soll und Ist lesen

```bash
nano -ET4 -l vlans.py
```

```python
#!/usr/bin/env python3
"""Idempotent VLAN provisioning via RESTCONF (exercise 1.3, part H)."""
import argparse
import os
import sys

import requests
import urllib3
import yaml

urllib3.disable_warnings()  # lab only: self-signed certificate on cEOS

AUTH = (os.environ["CEOS_USER"], os.environ["CEOS_PASSWORD"])
HEADERS = {"Accept": "application/yang-data+json", "Content-Type": "application/yang-data+json"}
VLANS = "openconfig-network-instance:network-instances/network-instance=default/vlans"


def url(host, path):
    return f"https://{host}:6020/restconf/data/{path}"


def get_vlans(host):
    """Return {vlan_id: name} as configured on the device."""
    resp = requests.get(url(host, VLANS), auth=AUTH, headers=HEADERS, verify=False, timeout=10)
    resp.raise_for_status()
    entries = next(iter(resp.json().values()), [])  # key may or may not carry the module prefix
    return {e["config"]["vlan-id"]: e["config"].get("name", "") for e in entries}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="vlans.yaml")
    args = ap.parse_args()
    with open(args.file) as f:
        desired = yaml.safe_load(f)  # {host: {vlan_id: name}}

    for host, vlans in desired.items():
        current = get_vlans(host)
        print(f"{host}: desired {vlans}")
        print(f"{host}: current {current}")


if __name__ == "__main__":
    main()
```

**Was passiert:**
- `argparse` liefert die Option `--file`, damit du später andere Dateien testen kannst.
- `yaml.safe_load` liest die YAML-Datei. Nimm immer `safe_load`, nie `load`, denn das könnte beliebige Python-Objekte erzeugen (Blueprint 3.6).
- `get_vlans()` holt die VLAN-Liste. `next(iter(….values()))` nimmt den einzigen Schlüssel der Antwort, egal ob mit oder ohne Präfix.
- Die Dict-Comprehension baut daraus `{10: 'CLIENTS', …}`.

```bash
python vlans.py
```

**Erwartet:**
```
172.20.20.11: desired {10: 'CLIENTS', 20: 'VOICE', 30: 'PRINTER'}
172.20.20.11: current {1: 'default', 10: 'CLIENTS', 20: 'VOICE'}
172.20.20.12: desired {10: 'CLIENTS', 30: 'PRINTER'}
172.20.20.12: current {1: 'default', 10: 'CLIENTS'}
```

### Schritt 3: Etappe 2 – Unterschied berechnen (Dry-Run)

Ersetz in `main()` die **Schleife** (die letzten drei Zeilen vor der Leerzeile). Markieren mit **M-A** und den Pfeiltasten, ausschneiden mit **^K**. Neu:

```python
    for host, vlans in desired.items():
        current = get_vlans(host)
        todo = {vid: name for vid, name in vlans.items() if current.get(vid) != name}
        print(f"{host}: would change {sorted(todo) or '-'}")
```

**Was passiert:** `todo` enthält nur die VLANs, die fehlen (`current.get(vid)` ist `None`) oder anders heißen. **Das ist der Kern der Idempotenz:** erst vergleichen, dann nur das Nötige schreiben.

**Erwartet:**
```
172.20.20.11: would change [30]
172.20.20.12: would change [30]
```
Hast du in Teil D den Selbsttest gemacht (VLAN 10 heißt auf ceos2 `PFLEGE`), steht bei ceos2 `[10, 30]`. Das Skript erkennt auch einen falschen Namen als Abweichung.

### Schritt 4: Etappe 3 – Schreiben

Über `def main():` fügst du die Funktion ein:

```python
def patch_vlans(host, vlans):
    """Create or rename VLANs in one PATCH (cEOS: body = children of the target resource)."""
    body = {"vlan": [{"vlan-id": vid, "config": {"vlan-id": vid, "name": name}} for vid, name in vlans.items()]}
    resp = requests.patch(url(host, VLANS), auth=AUTH, headers=HEADERS, json=body, verify=False, timeout=10)
    if not resp.ok:
        raise RuntimeError(f"PATCH {resp.status_code}: {resp.text.strip()[:200]}")
```

Und die Schleife in `main()` wird zu:

```python
    for host, vlans in desired.items():
        current = get_vlans(host)
        todo = {vid: name for vid, name in vlans.items() if current.get(vid) != name}
        if todo:
            patch_vlans(host, todo)
        print(f"{host}: changed {sorted(todo) or '-'}")
```

**Was passiert:**
- `json=body` lässt `requests` das Dict als JSON senden. Den `Content-Type` setzt `HEADERS`.
- `resp.ok` ist bei jedem 2xx wahr. Damit funktioniert der Code bei cEOS (`200`) und bei RFC-konformen Geräten (`204`).
- Bei einem Fehler gibt es eine Exception mit Statuscode und Text.

**Zweimal** ausführen. **Erwartet:**
```
172.20.20.11: changed [30]        # 1. Lauf
172.20.20.12: changed [30]
172.20.20.11: changed -           # 2. Lauf: nichts mehr zu tun = idempotent
172.20.20.12: changed -
```

Dann den Fehlerfall: Leg mit `nano bad.yaml` eine Datei mit `172.20.20.11:` und darunter `  5000: BAD` an.

```bash
python vlans.py --file bad.yaml
```

**Erwartet:** ein **Traceback**, der mit `RuntimeError: PATCH 400: … invalid value: 5000` endet. Das Gerät prüft den Wertebereich 1–4094, genau wie in Übung 2.7 (Fehler f3). Das Skript stürzt aber noch ab. Das ändert Etappe 4.

### Schritt 5: Etappe 4 – Aufräumen (`--prune`) und Fehlerbehandlung

Über `def main():` kommt eine weitere Funktion:

```python
def delete_vlan(host, vid):
    resp = requests.delete(url(host, f"{VLANS}/vlan={vid}"), auth=AUTH, headers=HEADERS, verify=False, timeout=10)
    if resp.status_code not in (200, 204):
        raise RuntimeError(f"DELETE vlan {vid}: {resp.status_code} {resp.text.strip()[:200]}")
```

Und `main()` ersetzt du **ganz** durch:

```python
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="vlans.yaml")
    ap.add_argument("--prune", action="store_true", help="delete VLANs not in the file")
    args = ap.parse_args()
    with open(args.file) as f:
        desired = yaml.safe_load(f)  # {host: {vlan_id: name}}

    failed = False
    for host, vlans in desired.items():
        try:
            current = get_vlans(host)
            todo = {vid: name for vid, name in vlans.items() if current.get(vid) != name}
            if todo:
                patch_vlans(host, todo)
            extra = [vid for vid in current if vid != 1 and vid not in vlans] if args.prune else []
            for vid in extra:
                delete_vlan(host, vid)
            print(f"{host}: changed {sorted(todo) or '-'}, deleted {extra or '-'}")
        except (requests.RequestException, RuntimeError) as err:
            print(f"{host}: ERROR {err}", file=sys.stderr)
            failed = True
    sys.exit(1 if failed else 0)
```

**Was passiert:**
- `--prune` (`store_true`) ist ein Schalter ohne Wert.
- `extra` sind VLANs auf dem Gerät, die nicht in der Datei stehen. **VLAN 1 wird nie gelöscht**, das ist eine Schutzregel.
- `try/except` pro Gerät: Ein Fehler stoppt nur dieses Gerät.
- `sys.exit(1)` meldet am Ende einen Fehler nach außen. Wichtig für Pipelines (Blueprint 2.3): Ein Job schlägt nur fehl, wenn das Skript einen Exit-Code ungleich 0 liefert.

Leg im **Lab-Tab** auf ceos2 ein „fremdes“ VLAN an:

```bash
docker exec clab-autocor-ceos2 Cli -p 15 -c "configure
vlan 99
name STALE
end"
```

Dann im **Editor-Tab** nacheinander:

```bash
python vlans.py
python vlans.py --prune
python vlans.py --file bad.yaml; echo exit=$?
```

**Erwartet:**
```
172.20.20.11: changed -, deleted -
172.20.20.12: changed -, deleted -
172.20.20.11: changed -, deleted -
172.20.20.12: changed -, deleted [99]
172.20.20.11: ERROR PATCH 400: … Parameter "vlan-id" has invalid value: 5000
exit=1
```

Ohne `--prune` bleibt VLAN 99 stehen, mit `--prune` verschwindet es. Der Fehlerfall endet jetzt ohne Traceback, mit sauberer Meldung und Exit-Code 1.

> [!question]- Selbsttest Teil H
> Ergänze VLAN `40: GAESTE` auf **beiden** Geräten nur über `vlans.yaml`. Lass das Skript zweimal laufen. Was meldet der zweite Lauf, und warum?
>
> **Lösung:** In `vlans.yaml` unter beiden IPs `  40: GAESTE` ergänzen. Der 1. Lauf meldet `changed [40]` je Gerät, der 2. Lauf `changed -`. Das Skript vergleicht vor dem Schreiben, und es gibt keinen Unterschied mehr. Das ist Idempotenz.

## 11. Teil I: Dasselbe auf IOS XE (Papier, prüfungsnah)

**Ziel:** Die Prüfung fragt IOS XE ab. Schreib URL, Methode und Körper in **RFC-Form** (Zielknoten im Körper). Bäume und JSON hast du in [Übung 2.7](yang-json-yaml.md).

1. Beschreibung `to R2` auf `GigabitEthernet2` per `ietf-interfaces`, nur dieses Leaf ändern.
2. VLAN 10 `CLIENTS` per PUT im Native-Modell.
3. OSPF-Netz `10.255.12.0 0.0.0.3 area 0` in Prozess 1 per PATCH.
4. Interface `GigabitEthernet0/0/1` lesen: Wie sieht die URL aus?
5. Welche Statuscodes erwartest du bei 1–3, und was bei einem zweiten POST von VLAN 10?

> [!example]- Lösung Teil I (nicht am Gerät getestet, abgeleitet aus RFC 8040 und den 17.13.1-Modellen)
> ```
> 1. PATCH /restconf/data/ietf-interfaces:interfaces/interface=GigabitEthernet2
>    {"ietf-interfaces:interface": [{"name": "GigabitEthernet2", "description": "to R2"}]}
>
> 2. PUT /restconf/data/Cisco-IOS-XE-native:native/vlan/Cisco-IOS-XE-vlan:vlan-list=10
>    {"Cisco-IOS-XE-vlan:vlan-list": [{"id": 10, "name": "CLIENTS"}]}
>
> 3. PATCH /restconf/data/Cisco-IOS-XE-native:native/router/Cisco-IOS-XE-ospf:router-ospf/ospf/process-id=1
>    {"Cisco-IOS-XE-ospf:process-id": [{"id": 1,
>       "network": [{"ip": "10.255.12.0", "wildcard": "0.0.0.3", "area": 0}]}]}
>
> 4. GET /restconf/data/ietf-interfaces:interfaces/interface=GigabitEthernet0%2F0%2F1
> ```
> 5. PATCH → **204**. PUT → **201** (neu) bzw. **204** (ersetzt). Ein zweiter **POST** von VLAN 10 auf `…/vlan` → **409 Conflict**.
>
> Der Körper beginnt mit dem **letzten Knoten der URL**, mit Modulpräfix. Eine Liste bleibt auch mit einem Eintrag ein Array. Der Listenschlüssel im Körper muss zum Schlüssel in der URL passen, sonst kommt `400`.

## Prüfungsfragen

1. Welche Methode ändert nur ein Leaf, und welche kann ungewollt Nachbarn löschen? Warum?
2. Welchen Statuscode liefert ein POST auf eine schon vorhandene Ressource nach RFC 8040?
3. Wie adressierst du einen Listeneintrag mit zwei Schlüsseln, und wie ein Interface mit `/` im Namen?
4. Was steht bei PUT/PATCH nach RFC 8040 an oberster Stelle im JSON-Körper?
5. Welche zwei Header braucht ein PATCH mit JSON?
6. Wofür sind `/.well-known/host-meta` und `ietf-yang-library` da?
7. Warum reicht ein `200` nicht als Erfolgsnachweis eines Changes?
8. Was ist der Unterschied zwischen `config` und `state` in OpenConfig?
9. Was macht ein Skript idempotent, und warum braucht eine Pipeline den Exit-Code?

## Aufräumen

Zurück zum Ausgangszustand, im Lab-Tab:

```bash
cd "$(git rev-parse --show-toplevel)/lab/clab" && sudo containerlab destroy --cleanup && sudo containerlab deploy && ./restconf-cert.sh
```

Die Startkonfiguration stellt den Ursprung wieder her. Deine Skripte in `lab/restconf/` bleiben, sie liegen lokal.
