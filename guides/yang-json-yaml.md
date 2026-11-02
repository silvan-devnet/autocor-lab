---
title: "JSON und YAML aus einem YANG-Modell"
description: "AUTOCOR 2.7: Konfigurationen aus YANG-Modellen ableiten"
---

> [!info] Geführter Modus, offline
> pyang und yanglint sind neu für dich. Die Werkzeuge sind deshalb offen erklärt. Die Bauaufgaben (Teil B–E) haben eine **zugeklappte** Lösung: Schreib zuerst dein eigenes JSON und prüf es mit `check.sh`. Klapp die Lösung erst danach auf. Alle Lösungen und alle Fehlerfälle aus Teil F wurden am 26.10.2026 in einem eigenen Ordner gegen die **IOS-XE-17.13.1-Modelle** (dieselbe Version wie der Cat8000v in EVE-NG) mit `yanglint -t config` geprüft: 5× gültig, 10× erwartungsgemäß ungültig. Ein Gerät ist für diese Übung nicht nötig.

## 1. YANG in 5 Minuten

YANG (RFC 7950) beschreibt **Struktur und Regeln** von Konfigurations- und Zustandsdaten. Es ist selbst kein Datenformat. Die Daten werden erst beim Übertragen kodiert: als **XML** (NETCONF, RFC 7950) oder als **JSON** (RESTCONF, RFC 7951). YAML ist kein offizielles YANG-Encoding. Es ist derselbe Baum wie in JSON, nur anders geschrieben, so wie in Ansible-Variablen oder NSO.

| YANG-Baustein | Bedeutung | In JSON (RFC 7951) |
|---|---|---|
| `module` | Datei mit eigenem Namespace und Präfix (`Cisco-IOS-XE-native`, Präfix `ios`) | Modulname als Präfix am obersten Knoten: `"Cisco-IOS-XE-native:native"` |
| `container` | Gruppe ohne eigenen Wert | Objekt `{ … }` |
| `list` + `key` | Mehrere Einträge, eindeutig über den Schlüssel | **immer ein Array** `[ {…}, {…} ]`, auch bei einem einzigen Eintrag. Der Schlüssel muss in jedem Eintrag stehen. |
| `leaf` | Einzelner Wert mit Typ | `"name": "wert"` |
| `leaf-list` | Liste einfacher Werte | Array `["a", "b"]` |
| `choice` / `case` | Nur einer von mehreren Zweigen ist erlaubt | Die Namen von choice und case **tauchen nie auf**, nur die Leafs des gewählten Zweigs |
| `augment` | Ein anderes Modul hängt Knoten in einen fremden Baum | Ab dort steht der **Präfix des augmentierenden Moduls**: `"ietf-ip:ipv4"`, `"Cisco-IOS-XE-vlan:vlan-list"` |
| `grouping` / `uses` | Wiederverwendbarer Baustein (wie ein Makro) | unsichtbar, nur das Ergebnis zählt |
| `identityref` | Wert aus einer Identity-Hierarchie | Wert **mit Modulpräfix**: `"iana-if-type:ethernetCsmacd"` |
| Präsenz-Container `!` | Allein durch sein Vorhandensein ein Schalter | `"x": {}` |

### Die Präfixregel (wichtigster Punkt der Prüfung)

Ein Knoten bekommt den Präfix `modulname:` **genau dann, wenn sich der Namespace gegenüber dem Elternknoten ändert**. Das gilt immer am obersten Knoten und an jeder Stelle, an der ein augment greift. Kinder erben den Namespace. Es ist **der Modulname, nicht der YANG-Präfix**: `Cisco-IOS-XE-vlan:` und nicht `ios-vlan:`.

### Typen, die in JSON anders aussehen als erwartet

| YANG-Typ | JSON | Falle |
|---|---|---|
| `int8/16/32`, `uint8/16/32` | Zahl `10` | – |
| **`int64`, `uint64`, `decimal64`** | **String `"10"`** | JavaScript kann 64-Bit-Zahlen nicht exakt darstellen, deshalb schreibt RFC 7951 einen String vor |
| `boolean` | `true` / `false` | **ohne Anführungszeichen** |
| **`empty`** | **`[null]`** | nicht `true`, nicht `""`, nicht `{}` |
| `enumeration`, `string`, `inet:ipv4-address` | String | – |
| `identityref` | `"modul:identity"` | Präfix ist Pflicht, wenn die Identity aus einem anderen Modul stammt |

