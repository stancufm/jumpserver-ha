# jumpserver-ha

Reusable, pull-based active/standby jump-server replication for Debian hosts.

The active node is the sole source of operational automation.  The standby node
pulls a fixed, root-readable export every five minutes through a restricted SSH
account, but never starts collection jobs by itself.

## What this project installs

- a narrow exporter on the active node;
- a root-owned sync key, pinned host key and pull service/timer on the standby;
- a role-aware MOTD/login warning and an operational runbook;
- optional replication of the GR configuration archive;
- unit files for scheduled jobs on both nodes, enabled only on the active node;
- a standby installer and a safe update checker for the installed project.

The role always installs the unit files and calls `systemctl daemon-reload`.
Installation alone does **not** enable an operational timer: this protects a
newly built standby and prevents an upgrade from unexpectedly starting network
collection. A separate explicit activation step enables timers only on the
active peer.

Secrets are replicated only when `jumpserver_ha_sync_secrets: true` is explicitly
set.  Do not put private keys, passphrases or credentials in Git; provision the
standby's private key and the active node's authorized public key out of band.

## Design constraints

The role deliberately does not copy host identity, network configuration,
VRRP/keepalived state, machine-id, or SSH host keys.  Each peer must retain its
own address and identity.  It synchronizes designated shared operational state
instead.  The active export command is fixed in sudoers; it is not a general
passwordless-root account.

See [the Romanian runbook](README.ro.md), [security model](docs/SECURITY.md),
and [the Ansible role](ansible/roles/jumpserver_ha/README.md).

## Standby installation and updates

The repository includes a non-interactive installer for the passive peer. It
preserves its existing root-only sync key and pinned active-host key; those
secrets are deliberately provisioned outside Git.

```bash
git clone https://github.com/stancufm/jumpserver-ha.git /opt/jumpserver-ha
cd /opt/jumpserver-ha
sudo ./install.sh --role standby --active-address ACTIVE_PHYSICAL_IP --ssh-port 42202 --vip FLOATING_VIP
```

The installer enables a daily `jumpserver-ha-update.timer` that only checks for
new fast-forward releases and logs their availability. It never auto-applies a
change. Apply after review with `sudo jumpserver-ha-update --apply`.
