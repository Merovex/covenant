#!/usr/bin/env bash
#
# Provision persistent storage for the Covenant Kamal deployment.
#
# Creates the bind-mount directories referenced in config/deploy.yml, owned by
# the container's uid/gid (1000) so the app can write to them:
#   /var/lib/covenant        -> /rails/storage (SQLite DBs + Active Storage)
#   /var/lib/covenant/logs   -> /rails/log
#
# ── HOW TO RUN ────────────────────────────────────────────────────────────────
# Run this ONCE per server, as root, BEFORE the first `bin/kamal setup`. Easiest
# is to pipe this local file straight into the server's root shell (no copy):
#
#     ssh root@5.161.252.146 'bash -s' < bin/provision-storage.sh
#
# Or copy it up and run it there:
#
#     scp bin/provision-storage.sh root@5.161.252.146:/tmp/
#     ssh root@5.161.252.146 bash /tmp/provision-storage.sh
#
# Or, if you're already on the box (ssh root@5.161.252.146):
#
#     bash provision-storage.sh
#
# Idempotent — safe to re-run. After it succeeds, proceed with `bin/kamal setup`.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

BASE=/var/lib/covenant
APP_UID=1000
APP_GID=1000

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

echo "Creating $BASE and $BASE/logs ..."
mkdir -p "$BASE/logs"

echo "Setting ownership to $APP_UID:$APP_GID ..."
chown -R "$APP_UID:$APP_GID" "$BASE"

echo "Setting permissions to 750 ..."
chmod -R 750 "$BASE"

echo
echo "Done. Current state:"
ls -ld "$BASE" "$BASE/logs"