## 2. Werkzeuge

Alles liegt in `lab/yang/` und läuft **lokal**, ohne Workstation und ohne Gerät:

```bash
cd "$(git rev-parse --show-toplevel)/lab/yang"
./fetch_models.sh        # einmalig: Modelle (66 MB, nicht im Git) + pyang-venv
```

| Werkzeug | Wofür |
|---|---|
| `models/vendor/cisco/xe/17131/` | 769 YANG-Module von IOS XE 17.13.1 aus github.com/YangModels/yang. Darin liegen auch `ietf-*` und `openconfig-*` in der von Cisco ausgelieferten Version. |
| **pyang** (`.venv/bin/pyang`) | Modelle lesen: `-f tree` zeigt den Baum. Mit `--tree-path` springst du direkt zu einem Teilbaum, mit `--tree-depth` begrenzt du die Tiefe. |
| **yanglint** (libyang, `brew install libyang`) | Instanzdaten (JSON/XML) **gegen das Modell prüfen** und zwischen den Formaten umwandeln. pyang selbst prüft keine Daten. |
| **`check.sh`** | Hülle um yanglint: wandelt YAML in JSON um, lädt die Module anhand der Präfixe in deiner Datei und prüft mit `-t config`. Mit dem Zusatz `xml` gibt es das Dokument auch als XML aus. |

Kurzform für die Bäume (in der Übung immer so):

```bash
M=models/vendor/cisco/xe/17131
tree() { .venv/bin/pyang -f tree -p $M --tree-path "$1" --tree-depth "${3:-6}" $M/Cisco-IOS-XE-native.yang $2; }
tree /native/vlan $M/Cisco-IOS-XE-vlan.yang 4
```

> [!warning] Warum der Augment-Modul-Name mit muss
> `Cisco-IOS-XE-native.yang` allein enthält **kein** VLAN, OSPF oder ACL. Diese Teile kommen per augment aus `Cisco-IOS-XE-vlan`, `-ospf` und `-acl`. Ohne das zweite Modul ist der Teilbaum leer. Genau so ist es später bei RESTCONF: Du musst wissen, aus welchem Modul ein Knoten stammt, sonst stimmt die URL nicht.

### Baumsymbole

```
+--rw name           Konfiguration (read-write)
+--ro oper-status    Zustand (read-only), gehört nie in ein PUT/PATCH
leaf?                optional
list* [key]          Liste mit Schlüssel(n), z. B. network* [ip wildcard] = zwei Schlüssel
leaf-list*           Liste einfacher Werte (ohne [key])
container!           Präsenz-Container
+--:(case-name)      Zweig einer choice (taucht im JSON nicht auf)
-> /pfad             leafref, Wert muss an anderer Stelle existieren
{feature}?           nur vorhanden, wenn das Gerät das Feature meldet
x--rw                deprecated (noch nutzbar)
o--rw                obsolete (nicht mehr nutzen)
ios-vlan:name        Präfix vor dem Knoten = kommt aus einem anderen Modul (augment)
```

## 3. Teil A: Bäume lesen

Beantworte die Fragen nur mit `pyang` und ohne Lösung:

1. `.venv/bin/pyang -f tree -p $M $M/ietf-interfaces.yang` – welche Knoten unter `interface` sind Pflicht? Was ist `interfaces-state`, und warum gehört es nie in eine Konfiguration?
2. Unter welchem Pfad liegt die VLAN-Liste im Native-Modell, und aus welchem Modul kommt `vlan-list`? Welche Knoten auf derselben Ebene sind mit `x` oder `o` markiert?
3. `tree /native/router $M/Cisco-IOS-XE-ospf.yang 5`: Es gibt **zwei** OSPF-Listen. Welche ist obsolete, und welcher Pfad ist der aktuelle?
4. Welche Schlüssel hat die Liste `network` unter `process-id`?
5. `tree /native/ip/access-list/extended $M/Cisco-IOS-XE-acl.yang 9`: Wie heißt die choice für die Quelle, und welche cases hat sie?

