# jumpserver-ha

Reusable, pull-based active/standby replication for Debian jump servers.

Release archives enforce Unix LF line endings for every Linux entrypoint, so a
package built or tagged from Windows remains directly executable on Debian.

The standby fetches a fixed export with its own unprivileged `shadow-ha`
account. A separate local root helper applies only a validated archive. The
active accepts the standby key through the restricted `shadow-export` account
and one forced exporter command; no general remote shell or broad sudo rule is
granted.

## Replicated state

Each successful export contains:

- explicitly allow-listed operational paths;
- selected human account metadata (UID, GID, home, shell and group membership);
- their home directories, preserving numeric ownership, ACLs and xattrs;
- a Debian package manifest used only to produce a standby proposal.

Automatic user discovery selects normal `/home` accounts with UID 1000-59999.
Service users and non-login accounts are excluded. Existing conflicting names,
UIDs or GIDs stop the apply before home data is changed. Accounts and files are
never deleted merely because they disappeared from the active account list.
Linux account and group names containing dots are supported (for example,
`first.last`) while path separators and control characters remain rejected.

Partial mode is the reusable default: password hashes, private SSH/GPG keys,
API credential files, password-store content and GR SSH audits are excluded.
`--full-clone` changes the contract for a designated clone such as
`shadow-m`/`shadow-s`: it copies each selected account's local `/etc/shadow`
hash, lock state and aging fields, then mirrors its complete home directory.
The legacy `--sync-secrets` option is accepted as an alias. No plaintext
password or GPG passphrase is exported. Review
[the security model](docs/SECURITY.md) before enabling full clone.

Full clone intentionally covers selected human login accounts. System/service
accounts remain owned by their packages or application installers, so their
numeric identities cannot silently collide between independently installed
peers. Deleted users are still not removed automatically.

Primary user groups remain identity-critical and must have the same GID on both
peers. Existing supplementary groups are matched by name, because package-owned
groups such as `sudo`, `www-data` or application access groups can legitimately
have different numeric GIDs after independent installations. Home payloads keep
their numeric file ownership; application paths with local service accounts are
normalized back to the standby's local service identities after replication.
The private synchronization state remains owned by the dedicated `shadow-ha`
fetch account even after the root-only apply phase. This ownership invariant
allows every later timer run to create the next locked incoming archive; apply
must not convert the directory to `root:root` after its first success.

The active exporter stages the selected payload under the root-only
`/var/lib/shadow-ha-export-state` directory. This avoids assuming that `/tmp`
has enough capacity for complete home directories; the location can be
overridden with `SHADOW_HA_EXPORT_STATE_DIR` for a dedicated filesystem.

## Package reconciliation

Synchronization records the active package set and writes a proposal on the
standby:

```text
sudo shadow-ha-packages plan
```

No synchronization, timer, installer or Ansible run installs packages from
that proposal. Installation of missing package names requires a separate,
reviewed action:

```text
sudo shadow-ha-packages apply --yes --update
```

Version differences and extra standby packages remain report-only. Packages
are never automatically downgraded or removed.

## New-server installation

Run `install.sh` without `--non-interactive` for a guided setup. It asks for the
node role, physical active address, SSH port, floating/VIP address, pinned trust
material and optional synchronization choices. A standby generates its own
Ed25519 synchronization key and prints the public key that must be authorized on
the active node.

Examples without environment-specific values:

```text
sudo ./install.sh --role standby --active-address ACTIVE --vip VIP \
  --active-known-hosts ./active_known_hosts --full-clone --enable-sync

sudo ./install.sh --role active --vip VIP \
  --standby-public-key ./standby_sync_ed25519.pub --full-clone
```

Use `--destdir` for package and CI validation. Installation is idempotent and
preserves an existing standby private key. Missing Debian dependencies are
reported; installation requires `--install-dependencies`.

## GR integration and node roles

The active node alone runs GR collectors. `/var/lib/gr/config-archive`,
`/etc/gr` and the dedicated collector state may be added to the HA allow-list.
The standby pulls them but keeps every GR operational timer disabled until a
reviewed promotion. `jumpserver-ha` is the single replication authority; GR
does not create a parallel HA transport.

The installer uses a user-specific ACL to give an existing `gr-collector`
account traversal-only access to `/etc/jumpserver-ha`. This permits testing the
fixed, world-readable `active` marker without listing the directory or reading
group-protected HA configuration. GR applies the same ACL when it is installed
after HA, so installation order does not weaken role fencing.

The login MOTD displays the role, last successful apply and the package-plan
command, and states whether partial or full-clone policy is active. See the
[standby runbook](docs/STANDBY-RUNBOOK.md) for validation and promotion.
