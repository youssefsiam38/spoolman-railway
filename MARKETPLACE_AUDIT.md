# Marketplace audit

Why this template was built, recorded at the time of publication.

## Gap

Searching the Railway marketplace returned nothing for 3D-printing filament inventory:

| Query | Result |
|---|---|
| `spoolman` | no match |
| `filament`, `3d printing` | no match |
| `octoprint`, `klipper`, `moonraker` | no match |

The scan covered roughly seventy self-hosted applications. Most popular categories are already
served several times over; this one is empty.

## Why Spoolman

- Actively maintained, tagged releases, official multi-arch images on GHCR.
- MIT, so redistribution is simple and the obligations are minimal.
- Self-contained: SQLite in one directory, no companion database.
- Fits Railway's model exactly: one public HTTP service with one volume.
- Genuinely useful remotely. A filament inventory is worth reaching from a phone, from a slicer on
  another machine, and from printers that are not on the same network, which is precisely the case
  the upstream project does not serve.

## Why it needs a template rather than a raw image

- **Spoolman has no authentication.** Upstream's own words: the network is the boundary protecting
  the data. Railway removes that boundary by handing out a public URL, so the stock image deployed
  as-is is a writable database on the open internet. The template supplies the missing front door.
- Railway mounts volumes as root while Spoolman runs as uid 1000 and never chowns its data
  directory, so a fresh volume is read-only to it.
- Railway probes its healthcheck against `PORT`, so the listening port has to be pinned to match.

The template answers all three without asking the deployer anything.

## Category

Other — the marketplace has no maker, hardware or inventory category; the template is a
self-hosted personal database with a web UI.