> [!example]- Lösung Teil A
> 1. Pflicht: `name` (Schlüssel) und `type` (kein `?`). `interfaces-state` ist `ro` (`config false`), also Betriebszustand (Zähler, `oper-status`). Er kommt nur bei GET zurück. IOS XE 17.13 liefert `ietf-interfaces` in der Fassung von 2014 (RFC 7223) aus. In der Nachfolgefassung RFC 8343 ist `interfaces-state` deprecated, dort steht der Zustand direkt unter `interfaces`.
> 2. `/native/vlan/vlan-list` (Schlüssel `id`, `uint16`), Modul **Cisco-IOS-XE-vlan** (Präfix `ios-vlan`). Daneben ist `configuration* [vlan-id]` mit `x` (deprecated) markiert, `device-tracking!` mit `o` (obsolete). Für einfache VLANs mit Namen nimmst du `vlan-list`.
> 3. `o--rw ios-ospf:ospf* [id]` direkt unter `router` ist **obsolete**. Aktuell ist `/native/router/router-ospf/ospf/process-id* [id]`. Für VRF-Prozesse gibt es `process-id-vrf* [id vrf]`.
> 4. `network* [ip wildcard]`: zwei Schlüssel, beide Pflicht. Dazu kommt `area` als normales Leaf.
> 5. `source-choice` mit den cases `ipv4-prefix-case` (`ipv4-address` + `mask`), `any-case` (`any`, Typ `empty`), `host-case` (`host-address`), `fqdn-group-case`, `geo-group-case` und `object-group-case`.

## 4. Teil B: Interface (ietf-interfaces + ietf-ip)

Lege deine Dateien in **`lab/yang/uebung/`** ab und prüfe jede mit `../check.sh datei.json`.

Baue `b-interface.json` für R1 aus dem Soll-Zustand von Übung 1.1:

- `GigabitEthernet2`, Beschreibung `to R2`, Typ Ethernet, eingeschaltet
- IPv4 `10.255.12.1` mit Maske `255.255.255.252`

Hinweise: `type` ist ein identityref aus `iana-if-type`. Die IPv4-Adresse kommt per augment aus `ietf-ip`. Schau mit `pyang -f tree -p $M $M/ietf-ip.yang | head -40` nach, wie die Adressliste heißt. `netmask` ist ein Feature und `check.sh` schaltet es ein. Die Alternative ist `prefix-length: 30`.

> [!example]- Lösung Teil B
> ```json
> {
>   "ietf-interfaces:interfaces": {
>     "interface": [
>       {
>         "name": "GigabitEthernet2",
>         "description": "to R2",
>         "type": "iana-if-type:ethernetCsmacd",
>         "enabled": true,
>         "ietf-ip:ipv4": {
>           "address": [
>             { "ip": "10.255.12.1", "netmask": "255.255.255.252" }
>           ]
>         }
>       }
>     ]
>   }
> }
> ```
> Drei Präfixe, drei Namespace-Wechsel: oben `ietf-interfaces:`, beim augment `ietf-ip:`, und im **Wert** des identityref `iana-if-type:`. `interface` und `address` sind Listen, also Arrays, obwohl sie nur einen Eintrag haben.

## 5. Teil C: VLANs (Native-Modell) als JSON **und** YAML

`c-vlans.json` und `c-vlans.yaml`: VLAN 10 `CLIENTS`, VLAN 20 `VOICE` (passend zum Trunk R1–SW1 aus Übung 1.1).

> [!example]- Lösung Teil C
> ```json
> {
>   "Cisco-IOS-XE-native:native": {
>     "vlan": {
>       "Cisco-IOS-XE-vlan:vlan-list": [
>         { "id": 10, "name": "CLIENTS" },
>         { "id": 20, "name": "VOICE" }
>       ]
>     }
>   }
> }
> ```
> ```yaml
> # Same tree as the JSON - module-qualified keys need no quotes in YAML
> Cisco-IOS-XE-native:native:
>   vlan:
>     Cisco-IOS-XE-vlan:vlan-list:
>       - id: 10
>         name: CLIENTS
>       - id: 20
>         name: VOICE
> ```
> `vlan` hat keinen Präfix, weil es zum Native-Modul gehört. `vlan-list` bekommt einen, weil es aus dem VLAN-Modul kommt. `id` ist `uint16` und steht deshalb als Zahl ohne Anführungszeichen. Im YAML ist jedes `- ` ein Listeneintrag.
>
> `./check.sh c-vlans.yaml xml` zeigt dieselben Daten als NETCONF-XML. Dort erscheint der Namespace-Wechsel als `xmlns="http://cisco.com/ns/yang/Cisco-IOS-XE-vlan"` an jedem `vlan-list`.

