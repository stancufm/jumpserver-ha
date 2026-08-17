#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
role=""
active_address=""
ssh_port=22
vip=""
sync_interval='*-*-* *:0/5:00'
full_clone=false
sync_users_auto=true
sync_users=()
sync_paths=()
standby_public_key=""
active_known_hosts=""
enable_sync=false
install_dependencies=false
non_interactive=false
destdir=""

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]

Roles and pairing:
  --role active|standby
  --active-address HOST       physical address of the active peer (standby)
  --ssh-port PORT             active peer SSH port (default: 22)
  --vip ADDRESS               floating/HA address used for role fencing
  --standby-public-key PATH   standby synchronization public key (active)
  --active-known-hosts PATH   pinned active OpenSSH known_hosts file (standby)

Replication:
  --sync-path PATH            approved shared path; repeatable
  --sync-user USER            explicit human account; repeatable
  --no-auto-users             disable automatic /home user discovery
  --full-clone               clone local password state and complete user homes
  --sync-secrets             compatibility alias for --full-clone
  --sync-interval CALENDAR    systemd calendar for passive pull
  --enable-sync               enable standby pull/apply units after installation

Installation:
  --install-dependencies      install missing Debian dependencies
  --non-interactive           require every necessary value as an option
  --destdir PATH              staged/test installation; no users or systemd actions
  --help

Without --non-interactive, missing role, peer and trust information is requested
interactively. Package reconciliation is never applied by this installer.
EOF
}

while (($#)); do
  case "$1" in
    --role) role=${2:-}; shift 2 ;;
    --active-address) active_address=${2:-}; shift 2 ;;
    --ssh-port) ssh_port=${2:-}; shift 2 ;;
    --vip) vip=${2:-}; shift 2 ;;
    --sync-interval) sync_interval=${2:-}; shift 2 ;;
    --sync-path) sync_paths+=("${2:-}"); shift 2 ;;
    --sync-user) sync_users+=("${2:-}"); shift 2 ;;
    --no-auto-users) sync_users_auto=false; shift ;;
    --full-clone) full_clone=true; shift ;;
    --sync-secrets) full_clone=true; shift ;;
    --standby-public-key) standby_public_key=${2:-}; shift 2 ;;
    --active-known-hosts) active_known_hosts=${2:-}; shift 2 ;;
    --enable-sync) enable_sync=true; shift ;;
    --install-dependencies) install_dependencies=true; shift ;;
    --non-interactive) non_interactive=true; shift ;;
    --destdir) destdir=${2:-}; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

prompt_value() {
  local variable_name=$1 prompt=$2 default=${3:-} value
  read -r -p "$prompt${default:+ [$default]}: " value
  value=${value:-$default}
  printf -v "$variable_name" '%s' "$value"
}

prompt_boolean() {
  local variable_name=$1 prompt=$2 answer
  read -r -p "$prompt [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    printf -v "$variable_name" '%s' true
  else
    printf -v "$variable_name" '%s' false
  fi
}

if [[ -z "$role" && "$non_interactive" == false ]]; then
  prompt_value role 'Node role (active/standby)'
fi
[[ "$role" == active || "$role" == standby ]] || { echo 'Role must be active or standby.' >&2; exit 2; }

if [[ -z "$vip" && "$non_interactive" == false ]]; then
  prompt_value vip 'Floating/VIP address'
fi
if [[ "$role" == standby && -z "$active_address" && "$non_interactive" == false ]]; then
  prompt_value active_address 'Physical address of the active node'
fi
if [[ "$role" == standby && "$non_interactive" == false && "$enable_sync" == false ]]; then
  prompt_boolean enable_sync 'Enable passive synchronization after installation and trust validation?'
fi
if [[ "$non_interactive" == false && "$full_clone" == false ]]; then
  prompt_boolean full_clone 'Enable full clone of local password state and complete user homes?'
