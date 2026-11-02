---
title: "Docker Compose: ein Inventar-Stack"
description: "AUTOCOR 2.5: Compose-Dateien lesen und bauen"
---

> [!info] Geführtes Mitmachen
> Jeder Schritt: **abtippen → ausführen → mit „Erwartet“ vergleichen**. Am Ende jedes Teils kommt ein **Selbsttest** mit zugeklappter Lösung. Alle Etappen, Fehlerfälle und die Lese-Aufgabe wurden am 30.10.2026 im Lab geprüft (Docker 27.5, Compose v5.6), in einem eigenen Ordner mit demselben Projektnamen `inventory`.
>

**Was du baust:** einen kleinen Stack aus zwei Containern. Der **collector** fragt per RESTCONF ceos1 und ceos2 ab (wie dein `inventory.py`) und schreibt das Ergebnis in ein Volume. **web** (nginx) liefert es als Webseite aus, die du im Browser lokal ansiehst.

```
 Browser ──http://localhost:8080──▶ ┌────────────── Lab-Host ──────────────────────────┐
                                    │  web (nginx) ── Netz frontend                    │
                                    │     │ liest                                      │
                                    │  Volume inventory-data                           │
                                    │     │ schreibt                                   │
                                    │  collector (Python) ── Netz clab-mgmt (extern) ──┼─▶ ceos1/ceos2 :6020
                                    └──────────────────────────────────────────────────┘
```

## 1. Docker Compose in 5 Minuten

Eine **Compose-Datei** (`compose.yaml`, früher `docker-compose.yml`) beschreibt einen ganzen Stack deklarativ: welche Container, wie verbunden, welche Daten bleiben. `docker compose up` baut daraus den Ist-Zustand, wie IaC für Container. Das Feld `version:` ganz oben ist veraltet und wird ignoriert.

| Schlüssel | Bedeutung | Prüfungsrelevant, weil … |
|---|---|---|
| `services:` | die Container. Der Name (`web`) ist gleichzeitig der **DNS-Name** im Netz | Name = Hostname für andere Services |
| `image:` / `build:` | fertiges Image ziehen oder aus einem Ordner mit `Dockerfile` bauen | `build` braucht `--build` beim Ändern |
| `ports:` | `"HOST:CONTAINER"`, optional `"IP:HOST:CONTAINER"` | ohne IP wird der Port auf **allen** Adressen geöffnet, auch IPv6 |
| `volumes:` (im Service) | `name:/pfad` = **benanntes Volume** · `./ordner:/pfad` = **Bind-Mount** · `:ro` = nur lesen | Volumes überleben `down`, Bind-Mounts sind Dateien auf dem Host |
| `volumes:` (oben) | deklariert benannte Volumes. `external: true` = existiert schon, Compose legt es nicht an | |
| `networks:` (oben) | eigene Netze. `external: true` + `name:` = fremdes Netz nutzen. `internal: true` = ohne Weg nach draußen | Services sehen sich nur in gemeinsamen Netzen |
| `environment:` / `env_file:` | Umgebungsvariablen direkt oder aus einer Datei. `${VAR}` wird beim Start aus der Shell bzw. einer `.env` im Projektordner ersetzt | Secrets! |
| `depends_on:` | Startreihenfolge, mit `condition: service_healthy` auch „erst wenn gesund“ | |
| `healthcheck:` | Befehl, der „gesund“ prüft | |
| `restart:` | `no` · `always` · `unless-stopped` · `on-failure` | |
| `links:` | **Altlast:** Alias für einen anderen Service, nur wirksam in einem gemeinsamen Netz. Heute: `networks: … aliases:` | steht im Blueprint |

**Projektname:** Compose nimmt den **Ordnernamen** (hier `inventory`) als Präfix. Container heißen `inventory-web-1`, Volumes `inventory_inventory-data`, Netze `inventory_frontend`.

### Die wichtigsten Befehle