## 6. Teil D: OSPF

`d-ospf.json`: Prozess 1, Router-ID `1.1.1.1`, Netz `10.255.12.0 0.0.0.3` in Area 0.

> [!example]- Lösung Teil D
> ```json
> {
>   "Cisco-IOS-XE-native:native": {
>     "router": {
>       "Cisco-IOS-XE-ospf:router-ospf": {
>         "ospf": {
>           "process-id": [
>             {
>               "id": 1,
>               "router-id": "1.1.1.1",
>               "network": [
>                 { "ip": "10.255.12.0", "wildcard": "0.0.0.3", "area": 0 }
>               ]
>             }
>           ]
>         }
>       }
>     }
>   }
> }
> ```
> Der augment greift bei `router-ospf`, also steht dort der Präfix. Darunter folgen `ospf` (Container) und `process-id` (Liste). `network` hat zwei Schlüssel, und **beide** müssen stehen (siehe Fehler f8).

## 7. Teil E: Extended ACL mit choice

`e-acl.json`, entspricht dieser CLI:

```
ip access-list extended MGMT-IN
 10 permit tcp 192.0.2.0 0.0.0.255 any eq 22
 20 deny ip any any log
```

Hinweise: Schau dir die cases von Quelle und Ziel an. `sequence` hat einen besonderen Typ, also prüf ihn im Baum. `any`, `dst-any` und `log` sind vom Typ `empty`.

> [!example]- Lösung Teil E
> ```json
> {
>   "Cisco-IOS-XE-native:native": {
>     "ip": {
>       "access-list": {
>         "Cisco-IOS-XE-acl:extended": [
>           {
>             "name": "MGMT-IN",
>             "access-list-seq-rule": [
>               {
>                 "sequence": "10",
>                 "ace-rule": {
>                   "action": "permit", "protocol": "tcp",
>                   "ipv4-address": "192.0.2.0", "mask": "0.0.0.255",
>                   "dst-any": [null], "dst-eq": 22
>                 }
>               },
>               {
>                 "sequence": "20",
>                 "ace-rule": {
>                   "action": "deny", "protocol": "ip",
>                   "any": [null], "dst-any": [null], "log": [null]
>                 }
>               }
>             ]
>           }
>         ]
>       }
>     }
>   }
> }
> ```
> - **`sequence` ist `uint64`, also String `"10"`.** Beim Test war genau das der erste Fehler in der Musterlösung: `Invalid non-num64-encoded uint64 value "10"`.
> - `mask` ist im IOS-Modell die **Wildcard**, nicht die Netzmaske.
> - Die choices (`source-choice`, `destination-choice`, `dst-port-choice`) und ihre cases stehen nirgends im JSON. Du schreibst nur die Leafs des gewählten Zweigs.
> - `empty` wird als `[null]` geschrieben.

## 8. Teil F: Finde den Fehler

Jedes Dokument hat **genau einen** Fehler. Finde ihn zuerst durch Hinsehen und prüf dann mit `check.sh`. Die Dateien musst du selbst anlegen.

| Datei | Inhalt (gekürzt auf das Wesentliche) |
|---|---|
| f1 | `{"Cisco-IOS-XE-native:native":{"vlan":{"vlan-list":[{"id":10,"name":"CLIENTS"}]}}}` |
| f2 | `{"Cisco-IOS-XE-native:native":{"vlan":{"Cisco-IOS-XE-vlan:vlan-list":{"id":10,"name":"CLIENTS"}}}}` |
| f3 | `… "Cisco-IOS-XE-vlan:vlan-list":[{"id":5000,"name":"CLIENTS"}] …` |
| f4 | `{"interfaces":{"interface":[{"name":"Gi2","type":"iana-if-type:ethernetCsmacd"}]}}` |
| f5 | `{"ietf-interfaces:interfaces":{"interface":[{"name":"Gi2","type":"ethernetCsmacd"}]}}` |
| f6 | `… "type":"iana-if-type:ethernetCsmacd","ipv4":{"address":[{"ip":"10.255.12.1","prefix-length":30}]} …` |
| f7 | `… "type":"iana-if-type:ethernetCsmacd","enabled":"true" …` |
| f8 | `… "process-id":[{"id":1,"network":[{"ip":"10.255.12.0","area":0}]}] …` |
| g1 | ACL-Regel 20 mit `"any": true` |
| g2 | ACL-Regel 10 mit `"any":[null]` **und** `"ipv4-address":"192.0.2.0","mask":"0.0.0.255"` |

