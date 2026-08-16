#!/usr/bin/env bash
# Install or refresh the passive HA components on a Debian jump server.
set -euo pipefail

readonly project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly role_file="/etc/jumpserver-ha/role.conf"
role=""
active_address=""
ssh_port="42202"
vip=""

usage() {
  cat <<'EOF'
Usage: install.sh --role standby --active-address ADDRESS --vip VIP [--ssh-port PORT]

This installer is intentionally limited to the passive node. It installs or
updates the passive synchronization service, its runbook/login banner and the
HA update-check timer. Existing key material and pinned host keys are preserved.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) role="${2:-}"; shift 2 ;;
    --active-address) active_address="${2:-}"; shift 2 ;;
    --ssh-port) ssh_port="${2:-}"; shift 2 ;;
    --vip) vip="${2:-}"; shift 2 ;;
    --upgrade) shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ "$role" == "standby" ]] || { echo "Only --role standby is currently supported." >&2; exit 2; }
[[ -n "$active_address" && -n "$vip" ]] || { usage >&2; exit 2; }
[[ "$ssh_port" =~ ^[0-9]{1,5}$ ]] || { echo "Invalid SSH port." >&2; exit 2; }

install -d -o root -g root -m 0750 /etc/jumpserver-ha /etc/jumpserver-ha/keys /var/lib/jumpserver-ha
cat >"$role_file" <<EOF
JUMPSERVER_HA_ROLE=standby
JUMPSERVER_HA_ACTIVE_ADDRESS=$active_address
JUMPSERVER_HA_SSH_PORT=$ssh_port
JUMPSERVER_HA_VIP=$vip
EOF
chmod 0640 "$role_file"

# Keep legacy paths as the operational source of truth for a non-disruptive
# migration of the existing shadow-s implementation.
install -d -o root -g root -m 0750 /etc/shadow-ha /etc/shadow-ha/keys /var/lib/shadow-ha-sync
if [[ ! -e /etc/shadow-ha/keys/sync_ed25519 || ! -e /etc/shadow-ha/master_known_hosts ]]; then
  echo "Missing existing standby SSH key or pinned master host key; refusing to create credentials." >&2
  exit 1
fi

install -o root -g root -m 0750 "$project_dir/bin/shadow-ha-sync" /usr/local/sbin/shadow-ha-sync
install -o root -g root -m 0755 "$project_dir/bin/jumpserver-ha-update" /usr/local/sbin/jumpserver-ha-update
install -o root -g root -m 0644 "$project_dir/systemd/shadow-ha-sync.service" /etc/systemd/system/shadow-ha-sync.service
install -o root -g root -m 0644 "$project_dir/systemd/shadow-ha-sync.timer" /etc/systemd/system/shadow-ha-sync.timer
install -o root -g root -m 0644 "$project_dir/systemd/jumpserver-ha-update.service" /etc/systemd/system/jumpserver-ha-update.service
install -o root -g root -m 0644 "$project_dir/systemd/jumpserver-ha-update.timer" /etc/systemd/system/jumpserver-ha-update.timer
install -o root -g root -m 0644 "$project_dir/docs/STANDBY-RUNBOOK.md" /etc/jumpserver-ha/README.md
install -o root -g root -m 0644 "$project_dir/docs/STANDBY-RUNBOOK.md" /etc/shadow-ha/README.md
install -o root -g root -m 0644 "$project_dir/VERSION" /etc/jumpserver-ha/version
install -o root -g root -m 0644 "$project_dir/templates/motd-standby" /etc/profile.d/99-shadow-ha-warning.sh
chmod 0644 /etc/profile.d/99-shadow-ha-warning.sh

systemctl daemon-reload
systemctl enable --now shadow-ha-sync.timer
# This only checks and records available releases. It never applies changes.
systemctl enable --now jumpserver-ha-update.timer
# A standby must never start GR operational automation because of installation.
systemctl disable --now gr-vendor-update.timer 2>/dev/null || true

echo "Installed passive HA components from $project_dir"
systemctl --no-pager --full is-active shadow-ha-sync.timer jumpserver-ha-update.timer
