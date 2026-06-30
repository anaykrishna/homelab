# 01 — Install Docker & Deploy Immich (run on the Ubuntu server)

1. Install Docker Engine + Compose plugin:
   `curl -fsSL https://get.docker.com | sh` then `sudo usermod -aG docker $USER` and re-login.
2. Create the layout:
   `sudo mkdir -p /opt/immich /photos /usr/local/lib/immich`
3. Copy from the authoring machine into place:
   - `config/docker-compose.yml` -> `/opt/immich/docker-compose.yml`
   - `config/.env.example` -> `/opt/immich/.env` (then edit: set a long random `DB_PASSWORD`, correct `TZ`)
   - `config/bin/*.sh` -> `/usr/local/bin/` (`chmod +x`)
   - `config/bin/lib/shutdown-decision.sh` -> `/usr/local/lib/immich/` 
   - `config/systemd/*` -> `/etc/systemd/system/`
4. Start Immich: `cd /opt/immich && docker compose up -d`
5. Open `http://<server-ip>:2283` and create the admin account.
