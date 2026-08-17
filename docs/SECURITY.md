# Security model

## Split privilege

Network retrieval runs as the dedicated, non-login `shadow-ha` service user.
It can write only `/var/lib/shadow-ha-sync` and read its own private key and the
pinned active host key. A local root path unit starts `shadow-ha-apply` only
after a complete archive has been atomically staged.

The active node exposes no general shell. `shadow-export` accepts one key with
`restrict` and a forced `sudo -n /usr/local/libexec/shadow-ha/export` command.
The corresponding sudoers rule accepts no caller-supplied option or path.

## Archive validation and account safety

The standby verifies required metadata, format and member names before marking
an archive ready. The root apply helper extracts into a private staging
directory, validates every configured destination and refuses `/`, relative
paths and parent traversal. Existing account name/UID/GID/home/shell conflicts
abort the apply. Missing accounts may be created locked; password hashes are
never exported.

Home and approved path synchronization may remove stale files inside those
specific roots. The allow-list is therefore root-owned configuration. The
installer never accepts it from the remote caller.

## Secrets

Private SSH/GPG keys, API credential files, password-store state and GR SSH
audits are excluded from both home and approved-path replication unless
`JUMPSERVER_HA_SYNC_SECRETS=true` is explicitly configured. Enabling it means
compromise of the standby root account or synchronization key can expose the
replicated encrypted material and private keys. It does not copy a GPG
passphrase or guarantee unattended vault unlock after reboot.

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