> [!example]- Auflösung Teil F (Meldungen von yanglint)
> | Datei | Fehler | yanglint |
> |---|---|---|
> | f1 | Präfix `Cisco-IOS-XE-vlan:` fehlt am augment | `Node "vlan-list" not found as a child of "vlan"` |
> | f2 | Liste als Objekt statt Array | `list "vlan-list" is represented in input data as name/object` |
> | f3 | VLAN-ID außerhalb 1–4094 | `Unsatisfied range - value "5000"` |
> | f4 | oberster Knoten ohne Modulpräfix | `Top-level JSON object member "interfaces" must be namespace-qualified` |
> | f5 | identityref ohne Modulpräfix | `identity not found in module "ietf-interfaces"` |
> | f6 | Präfix `ietf-ip:` fehlt an `ipv4` | `Node "ipv4" not found as a child of "interface"` |
> | f7 | Boolean als String | `Invalid non-boolean-encoded boolean value "true"` |
> | f8 | zweiter Listenschlüssel `wildcard` fehlt | `List instance is missing its key "wildcard"` |
> | g1 | `empty` als `true` statt `[null]` | `Invalid empty value` |
> | g2 | zwei cases derselben choice gleichzeitig | `Data for both cases "ipv4-prefix-case" and "any-case" exist` |

> [!warning] `-t edit` findet g2 nicht
> Mit `yanglint -t edit` (Inhalt eines edit-config) gilt g2 als **gültig**, und beide Zweige bleiben stehen. Erst `-t config` prüft den vollständigen Datenbaum samt choices. `check.sh` nutzt deshalb `-t config`. Auch ein Gerät prüft so etwas erst beim Commit und lehnt es dann ab oder ersetzt den alten case.

## 9. Teil G: Übertrag auf RESTCONF (Vorschau auf Kapitel 3)

Dieselben Bäume werden in Kapitel 3 zu URLs. Das Muster für die RESTCONF-URL nach RFC 8040:

```
https://<gerät>/restconf/data/<modul>:<top-knoten>/<kind>/<augment-modul>:<knoten>=<schlüssel>
```

Beispiele, abgeleitet aus Teil C und E. **Noch nicht am Gerät getestet**, das kommt in Übung 1.3:

```
GET  /restconf/data/Cisco-IOS-XE-native:native/vlan/Cisco-IOS-XE-vlan:vlan-list=10
GET  /restconf/data/Cisco-IOS-XE-native:native/ip/access-list/Cisco-IOS-XE-acl:extended=MGMT-IN
GET  /restconf/data/ietf-interfaces:interfaces/interface=GigabitEthernet2
```

Die Präfixregel gilt in der URL genauso wie im JSON. Mehrere Schlüssel werden mit Komma getrennt, zum Beispiel `network=10.255.12.0,0.0.0.3`. Der Payload eines PUT auf `…/vlan-list=10` beginnt mit dem **Zielknoten** selbst: `{"Cisco-IOS-XE-vlan:vlan-list": [{"id": 10, …}]}`.

## Prüfungsfragen

1. Wann bekommt ein JSON-Knoten einen Modulpräfix, und ist es der Modulname oder der YANG-Präfix?
2. Wie sieht ein Leaf vom Typ `empty` in JSON aus, und wie eines vom Typ `uint64`?
3. Warum ist eine Liste mit einem Eintrag trotzdem ein Array?
4. Wo stehen die Namen von choice und case im JSON?
5. Was unterscheidet `+--ro` von `+--rw`, und was bedeutet das für ein PUT?
6. Wie unterscheidet sich der Namespace-Wechsel in XML (NETCONF) von dem in JSON (RESTCONF)?
7. Warum zeigt `pyang -f tree Cisco-IOS-XE-native.yang` allein kein `vlan-list`?