| Befehl | Wirkung |
|---|---|
| `docker compose config` | Datei prüfen und **aufgelöst** anzeigen (Variablen eingesetzt) |
| `docker compose up -d` | Stack starten oder auf den Stand der Datei bringen (`-d` = im Hintergrund) |
| `docker compose up -d --build` | dasselbe, Images aus `build:` neu bauen |
| `docker compose ps` | Container des Projekts mit Status und Ports |
| `docker compose logs -f <service>` | Logs verfolgen (Ctrl+C beendet nur das Mitlesen) |
| `docker compose exec <service> <befehl>` | Befehl im laufenden Container |
| `docker compose stop` / `start` | anhalten/fortsetzen, Container bleiben |
| `docker compose down` | Container und Netze löschen, **Volumes bleiben** |
| `docker compose down -v` | zusätzlich die Volumes löschen, also **Daten weg** |

## 2. Vorbereitung

Du arbeitest wieder mit den **zwei Tabs** aus der [Lab-Einrichtung](lab-setup.md). Das Lab muss laufen, sonst gibt es nichts zu sammeln:

```bash
(cd lab/clab && sudo containerlab inspect | grep -c running)
```

**Erwartet:** `3`. Dann den Arbeitsordner anlegen und die Zugangsdaten aus der `.env` laden (im Hauptordner des Repos):

```bash
set -a; . ./.env; set +a
mkdir -p lab/compose/inventory/html
cd "$(git rev-parse --show-toplevel)/lab/compose/inventory"
```

## 3. Teil A: Ein Service, ein Port, ein Bind-Mount

### Schritt 1: Eine Webseite

```bash
nano -ET4 -l html/index.html
```

```html
<h1>Hallo aus dem Container</h1>
```

### Schritt 2: Die erste Compose-Datei

```bash
nano -ET4 -l compose.yaml
```

```yaml
services:
  web:
    image: nginx:1.27-alpine
    ports:
      - "0.0.0.0:8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
```

**Was passiert:**
- `services: web:` definiert einen Service namens `web`.
- `image: nginx:1.27-alpine` ist ein fertiges Image vom Docker Hub. Die **Version ist festgenagelt** (`1.27`), nicht `latest`. So ist das Ergebnis morgen dasselbe wie heute.
- `ports: "0.0.0.0:8080:80"`: Host-Port 8080 wird auf Container-Port 80 weitergeleitet, aber **nur auf IPv4**. Ohne `0.0.0.0:` öffnet Docker auch `[::]:8080`. Ein Lab-Dienst soll nicht ungewollt auch über IPv6 erreichbar sein, darum hier explizit IPv4.
- `volumes: ./html:/usr/share/nginx/html:ro` ist ein **Bind-Mount**: Dein Ordner `html` erscheint im Container als Web-Root, nur lesbar (`:ro`).
- YAML-Einrückung: **2 Leerzeichen je Ebene**, Listen mit `- `. Ein falsches Leerzeichen ist der häufigste Fehler (Teil F).

### Schritt 3: Prüfen und starten (Editor-Tab)

```bash
docker compose config
docker compose up -d
```

**Was passiert:**
- `config` liest die Datei, prüft sie und gibt sie vollständig aus, mit Projektname `inventory` und dem absoluten Pfad des Bind-Mounts. Steht dort kein Fehler, ist die Syntax in Ordnung.
- `up -d` lädt das Image (beim ersten Mal), legt das Netz `inventory_default` an und startet den Container.

**Erwartet:** am Ende `Container inventory-web-1 Started`.

### Schritt 4: Nachsehen

Im **Lab-Tab**:

```bash
cd "$(git rev-parse --show-toplevel)/lab/compose/inventory"
docker compose ps
curl -s localhost:8080
```

Im **Browser lokal**: `http://localhost:8080`

**Erwartet:**
- `ps` zeigt `web` mit `0.0.0.0:8080->80/tcp`, nur IPv4.
- curl und Browser zeigen die Überschrift „Hallo aus dem Container“.

Ändere den Text in `html/index.html` und lade die Seite neu. Der neue Text ist da, **ohne Neustart**. Das ist der Bind-Mount: Der Container liest live die Datei vom Host.

