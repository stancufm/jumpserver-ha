# jumpserver-ha

Reusable, pull-based active/standby replication for Debian jump servers.

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

Private SSH/GPG keys, API credential files, password-store content and GR SSH
audits are excluded by default, including when they are below an approved
shared path. They are included only with the explicit `--sync-secrets` decision. Review
[the security model](docs/SECURITY.md) before enabling it.

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
  --active-known-hosts ./active_known_hosts --enable-sync

sudo ./install.sh --role active --vip VIP \
  --standby-public-key ./standby_sync_ed25519.pub
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

The login MOTD displays the role, last successful apply and the package-plan
command. See the [standby runbook](docs/STANDBY-RUNBOOK.md) for validation and
promotion.
