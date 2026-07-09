# Immich Homelab Photo-Backup Server — Design

**Date:** 2026-06-30
**Status:** Approved design, ready for implementation planning

---

## 1. Purpose

Replace paid Google Photos storage with a self-hosted photo-backup server for a
household of 2–3 people. The server runs on an old all-in-one PC that is **not on
all day**: it powers itself on at a set time each evening, lets family phones back
up that day's photos over the home network, processes them (face recognition,
search indexing), and then powers itself back off when idle.

### Success criteria

- Each family member's Android phone auto-backs-up its camera photos to the server
  during the nightly window, over the LAN.
- Other media (WhatsApp, screenshots, etc.) can be backed up manually/selectively.
- If the server misses a night, no photos are lost — they back up next time the
  server is reachable, or on a manual sync.
- The server wakes itself for the backup window and shuts itself down afterward,
  **without ever powering off while someone is using the desktop or while an upload
  is in progress.**
- Google-Photos-like experience: web/mobile UI, per-person libraries, per-device
  visibility, face recognition, smart search, map, albums, memories.
- Secure remote *viewing* from anywhere with no ports exposed to the internet.
- A manual, on-demand way to export the whole archive to an external USB drive.

### Non-goals (v1)

- No automatic/continuous mirror to a second drive (export is manual, on demand).
- No HTTPS / browser padlock (traffic is already encrypted over Tailscale).
- No second always-on helper device (e.g. Raspberry Pi).
- No iOS support needed — household is all-Android.

---

## 2. Environment

- **Server:** old all-in-one PC, Intel Core i3 M 380 (2 cores / 4 threads, ~2.53 GHz,
  no AVX), **8 GB RAM**, single internal drive, running **Debian 13 with GUI** (still
  occasionally used as a normal desktop).
- **Clients:** 2–3 Android phones.
- **Authoring machine:** a separate Debian 12 box (this is where config files are
  written, then transferred to the server). Every config file in this repo carries a
  header comment stating its intended path/name on the Debian 13 server.

---

## 3. Chosen approach

Self-host **Immich** (mature open-source Google-Photos alternative) via **Docker
Compose**, wrapped by a thin custom host-management layer for the "sometimes-on"
behavior, and **Tailscale** for free secure remote access.

Rejected alternatives:
- *Build from scratch* — months of work to match face recognition, ML search, and
  mobile apps. Not justified.
- *Native (non-Docker) Immich* — Immich is only officially supported via Docker;
  native installs break on updates.
- *Add an always-on helper device for Wake-on-LAN* — unnecessary given RTC self-wake.

---

## 4. Architecture

Two layers on the one Debian 13 PC, plus an access layer.

### Layer 1 — Immich application stack (Docker Compose)

| Container | Role |
|-----------|------|
| `immich-server` | Web UI, API, upload endpoint |
| `immich-machine-learning` | Face recognition + smart search (CPU-only) |
| `redis` | Job queue |
| `postgres` (pgvector) | Metadata: albums, faces, device info, users |

Photo originals are stored as **plain files** on disk at `UPLOAD_LOCATION`
(`/photos`), independent of the database, so images remain accessible even without
Immich.

### Layer 2 — "Sometimes-on" host management (custom, lightweight)

1. **Wake scheduler** — programs the hardware RTC alarm
   (`/sys/class/rtc/rtc0/wakealarm`) for the next backup time. Runs **at shutdown**
   (arms next occurrence) and **at boot** (re-asserts), so the alarm is always armed
   regardless of how the machine was powered off. Default wake: **21:00 (9:00 PM)**.
2. **Auto-shutdown guard** — a systemd timer (~every 10 min) that powers the PC off
   **only when all** of: past the backup window (machine up ≥ ~45 min since a
   scheduled wake), no active user input at the desktop, and no Immich upload/processing
   jobs in progress. Otherwise it does nothing and re-checks next cycle.
3. **Manual export script** (`immich-export.sh`) — run by hand when the external USB
   drive is plugged in; dumps Postgres and `rsync`-mirrors `/photos` + the dump to the
   drive.

### Access layer — Tailscale

- Tailscale on the server provides a stable MagicDNS name used as the **single Immich
  server URL** on every phone.
- **At home:** Tailscale routes directly over the LAN (full Wi-Fi speed) — nightly
  uploads are local and fast.
- **Away:** the same name routes over Tailscale's encrypted tunnel for **viewing**.
- A **static local IP** (router DHCP reservation or static config) is set as a reliable
  LAN fallback address.
- **No router port-forwarding** — nothing exposed to the internet.

### Data flow

```
Phone (Immich app) --upload over LAN/Tailscale--> immich-server
    --> writes original file to /photos
    --> writes metadata to postgres
    --> enqueues jobs in redis --> immich-machine-learning (faces, search) in background
```

### Power lifecycle (each cycle)

```
RTC alarm fires (21:00) -> PC powers on -> Docker + Immich auto-start
  -> phones detect server on LAN, upload new photos
  -> ML processes faces/search in background
  -> guard: past window AND nobody at desktop AND uploads idle
  -> arm tomorrow's RTC alarm -> shutdown
```

---

## 5. Component details

### 5.1 Power lifecycle

- **One-time BIOS setup (manual, on server):** enable "Wake on RTC / RTC Alarm /
  Auto Power-On."
  - **Fallback if BIOS lacks RTC wake:** use **suspend** instead of full power-off;
    the kernel RTC alarm wakes from suspend very reliably (tiny standby power draw).