fi
if [[ ${#sync_paths[@]} -eq 0 ]]; then
  sync_paths=(/etc/gr /var/lib/gr/config-archive /var/lib/gr-collector)
fi

safe_host='^[A-Za-z0-9_.:-]+$'
[[ -n "$vip" && "$vip" =~ $safe_host ]] || { echo 'A safe VIP address is required.' >&2; exit 2; }
[[ "$ssh_port" =~ ^[0-9]+$ && "$ssh_port" -ge 1 && "$ssh_port" -le 65535 ]] || {
  echo 'SSH port must be between 1 and 65535.' >&2; exit 2;
}
if [[ "$role" == standby ]]; then
  [[ -n "$active_address" && "$active_address" =~ $safe_host ]] || {
    echo 'A safe active-node address is required on standby.' >&2; exit 2;
  }
fi
for path in "${sync_paths[@]}"; do
  [[ "$path" == /* && "$path" != / && "$path" != *'/../'* && "$path" != */.. \
     && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || {
    echo "Unsafe sync path: $path" >&2; exit 2;
  }
done
for user in "${sync_users[@]}"; do
  [[ "$user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || { echo "Unsafe sync user: $user" >&2; exit 2; }
done

if [[ -z "$destdir" && $(id -u) -ne 0 ]]; then
  echo 'Run as root, or use --destdir for a staged test.' >&2
  exit 2
fi
for input in "$standby_public_key" "$active_known_hosts"; do
  [[ -z "$input" || -r "$input" ]] || { echo "Cannot read trust input: $input" >&2; exit 2; }
done

required_packages=(bash openssh-client rsync tar gzip python3 systemd iproute2 util-linux)
if [[ "$role" == active ]]; then
  required_packages+=(openssh-server sudo)
fi
if [[ -z "$destdir" ]]; then
  missing=()
  for package in "${required_packages[@]}"; do
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qxF 'install ok installed' || missing+=("$package")
  done
  if ((${#missing[@]})) && [[ "$install_dependencies" == true ]]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
    missing=()
  fi
  ((${#missing[@]} == 0)) || {
    printf 'Missing Debian packages:' >&2; printf ' %s' "${missing[@]}" >&2; echo >&2
    echo 'Re-run with --install-dependencies to install them explicitly.' >&2
    exit 2
  }
fi

install -d -m 0755 "$destdir/usr/local/sbin" "$destdir/usr/local/libexec/shadow-ha" \
  "$destdir/etc/jumpserver-ha/keys" "$destdir/etc/systemd/system" \
  "$destdir/etc/profile.d" "$destdir/usr/local/share/doc/jumpserver-ha"
install -m 0755 "$project_dir/bin/shadow-ha-sync" "$destdir/usr/local/sbin/shadow-ha-sync"
install -m 0755 "$project_dir/bin/shadow-ha-apply" "$destdir/usr/local/sbin/shadow-ha-apply"
install -m 0755 "$project_dir/bin/shadow-ha-packages" "$destdir/usr/local/sbin/shadow-ha-packages"
install -m 0755 "$project_dir/bin/shadow-ha-export" "$destdir/usr/local/libexec/shadow-ha/export"
install -m 0755 "$project_dir/bin/jumpserver-ha-update" "$destdir/usr/local/sbin/jumpserver-ha-update"
for unit in shadow-ha-sync.service shadow-ha-sync.timer shadow-ha-apply.service shadow-ha-apply.path \
  jumpserver-ha-update.service jumpserver-ha-update.timer; do
  install -m 0644 "$project_dir/systemd/$unit" "$destdir/etc/systemd/system/$unit"
done
install -m 0755 "$project_dir/templates/motd-standby" "$destdir/etc/profile.d/99-shadow-ha-warning.sh"
install -m 0644 "$project_dir/docs/STANDBY-RUNBOOK.md" "$destdir/usr/local/share/doc/jumpserver-ha/STANDBY-RUNBOOK.md"
install -m 0644 "$project_dir/docs/SECURITY.md" "$destdir/usr/local/share/doc/jumpserver-ha/SECURITY.md"
install -m 0644 "$project_dir/VERSION" "$destdir/usr/local/share/doc/jumpserver-ha/VERSION"

cat > "$destdir/etc/jumpserver-ha/role.conf" <<EOF
JUMPSERVER_HA_ROLE=$role
JUMPSERVER_HA_ACTIVE_ADDRESS=$active_address
JUMPSERVER_HA_SSH_PORT=$ssh_port
JUMPSERVER_HA_VIP=$vip
JUMPSERVER_HA_EXPORT_USER=shadow-export
JUMPSERVER_HA_FULL_CLONE=$full_clone
JUMPSERVER_HA_SYNC_SECRETS=$full_clone
EOF
chmod 0644 "$destdir/etc/jumpserver-ha/role.conf"
printf '%s\n' "${sync_paths[@]}" > "$destdir/etc/jumpserver-ha/sync-paths"
chmod 0640 "$destdir/etc/jumpserver-ha/sync-paths"
if [[ "$sync_users_auto" == true ]]; then
  echo auto > "$destdir/etc/jumpserver-ha/sync-users"
else
  printf '%s\n' "${sync_users[@]}" > "$destdir/etc/jumpserver-ha/sync-users"
fi
chmod 0640 "$destdir/etc/jumpserver-ha/sync-users"
if [[ "$role" == active ]]; then
  : > "$destdir/etc/jumpserver-ha/active"
  chmod 0644 "$destdir/etc/jumpserver-ha/active"
else
  rm -f -- "$destdir/etc/jumpserver-ha/active"
fi

# Install the configured calendar without evaluating it as shell input.
python3 - "$destdir/etc/systemd/system/shadow-ha-sync.timer" "$sync_interval" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
calendar = sys.argv[2]
if "\n" in calendar or "\r" in calendar:
    raise SystemExit("Unsafe systemd calendar")
text = path.read_text(encoding="utf-8")
lines = ["OnCalendar=" + calendar if line.startswith("OnCalendar=") else line
         for line in text.splitlines()]
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

if [[ -n "$destdir" ]]; then
  echo "STAGED_INSTALL_STATUS=success role=$role root=$destdir"
  exit 0
fi

getent group shadow-ha >/dev/null || groupadd --system shadow-ha
if ! getent passwd shadow-ha >/dev/null; then
  useradd --system --gid shadow-ha --home-dir /var/lib/shadow-ha --create-home \
    --shell /usr/sbin/nologin shadow-ha
fi
install -d -o root -g shadow-ha -m 0750 /etc/jumpserver-ha /etc/jumpserver-ha/keys
chown root:shadow-ha /etc/jumpserver-ha/role.conf /etc/jumpserver-ha/sync-paths /etc/jumpserver-ha/sync-users
install -d -o shadow-ha -g shadow-ha -m 0700 /var/lib/shadow-ha /var/lib/shadow-ha-sync

if [[ "$role" == standby ]]; then
  key=/etc/jumpserver-ha/keys/sync_ed25519
  if [[ ! -e "$key" ]]; then
    runuser -u shadow-ha -- ssh-keygen -q -t ed25519 -N '' -f "$key"
  fi
  chown shadow-ha:shadow-ha "$key" "$key.pub"
  chmod 0600 "$key"; chmod 0644 "$key.pub"
  if [[ -z "$active_known_hosts" && "$non_interactive" == false ]]; then
    candidate=$(mktemp)
    ssh-keyscan -p "$ssh_port" "$active_address" > "$candidate" 2>/dev/null
    echo 'Candidate active host-key fingerprints:'
    ssh-keygen -lf "$candidate"
    read -r -p 'Trust and pin these active host keys? [y/N]: ' answer
    [[ "$answer" =~ ^[Yy]$ ]] || { rm -f "$candidate"; echo 'Host key was not approved.' >&2; exit 2; }
    active_known_hosts=$candidate
  fi
  [[ -n "$active_known_hosts" ]] || {
    echo '--active-known-hosts is required in non-interactive standby installation.' >&2
    exit 2
  }
  install -o shadow-ha -g shadow-ha -m 0644 "$active_known_hosts" /etc/jumpserver-ha/active_known_hosts
  [[ ${candidate:-} ]] && rm -f "$candidate"
  systemctl disable --now gr-config-collect.timer 2>/dev/null || true
else
  getent group shadow-export >/dev/null || groupadd --system shadow-export
  if ! getent passwd shadow-export >/dev/null; then
    useradd --system --gid shadow-export --home-dir /var/lib/shadow-export --create-home \
      --shell /bin/sh shadow-export
  fi
  usermod --shell /bin/sh shadow-export
  install -d -o shadow-export -g shadow-export -m 0700 /var/lib/shadow-export/.ssh
  if [[ -z "$standby_public_key" && "$non_interactive" == false ]]; then
    prompt_value standby_public_key 'Path to the standby synchronization public key'
  fi
  [[ -r "$standby_public_key" ]] || {
    echo '--standby-public-key is required on the active node.' >&2
    exit 2
  }
  key_text=$(awk 'NF >= 2 && $1 ~ /^ssh-(ed25519|rsa)$/ {print $1 " " $2; exit}' "$standby_public_key")
  [[ -n "$key_text" ]] || { echo 'Standby public key is invalid.' >&2; exit 2; }
  printf 'restrict,command="sudo -n /usr/local/libexec/shadow-ha/export" %s\n' "$key_text" \
    > /var/lib/shadow-export/.ssh/authorized_keys
  chown shadow-export:shadow-export /var/lib/shadow-export/.ssh/authorized_keys
  chmod 0600 /var/lib/shadow-export/.ssh/authorized_keys
  cat > /etc/sudoers.d/shadow-ha-export <<'EOF'
shadow-export ALL=(root) NOPASSWD: /usr/local/libexec/shadow-ha/export
EOF
  chmod 0440 /etc/sudoers.d/shadow-ha-export
  visudo -cf /etc/sudoers.d/shadow-ha-export >/dev/null
fi

install -m 0644 "$project_dir/docs/STANDBY-RUNBOOK.md" /etc/jumpserver-ha/README.md
systemctl daemon-reload
if [[ "$role" == standby && "$enable_sync" == true ]]; then
  systemctl enable --now shadow-ha-apply.path shadow-ha-sync.timer
else
  systemctl disable --now shadow-ha-sync.timer shadow-ha-apply.path 2>/dev/null || true
fi
systemctl enable --now jumpserver-ha-update.timer

echo "JUMPSERVER_HA_INSTALL_STATUS=success role=$role"
if [[ "$role" == standby ]]; then
  echo 'Standby public key to authorize on the active node:'
  cat /etc/jumpserver-ha/keys/sync_ed25519.pub
  echo 'Package differences are proposal-only: sudo shadow-ha-packages plan'
fi