> [!question]- Selbsttest Teil A
> 1. Was ändert sich, wenn du `"0.0.0.0:8080:80"` durch `"127.0.0.1:8080:80"` ersetzt? Kommst du dann noch von einem anderen Rechner auf die Seite?
> 2. Warum `nginx:1.27-alpine` und nicht `nginx:latest`?
>
> **Lösung:**
> 1. Der Port lauscht dann nur auf dem Loopback des Lab-Hosts. `curl localhost:8080` auf dem Lab-Host geht, ein anderer Rechner kommt nicht mehr hin. So veröffentlichst du Dienste, die nur ein Reverse-Proxy auf demselben Host erreichen soll (siehe Teil G).
> 2. Reproduzierbarkeit. `latest` ist morgen ein anderes Image, und ein Stack kann ohne Änderung an der Datei kaputtgehen.

## 4. Teil B: Benanntes Volume, geteilt von zwei Services

### Schritt 1: Einen zweiten Service und ein Volume

Ersetze den Inhalt von `compose.yaml` (in nano mit **M-A**, Pfeiltasten, **^K** alles markieren und löschen, dann neu tippen):

```yaml
services:
  web:
    image: nginx:1.27-alpine
    ports:
      - "0.0.0.0:8080:80"
    volumes:
      - inventory-data:/usr/share/nginx/html:ro

  collector:
    image: alpine:3.20
    command: sh -c 'while true; do date -Iseconds > /data/now.txt; sleep 10; done'
    volumes:
      - inventory-data:/data

volumes:
  inventory-data:
```

**Was passiert:**
- `inventory-data` ohne `./` davor ist ein **benanntes Volume**. Docker verwaltet es selbst unter `/var/lib/docker/volumes/…`, nicht in deinem Ordner.
- Beide Services hängen **dasselbe** Volume ein, aber an verschiedenen Stellen: `collector` schreibt nach `/data`, `web` liest dasselbe als Web-Root.
- `command:` überschreibt den Startbefehl des Images. Hier schreibt eine Shell-Schleife alle 10 s die Uhrzeit in eine Datei.
- Ganz unten `volumes: inventory-data:` **deklariert** das Volume. Ohne diese Zeilen meldet Compose einen Fehler.

### Schritt 2: Starten (Editor-Tab)

```bash
docker compose up -d
```

**Erwartet:** `inventory-collector-1 Started`. `web` wird **neu erzeugt** (`Recreated`), weil sich seine Definition geändert hat. Compose gleicht immer Soll und Ist ab.

### Schritt 3: Nachsehen (Lab-Tab)

```bash
docker compose ps
curl -s localhost:8080/now.txt
docker volume ls
docker compose exec collector ls /data
```

**Erwartet:**
- `curl` liefert einen Zeitstempel, und alle 10 s einen neuen.
- `docker volume ls` zeigt `inventory_inventory-data`, mit Projektpräfix.
- In `/data` liegen `now.txt` **und** `index.html` und `50x.html`.

**Woher kommen die HTML-Dateien?** Ein **leeres benanntes Volume** wird beim ersten Einhängen mit dem Inhalt des Images an dieser Stelle befüllt, hier den nginx-Standardseiten. Ein Bind-Mount macht das **nicht**, er verdeckt den Image-Inhalt. Deshalb zeigt `http://localhost:8080/` jetzt die nginx-Willkommensseite.

> [!question]- Selbsttest Teil B
> Leg im Volume eine Markierungsdatei an (Lab-Tab):
> ```bash
> docker compose exec collector touch /data/marker.txt
> ```
> Ist `http://localhost:8080/marker.txt` noch da nach (a) `docker compose down` + `up -d` und (b) `docker compose down -v` + `up -d`? Erst tippen, dann ausprobieren. (`now.txt` taugt dafür nicht, der collector schreibt sie beim Start sofort neu.)
>
> **Lösung:** (a) **Ja** (`200`). `down` löscht Container und Netze, **nicht** die Volumes. (b) **Nein** (`404`). `down -v` löscht das Volume, beim `up` entsteht ein neues, leeres, in das nginx wieder seine Standardseiten kopiert. `down -v` heißt **Daten weg**. In Produktion vorsichtig.

## 5. Teil C: Eigenes Image, Secrets, externes Netz

Jetzt wird aus dem Dummy der echte collector: dein `inventory.py` als Dauerläufer im Container.

### Schritt 1: Das Programm (Editor-Tab)

```bash
mkdir -p collector
nano -ET4 -l collector/collector.py
```

```python
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
```

