# Ansible role contract

Invoke the role once for the `active` host and once for the `standby` host.
Its variables are deliberately generic so a new HA pair can reuse the role.

Required out-of-band material:

- `jumpserver_ha_standby_sync_public_key` on the active host;
- the matching private key installed root-only on the standby host;
- `jumpserver_ha_active_known_host` pinned on the standby host.

`jumpserver_ha_sync_paths` is an explicit allow-list for shared operational
state. Human users are discovered independently from `/etc/passwd`, or selected
with `jumpserver_ha_sync_users`. Existing conflicting UID/GID mappings stop the
apply before a home directory is changed.

Private SSH/GPG keys and encrypted vault directories are excluded unless
`jumpserver_ha_sync_secrets` is explicitly enabled. Package differences are
written as a proposal; the role never invokes package installation.

GR owns and installs its scheduled-collection units. This role does not replace
them; it keeps `gr-config-collect.timer` disabled on standby and maintains the
active marker used by GR for fencing.