- **Wake scheduler:** systemd service triggered on shutdown and on boot; computes the
  next 21:00 and writes the epoch time to the RTC wakealarm.
- **Auto-shutdown guard conditions (all required):**
  - Uptime since boot ≥ ~45 min (let phones connect/upload) — tunable.
  - **No active user input** — detected via session idle time, so a family member
    using the desktop (or present after an auto-wake) prevents shutdown.
  - **No active Immich jobs** — uploads/processing idle (queried from Immich).
  - Conservative by design: failing any check means "stay on"; worst case is staying
    on too long, which is harmless.

### 5.2 Backup behavior (mostly stock Immich)

- **Automatic:** Immich Android app with auto-backup ON, triggered on **Wi-Fi +
  charging**, camera folder selected. Uploads are **incremental/idempotent** — only
  new assets are sent.
- **Manual / other media:** user selects extra folders or individual items to upload
  on demand; can also open the app and sync any time the server is up.
- **Catch-up (no custom code):** missed nights are self-correcting — the phone uploads
  the backlog the next time it reaches the server (next window or manual sync).
- **Per-device organization:** Immich tags each asset with its source device; each
  family member has a separate account/library (per-person separation + per-device
  visibility/filtering).

### 5.3 Storage, redundancy & manual export

- **Single internal drive:** `/photos` (originals) + Postgres (metadata).
- **Known risk (accepted):** with one drive and no auto-mirror, a drive failure loses
  any photos that exist *only* on the server (deleted from phone, not yet exported).
  Phones act as a rolling buffer, so exposure ≈ "photos deleted from phone since last
  export." Mitigated by running the manual export periodically.
- **`immich-export.sh`:** (1) dumps the Postgres DB (so albums/faces/metadata are
  restorable), (2) `rsync`-mirrors `/photos` + the dump to the external USB drive
  (incremental; fast on repeat), (3) prints a summary (files copied, total size, DB
  dump timestamp). Manual and on-demand only — no concurrent/automatic mirroring.
- **Optional later:** a passive "it's been N weeks since last export" desktop reminder
  (no automatic copying). Out of scope for v1.

### 5.4 Networking & access

- Tailscale MagicDNS name as the single server URL on all phones; Tailscale always-on.
- Static local IP as LAN fallback.
- No HTTPS in v1 (Tailscale encrypts); optional Tailscale-issued cert later.
- No port-forwarding.

### 5.5 Users, devices & ML

- Admin account (owner) created first; then 2–3 member accounts. Optional per-user
  storage quota (off by default).
- Per phone: install Immich app, log in, set server URL, enable auto-backup
  (Wi-Fi + charging), select extra folders for manual backup.
- **Face recognition + smart search** via the ML container (CPU-only, no GPU).
  Additional stock features: map view (GPS), memories/"on this day", shared albums,
  duplicate detection.
- All containers run with `restart: always` so Immich returns automatically on every
  wake; queued ML jobs persist and resume across reboots.

### 5.6 ML resource tuning (for the old CPU)

- 8 GB RAM is comfortable for the full stack including ML (~2–3 GB ML when active).
- 2 old cores → ML is slow but non-blocking. The **initial pass** over the existing
  library spans several nightly windows; daily new photos process quickly.
- **Job concurrency = 1** for face detection and smart search → steady low CPU, UI stays
  responsive.
- **Docker memory limit** on the ML container so it can't starve the system.
- Default (lighter) models; option to disable smart search and keep only face
  recognition (or vice-versa) if desired. No AVX → ML runs in slower compatibility mode
  (expected, nothing to configure).

---

## 6. Error handling

| Scenario | Behavior |
|----------|----------|
| Container crash / reboot | `restart: always` recovers; ML jobs resume |
| Missed night (BIOS/power) | No data loss; phones catch up next window or manual sync; can power on by hand |
| Auto-shutdown vs. active use | Guard is conservative — never powers off during use or upload |
| Power loss mid-write | Postgres journaling protects DB; manual export is a restore point |

---

## 7. Testing plan

(Commands provided for the Debian 13 server.)

- **Wake:** arm RTC alarm ~2 min out, power off, confirm self power-on.
- **Auto-shutdown guard:** dry-run under simulated states — (a) active desktop session
  → must NOT shut down, (b) active uploads → must NOT shut down, (c) idle + past window
  → shuts down.
- **Backup:** new photo on a phone appears on the server at next window.
- **Face recognition:** faces detected; name a person; search by them.
- **Manual export + restore dry-run:** run `immich-export.sh` to USB, then restore the
  dump into a throwaway Immich instance to prove the backup is restorable.
- **Remote view:** disable phone Wi-Fi, confirm browsing works over Tailscale (cellular).

---

## 8. Deliverables (config files in this repo)

Each file includes a header noting its server path. Anticipated:

- `config/docker-compose.yml` — Immich stack (→ e.g. `/opt/immich/docker-compose.yml`)
- `config/.env` — Immich env (`UPLOAD_LOCATION=/photos`, DB creds, ML settings)
- `config/immich-wake.service` + script — RTC wake scheduler (systemd)
- `config/immich-autoshutdown.service` + `.timer` + guard script — auto-shutdown
- `config/immich-export.sh` — manual external-drive export
- Setup checklists: BIOS RTC wake, static IP, Tailscale, Android app config.

Final file list and contents are produced during implementation planning.