**Was passiert, das neu ist gegenüber `inventory.py`:**
- **Alles Einstellbare kommt aus der Umgebung:** Geräte, Zugangsdaten, Intervall. Das Image bleibt gleich, nur die Compose-Datei ändert sich. Nach der „12-Factor“-Regel gehört Konfiguration in die Umgebung, nicht in den Code.
- Fehler pro Gerät landen **in den Daten** (`"error"`), statt das Programm zu beenden. Ein Dauerläufer soll weiterlaufen.
- `print(…, flush=True)`: Ohne `flush` puffert Python die Ausgabe, und `docker compose logs` bliebe leer.
- `while True` + `sleep`: Der Container lebt so lange wie die Schleife.

### Schritt 2: Das Rezept fürs Image

```bash
nano -ET4 -l collector/Dockerfile
```

```dockerfile
FROM python:3.13-slim
RUN pip install --no-cache-dir requests
WORKDIR /app
COPY collector.py .
CMD ["python", "-u", "collector.py"]
```

**Was passiert:**
- `FROM` ist das Basis-Image, ein schlankes Python.
- `RUN` wird **beim Bauen** ausgeführt und installiert `requests` ins Image.
- `WORKDIR` ist das Arbeitsverzeichnis im Image.
- `COPY` kopiert dein Skript aus dem Build-Ordner `collector/` ins Image.
- `CMD` ist der Startbefehl. `-u` heißt „unbuffered“, doppelt hält besser zum `flush`.

### Schritt 3: Die Compose-Datei

`compose.yaml` ganz ersetzen:

```yaml
services:
  web:
    image: nginx:1.27-alpine
    ports:
      - "0.0.0.0:8080:80"
    volumes:
      - inventory-data:/usr/share/nginx/html:ro
    networks:
      - frontend

  collector:
    build: ./collector
    environment:
      CEOS_USER: ${CEOS_USER}
      CEOS_PASSWORD: ${CEOS_PASSWORD}
      INTERVAL: "30"
    volumes:
      - inventory-data:/data
    networks:
      - lab

volumes:
  inventory-data:

networks:
  frontend:
  lab:
    name: clab-mgmt
    external: true
```

**Was passiert:**
- `build: ./collector` baut das Image aus deinem Ordner statt es zu ziehen. Es heißt danach `inventory-collector`.
- `environment:` mit `${CEOS_USER}`: Compose setzt den Wert **beim Start** aus der Shell-Umgebung ein. Dafür hast du die `.env` vorher in die Shell geladen. So steht kein Passwort in der Compose-Datei, und die Datei darf ins Git.
- `INTERVAL: "30"` in Anführungszeichen, weil Umgebungsvariablen immer Strings sind.
- **Zwei Netze, getrennt:**
  - `frontend` ist ein eigenes Netz für `web`. Compose legt es an (`inventory_frontend`).
  - `lab` ist das **fremde** Netz `clab-mgmt` von containerlab (172.20.20.0/24), in dem ceos1/ceos2 hängen. `external: true` heißt: Compose legt es **nicht** an und löscht es nie, es muss schon existieren. `name:` ist der echte Docker-Name. `lab` ist nur der Name innerhalb dieser Datei.

### Schritt 4: Bauen und starten (Editor-Tab)

```bash
docker compose up -d --build
```

**Erwartet:** `Image inventory-collector Built`, danach `Recreated`/`Started` für beide. Der erste Build dauert etwa 30 s.

Ohne `--build` würde Compose ein schon gebautes Image wiederverwenden, auch wenn du `collector.py` geändert hast. Merke: **Code geändert → `--build`.**

### Schritt 5: Nachsehen

Im **Lab-Tab**:

```bash
docker compose ps --format "{{.Service}} {{.State}} {{.Networks}}"
docker compose logs collector
curl -s localhost:8080/inventory.json
```

Im **Browser**: `http://localhost:8080`

**Erwartet:**
- `collector running clab-mgmt` und `web running inventory_frontend`.
- Im Log steht `collected 2 devices, 0 errors`.
- Das JSON enthält beide cEOS mit Hostname, Seriennummer und Software.
- Im Browser siehst du die Tabelle „Lab-Inventar“. Nach 30 s ändert sich der Zeitstempel.

### Schritt 6: Fehlerfall – Umgebung fehlt

