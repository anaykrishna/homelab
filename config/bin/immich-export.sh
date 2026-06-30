#!/usr/bin/env bash
# Server path: /usr/local/bin/immich-export.sh
# Manual, on-demand export of the whole Immich archive to an external USB drive.
# Usage: immich-export.sh /media/<you>/<DRIVE>
# Dumps Postgres (so albums/faces/metadata are restorable), then rsync-mirrors photos.
# Set DRY_RUN=1 to preview (rsync --dry-run, no DB dump).
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/immich/.env}"
PG_CONTAINER="${PG_CONTAINER:-immich_postgres}"

build_dump_name() { echo "immich-db-$1.sql.gz"; }

# main path only when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  DEST="${1:?Usage: immich-export.sh /path/to/external/drive}"
  [[ -d "$DEST" ]] || { echo "ERROR: destination '$DEST' is not a mounted directory"; exit 1; }

  # shellcheck source=/dev/null
  source "$ENV_FILE"
  : "${UPLOAD_LOCATION:?UPLOAD_LOCATION not set in $ENV_FILE}"

  OUT="$DEST/immich-backup"
  mkdir -p "$OUT"
  ts=$(date +%Y%m%d-%H%M)
  dump_name="$(build_dump_name "$ts")"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[export] DRY_RUN: skipping DB dump"
    rsync -a --dry-run --delete "$UPLOAD_LOCATION/" "$OUT/photos/"
    echo "[export] DRY_RUN complete (no changes written)"
    exit 0
  fi

  echo "[export] dumping database -> $OUT/$dump_name"
  docker exec -t "$PG_CONTAINER" pg_dumpall --clean --if-exists --username="$DB_USERNAME" \
    | gzip > "$OUT/$dump_name"

  echo "[export] mirroring photos -> $OUT/photos/"
  rsync -a --delete --info=stats2 "$UPLOAD_LOCATION/" "$OUT/photos/"

  photo_count=$(find "$OUT/photos" -type f | wc -l)
  total_size=$(du -sh "$OUT" | awk '{print $1}')
  echo "--------------------------------------------"
  echo "[export] DONE"
  echo "  DB dump:     $dump_name"
  echo "  photo files: $photo_count"
  echo "  total size:  $total_size"
  echo "  location:    $OUT"
fi
