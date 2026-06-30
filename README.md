# Homelab Immich Photo-Backup Server

Config + scripts for a self-hosted Immich server on an old all-in-one Ubuntu PC
that auto-wakes at 21:00 for backups and auto-shuts-down when idle.

- Design spec: `docs/superpowers/specs/2026-06-30-immich-homelab-photo-backup-design.md`
- Implementation plan: `docs/superpowers/plans/2026-06-30-immich-homelab-photo-backup.md`
- Server-bound files live in `config/` (each has a header with its server path).
- Setup checklists (run on the server): `docs/setup/`.
- Run logic tests: `bash tests/run.sh`

Files are authored here, then copied to the Ubuntu server. See `docs/setup/`.
