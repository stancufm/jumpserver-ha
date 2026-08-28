# Security model

## Split privilege

Network retrieval runs as the dedicated, non-login `shadow-ha` service user.
It can write only `/var/lib/shadow-ha-sync` and its mode 0700 key directory, and
read its own private key and the
pinned active host key. A local root path unit starts `shadow-ha-apply` only
after a complete archive has been atomically staged.

The active node exposes no general shell. `shadow-export` accepts one key with
`restrict` and a forced `sudo -n /usr/local/libexec/shadow-ha/export` command.
The corresponding sudoers rule accepts no caller-supplied option or path.
The installer normalizes this dedicated account's home to
`/var/lib/shadow-export`, ensuring OpenSSH and the updater use the same guarded
`authorized_keys` location even after an upgrade from a legacy installation.

## Archive validation and account safety

The standby verifies required metadata, format and member names before marking
an archive ready. The root apply helper extracts into a private staging
directory, validates every configured destination and refuses `/`, relative
paths and parent traversal. Existing account name/UID/GID/home/shell conflicts
abort the apply. Missing accounts are created locked before policy is applied.
In partial mode, password hashes are never exported. In full-clone mode, the
selected account names in `/etc/shadow` must exactly match the selected user
metadata before any password state is accepted. The hash is passed to
`chpasswd --encrypted` over standard input, never in a process argument or log.

Home and approved path synchronization may remove stale files inside those
specific roots. The allow-list is therefore root-owned configuration. The
installer never accepts it from the remote caller.

## Secrets

Private SSH/GPG keys, API credential files, password-store state, GR SSH
audits and local password hashes are excluded from partial replication.
`JUMPSERVER_HA_FULL_CLONE=true` includes these items for selected human login
accounts and approved paths. The compatibility variable
`JUMPSERVER_HA_SYNC_SECRETS=true` enables the same policy.

Full clone makes the standby a second security boundary for the active: root
or physical compromise can expose password hashes, encrypted material and
private keys. The incoming archive is mode 0600 in a mode 0700 service state
directory and is deleted after a successful apply; a failed apply retains it
for diagnosis/retry. No plaintext password or GPG passphrase is copied, and a
GPG agent may still require interactive unlock after reboot.

System accounts are not copied from `/etc/shadow`. They are created by the
same reviewed packages/application installers on both peers. This avoids
replacing service-account authentication and UID policy with data from another
installation.

Selected users and their primary groups are identity-critical: a UID or primary
GID conflict stops apply. Supplementary groups are reconciled by name so that
independently installed package/service groups do not require the same numeric
GID. The apply step never renumbers an existing local system group. Numeric file
ownership is retained for selected homes, while known application paths are
restored to the standby's local service identities after replication.

## Packages

Package inventory is data, not an instruction. Synchronization only writes a
proposal. `shadow-ha-packages apply --yes` is a separate local-root action and
installs missing names from configured standby repositories. It never removes,
downgrades or automatically reconciles version differences. Package maintainer
scripts may start services, so every apply needs an administrator review.

## Role fencing

The standby fetch and apply steps both stop when the configured VIP is present
locally. GR collection timers remain disabled on standby. Promotion requires a
human to exclude split-brain, inspect the last successful synchronization and
enable only the approved operational timers.