In einem **neuen** Terminal, also ohne geladene `.env`:

```bash
cd "$(git rev-parse --show-toplevel)/lab/compose/inventory"
docker compose up -d
sleep 35; docker compose logs collector --tail 1
```

**Erwartet:**
- Zwei Warnungen `The "CEOS_USER" variable is not set. Defaulting to a blank string.` (dasselbe für `CEOS_PASSWORD`).
- Der collector wird mit **leeren** Zugangsdaten neu erzeugt. Im Log steht danach `collected 2 devices, 2 errors`, und die Webseite zeigt `401 … Unauthorized`.

Compose bricht hier **nicht** ab, es warnt nur. Lies die Warnungen!

Zum Reparieren im Editor-Tab wieder `docker compose up -d`, dort ist die `.env` geladen. Das zweite Terminal kannst du schließen.

### Schritt 7: Was `config` verrät

Im Editor-Tab:

```bash
docker compose config
```

**Erwartet:** unter `environment:` steht `CEOS_PASSWORD: admin` im **Klartext**. `docker compose config` zeigt die aufgelöste Konfiguration mit allen Secrets. Ausgaben davon nie in Tickets oder Logs kopieren (Blueprint 3.6). Für echte Secrets gibt es `secrets:`. Die Lese-Aufgabe in Teil G zeigt die Form.

> [!question]- Selbsttest Teil C
> 1. Der collector soll künftig auch `172.20.20.21` (srl1) abfragen. Wo änderst du das, ohne das Image neu zu bauen?
> 2. Warum steht `clab-mgmt` unter `name:` und nicht direkt als Netzname?
>
> **Lösung:**
> 1. In `compose.yaml` unter `collector: environment:` ergänzt du `DEVICES: "172.20.20.11,172.20.20.12,172.20.20.21"` und startest mit `docker compose up -d` (ohne `--build`). srl1 erscheint dann mit Fehler, weil SR Linux kein RESTCONF hat. Der Rest läuft weiter.
> 2. Der Schlüssel unter `networks:` (`lab`) ist ein **lokaler Name** in dieser Datei. `name:` ist der echte Docker-Name. Ohne `name:` würde Compose ein Netz `inventory_lab` suchen bzw. anlegen. `external: true` heißt außerdem: nicht anlegen, nicht löschen.

## 6. Teil D: Betrieb – Healthcheck, Startreihenfolge, Neustart, Netztrennung

### Schritt 1: Die Datei für den Betrieb

`compose.yaml` ganz ersetzen:

```yaml
services:
  web:
    image: nginx:1.27-alpine
    ports:
      - "0.0.0.0:8080:80"
    volumes:
      - inventory-data:/usr/share/nginx/html:ro
    networks:
      - frontend
    depends_on:
      collector:
        condition: service_healthy
    restart: unless-stopped

  collector:
    build: ./collector
    environment:
      CEOS_USER: ${CEOS_USER}
      CEOS_PASSWORD: ${CEOS_PASSWORD}
      INTERVAL: "30"
    volumes:
      - inventory-data:/data
    networks:
      - lab
    healthcheck:
      test: ["CMD", "test", "-s", "/data/inventory.json"]
      interval: 10s
      retries: 6
    restart: unless-stopped

volumes:
  inventory-data:

networks:
  frontend:
  lab:
    name: clab-mgmt
    external: true
```

**Was passiert:**
- `healthcheck` im collector prüft alle 10 s, ob `/data/inventory.json` existiert und nicht leer ist (`test -s`). Nach bis zu 6 Fehlversuchen gilt er als `unhealthy`.
- `depends_on … condition: service_healthy`: `web` startet erst, wenn der collector **gesund** ist. Ohne `condition` hieße es nur „erst starten“, nicht „erst bereit“.
- `restart: unless-stopped`: Docker startet den Container nach einem Absturz oder Neustart des Docker-Dienstes wieder, außer du hast ihn selbst gestoppt.

### Schritt 2: Starten (Editor-Tab)

```bash
docker compose up -d --build
```

**Erwartet:** in dieser Reihenfolge `collector Started` → `collector Waiting` → `collector Healthy` → `web Started`. `docker compose ps` zeigt `collector … (healthy)`.

