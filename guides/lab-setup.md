---
title: Lab-Einrichtung
---

Das Lab für die [RESTCONF-Anleitung](restconf.md) und die [Compose-Anleitung](docker-compose.md): zwei Arista cEOS und ein Nokia SR Linux in [ContainerLab](https://containerlab.dev/). Die Topologie liegt im Repo [autocor-lab](https://github.com/silvan-devnet/autocor-lab) unter `lab/clab/`.

## Was du brauchst

- Einen **Linux-Host** (x86-64, VM genügt) mit etwa 8 GB freiem RAM, Docker und ContainerLab.
- Das **cEOS-Image** `cEOS-lab-4.32.0F`. Es darf nicht weitergegeben werden: Du lädst es nach einer kostenlosen Registrierung bei [arista.com](https://www.arista.com/en/support/software-download) selbst und importierst es:

```bash
docker import cEOS-lab-4.32.0F.tar.xz ceos:4.32.0F
```

Das SR-Linux-Image ist frei und wird beim Start automatisch geladen.

## Lab starten

```bash
git clone https://github.com/silvan-devnet/autocor-lab.git
cd autocor-lab/lab/clab
sudo containerlab deploy
./restconf-cert.sh
```

**Erwartet:** `ceos1: RESTCONF running on 6020` und `ceos2: RESTCONF running on 6020`.

| Gerät | Mgmt-IP | RESTCONF |
|---|---|---|
| ceos1 | 172.20.20.11 | `https://172.20.20.11:6020/restconf/data` |
| ceos2 | 172.20.20.12 | `https://172.20.20.12:6020/restconf/data` |
| srl1 | 172.20.20.21 | – |

Die Mgmt-Adressen sind nur auf dem Lab-Host erreichbar. Die Anmeldung ist der ContainerLab-Standard `admin` / `admin`, nur für dieses Wegwerf-Lab.

## Zugangsdaten als `.env`

Lege im Hauptordner des Repos eine `.env` an (sie ist per `.gitignore` ausgeschlossen):

```bash
CEOS_USER=admin
CEOS_PASSWORD=admin
```

## Python-Umgebung

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install requests pyyaml
```

## Zwei Terminal-Tabs

Die Anleitungen arbeiten mit zwei Tabs auf dem Lab-Host:

| Tab | Wofür |
|---|---|
| **Editor-Tab** | Dateien schreiben und Skripte starten |
| **Lab-Tab** | nachsehen: `curl`, `docker compose ps`, `logs`, `exec` |

Du kannst mit einem Tab auskommen, zwei sind nur übersichtlicher.

## Aufräumen

```bash
cd lab/clab
sudo containerlab destroy --cleanup
```
