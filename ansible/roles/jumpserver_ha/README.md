# Ansible role contract

Invoke the role once for the `active` host and once for the `standby` host.
Its variables are deliberately generic so a new HA pair can reuse the role.

Required out-of-band material:

- `jumpserver_ha_standby_sync_public_key` on the active host;
- the matching private key installed root-only on the standby host;
- `jumpserver_ha_active_known_host` pinned on the standby host.

Use `jumpserver_ha_sync_paths` only for shared operational state. The default
list is intentionally empty; each environment must opt in. Typical entries are
GR configuration, a user's encrypted password store/GPG/SSH material, GR audit
state, and `/var/lib/gr/config-archive`.

Scheduled collection units belong to the active node. The standby receives their
files but disables their timers.