### Schritt 3: Absturz simulieren (Lab-Tab)

```bash
docker kill inventory-collector-1
sleep 5; docker inspect inventory-collector-1 --format "{{.State.Status}} restarts={{.RestartCount}}"
```

**Erwartet:** `exited restarts=0`. **Kein** Neustart! `docker kill` zählt als **manueller** Stopp, und `unless-stopped` respektiert das.

Jetzt ein echter Absturz: Der Prozess stirbt von außen, ohne dass Docker gefragt wurde.

```bash
docker start inventory-collector-1
sleep 3; sudo kill -9 $(docker inspect -f "{{.State.Pid}}" inventory-collector-1)
sleep 5; docker inspect inventory-collector-1 --format "{{.State.Status}} restarts={{.RestartCount}}"
```

**Was passiert:** `docker inspect -f "{{.State.Pid}}"` liefert die Prozess-ID des Containers auf dem Host. `kill -9` beendet ihn hart, so wie ein Absturz.

**Erwartet:** `running restarts=1`. Docker hat ihn selbst wieder gestartet.

### Schritt 4: Netztrennung prüfen (Lab-Tab)

```bash
docker compose exec web ping -c1 -W2 collector
docker compose exec web nc -zv -w3 172.20.20.11 6020
sudo iptables -S DOCKER-USER
```

**Erwartet:**
1. `ping: bad address 'collector'`: `web` (Netz `frontend`) kann den Namen `collector` (Netz `clab-mgmt`) **nicht auflösen**. Ohne gemeinsames Netz gibt es keinen gemeinsamen DNS.
2. `172.20.20.11 (172.20.20.11:6020) open`: **per IP** kommt `web` trotzdem bis zu ceos1!
3. Zwei Regeln `-j ACCEPT` mit dem Kommentar `set by containerlab`.

**Warum?** Docker trennt Netze auf zwei Ebenen: **DNS** (Namen nur im eigenen Netz) und **iptables** (Pakete zwischen Bridges verboten). containerlab öffnet in der Kette `DOCKER-USER` bewusst seine Management-Bridge für Zugriffe von außen, und damit auch für jeden anderen Container. Netztrennung ist also nur so gut wie die Firewall-Regeln auf dem Host. Für die Prüfung zählt die Regel: **Services sehen sich nur in gemeinsamen Netzen.** Für die Praxis gilt: Prüfen, nicht glauben.

> [!question]- Selbsttest Teil D
> 1. Was ist der Unterschied zwischen `depends_on: [collector]` und `depends_on: collector: condition: service_healthy`?
> 2. Welche `restart`-Policy startet einen Container auch nach `docker stop` und einem Neustart des Docker-Dienstes wieder?
>
> **Lösung:**
> 1. Die kurze Form wartet nur, bis der Container **gestartet** ist. Die lange wartet, bis sein Healthcheck **gesund** meldet. Eine Datenbank, die schon läuft, aber noch keine Verbindungen annimmt, ist der klassische Fall dafür.
> 2. `always`. `unless-stopped` merkt sich den manuellen Stopp, `on-failure` greift nur bei Exit-Code ≠ 0, `no` nie.

## 7. Teil E: `links` – die Altlast verstehen

Die Prüfung nennt `links` ausdrücklich. Du baust es einmal ein und siehst, was es wirklich tut.

### Schritt 1: `links` über Netzgrenzen

In `compose.yaml` bei `web` unter `restart: unless-stopped` ergänzen:

```yaml
    links:
      - collector:inv
```

Editor-Tab: `docker compose up -d`. Dann im Lab-Tab:

```bash
docker compose exec web sh -c "getent hosts inv || echo no-inv; getent hosts collector || echo no-collector"
```

**Was passiert:** `collector:inv` heißt „Service `collector`, zusätzlich erreichbar als `inv`“.

**Erwartet:** `no-inv` und `no-collector`. Compose hat `links` **ohne Fehler** angenommen, es wirkt aber nicht, weil `web` und `collector` kein gemeinsames Netz haben.

### Schritt 2: Gemeinsames Netz

Bei `web` unter `networks:` zusätzlich `- lab` eintragen, sodass dort `- frontend` und `- lab` stehen. `up -d`, dann noch einmal:

```bash
docker compose exec web sh -c "getent hosts inv; getent hosts collector"
```

**Erwartet:** zweimal dieselbe IP aus 172.20.20.0/24, für `inv` **und** `collector`.

### Schritt 3: Ohne `links`

Die beiden `links`-Zeilen wieder löschen (**^K** zweimal), `- lab` bei `web` lassen, `up -d`:

```bash
docker compose exec web sh -c "getent hosts collector; getent hosts inv || echo no-inv"
```

**Erwartet:** `collector` wird aufgelöst, `inv` nicht mehr.

**Fazit:** Den **Servicenamen** liefert das gemeinsame Netz von selbst. `links` gibt nur einen **zusätzlichen Alias** (und eine Startreihenfolge). Moderne Form dafür:

```yaml
    networks:
      lab:
        aliases:
          - inv
```

(im Service, der den Alias **bekommt**, hier `collector`.)

Zum Schluss `web` wieder nur in `frontend` hängen (`- lab` bei `web` löschen) und `up -d`. So ist der Stand wie nach Teil D.

> [!question]- Selbsttest Teil E
> In einer fremden Datei steht bei `app` der Eintrag `links: - db:postgres`. Unter welchen Namen erreicht `app` die Datenbank, und was muss dafür noch gelten?
>
> **Lösung:** Unter `db` (Servicename) und `postgres` (Alias), aber nur, wenn `app` und `db` mindestens ein **gemeinsames Netz** haben. Ohne gemeinsames Netz wirkt der Link nicht, und Compose meldet das nicht einmal.

## 8. Teil F: Fehlerbilder lesen

### Schritt 1: Einrückung

Im Editor-Tab eine kaputte Kopie anlegen und prüfen:

```bash
sed "s/^    image: nginx/   image: nginx/" compose.yaml > bad1.yaml
docker compose -f bad1.yaml config
```

**Was passiert:** `sed` nimmt vor `image: nginx` ein Leerzeichen weg (3 statt 4). `-f` wählt eine andere Datei als `compose.yaml`.

**Erwartet:** `yaml … load error … L4.C10: mapping values are not allowed in this context`. Zeile 4, Spalte 10: Dort sieht YAML ein `:`, wo es keins erwartet, weil die Einrückung nicht mehr zur Ebene passt. Mit nano springst du mit **^_ 4** direkt hin.

### Schritt 2: Externes Netz fehlt

```bash
sed "s/name: clab-mgmt/name: clab-mgmnt/" compose.yaml > bad2.yaml
docker compose -f bad2.yaml up -d
```

**Erwartet:** `network clab-mgmnt declared as external, but could not be found`. Dieselbe Meldung kommt mit dem richtigen Namen, wenn das **Lab gerade nicht läuft**. Ohne `sudo containerlab deploy` gibt es `clab-mgmt` nicht.

Danach die Kopien löschen: `rm bad1.yaml bad2.yaml`.

> [!question]- Selbsttest Teil F
> `docker compose up` meldet `service "web" refers to undefined volume inventory-dat`. Was ist kaputt?
>
> **Lösung:** Ein Tippfehler im Volume-Namen beim Service (`inventory-dat` statt `inventory-data`). Jedes benannte Volume, das ein Service nutzt, muss oben unter `volumes:` deklariert sein. Compose prüft das vor dem Start.

## 9. Teil G: Eine fremde Compose-Datei lesen (prüfungsnah)

In der Prüfung bekommst du eine Datei und Fragen dazu. Lies diese **ohne sie zu starten** und beantworte die Fragen auf Papier.

```yaml
# Lese-Aufgabe: fremder Stack (nicht starten, nur lesen)
services:
  app:
    image: netboxcommunity/netbox:v4.4
    depends_on:
      - db
      - cache
    env_file: netbox.env
    ports:
      - "127.0.0.1:8000:8080"
    volumes:
      - media:/opt/netbox/netbox/media
      - ./config:/etc/netbox/config:ro
    networks:
      - front
      - back
    links:
      - db:postgres

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: netbox
      POSTGRES_USER: netbox
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pw
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - back
    restart: always

  cache:
    image: valkey/valkey:8-alpine
    command: valkey-server --appendonly yes
    networks:
      back:
        aliases:
          - redis

volumes:
  media:
  pgdata:
    external: true

networks:
  front:
  back:
    internal: true
```

1. Wie viele Container entstehen, und in welcher Reihenfolge starten sie?
2. Von wo ist NetBox erreichbar, und auf welchem Port im Container lauscht es?
3. Unter welchen Namen erreicht `app` die Datenbank und den Cache?
4. Kann `db` ins Internet, zum Beispiel für Updates aus dem Container heraus?
5. Welche Daten überleben `docker compose down -v`, und warum?
6. Was passiert beim ersten `docker compose up` auf einem neuen Host?
7. Welches Volume ist ein Bind-Mount, und was bedeutet `:ro`?
8. Was fehlt, damit `POSTGRES_PASSWORD_FILE` funktioniert?

> [!example]- Lösung Teil G (Datei mit `docker compose config` am 30.10. auf Gültigkeit geprüft)
> 1. **Drei** (`app`, `db`, `cache`). `db` und `cache` starten zuerst, `app` danach (`depends_on`). Ob die Datenbank dann schon Verbindungen annimmt, ist **nicht** garantiert, dafür fehlt `condition: service_healthy`.
> 2. Nur **vom Host selbst** (`127.0.0.1:8000`), typisch hinter einem Reverse-Proxy auf demselben Host. Im Container lauscht NetBox auf **8080**.
> 3. Datenbank: `db` und `postgres` (Alias über `links`, wirksam, weil beide im Netz `back` sind). Cache: `cache` und `redis` (Netz-Alias).
> 4. **Nein.** `back` ist `internal: true`, also ohne Gateway nach draußen. `db` hängt nur dort. `app` kommt über `front` raus.
> 5. **`pgdata`**, weil es `external: true` ist. Compose hat es nicht angelegt und löscht es auch nicht. `media` wird mit `-v` gelöscht. `./config` ist ein Ordner auf dem Host und bleibt immer.
> 6. Es **bricht ab**: Das externe Volume `pgdata` existiert noch nicht (`external volume "pgdata" not found`). Es muss vorher mit `docker volume create pgdata` angelegt werden.
> 7. `./config:/etc/netbox/config:ro` ist ein Bind-Mount (beginnt mit `./`). `:ro` heißt nur lesen: Der Container kann die Konfiguration nicht verändern.
> 8. Ein `secrets:`-Block. Oben `secrets: db_pw: file: ./db_pw.txt` und beim Service `db` dazu `secrets: [db_pw]`. Dann legt Compose die Datei unter `/run/secrets/db_pw` in den Container, statt das Passwort als Umgebungsvariable sichtbar zu machen (vgl. Teil C, Schritt 7).

## Prüfungsfragen

1. Benanntes Volume oder Bind-Mount: Woran erkennst du was, und was überlebt `down -v`?
2. Was bedeutet `external: true` bei Netzen und bei Volumes?
3. Wann erreichen sich zwei Services per Namen?
4. Was macht `links`, und was ist die moderne Alternative?
5. `"8080:80"` gegen `"127.0.0.1:8080:80"`: Wer kommt jeweils ran?
6. Wann brauchst du `up --build`?
7. Wie kommen Secrets in einen Container, ohne in der Compose-Datei zu stehen, und wo tauchen sie trotzdem auf?
8. `depends_on` mit und ohne `condition`: Wo ist der Unterschied?

## Aufräumen

Im Editor-Tab:

```bash
docker compose down -v
```

**Erwartet:** Container, das Netz `inventory_frontend` und das Volume werden gelöscht. Das Netz `clab-mgmt` **bleibt**, weil es `external` ist. Das Lab läuft weiter.

Ein Rest bleibt trotzdem: das Netz **`inventory_default`** aus Teil A/B. Ab Teil C verwendet die Datei es nicht mehr, und `down` räumt nur Netze auf, die **in der aktuellen Datei** stehen. Im Lab-Tab:

```bash
docker network ls | grep inventory
docker network rm inventory_default
```

Lehre: Wer die Netze in einer Compose-Datei umbaut, sollte vorher `down` machen, sonst bleiben Waisen liegen.

Deine Dateien in `lab/compose/inventory/` bleiben lokal. `docker compose up -d --build` baut alles wieder auf.
