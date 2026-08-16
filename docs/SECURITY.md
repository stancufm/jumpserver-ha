# Security model

The standby authenticates with a dedicated, root-owned SSH key. The active
node accepts it only for a forced command that invokes one fixed exporter via a
single sudoers entry. The exporter has a fixed allow-list of paths and produces
one tar stream; it accepts no caller-supplied path or option.

This is intentionally stronger than granting a general shell or broad
passwordless sudo access. The trade-off is that compromise of the standby sync
key can retrieve the allow-listed state, including secrets when that option is
enabled. Protect the key as root-only, pin the active host key, use the physical
active address rather than a floating VIP, and audit each sync.

After a failover, validate VRRP and the latest successful sync before manually
enabling any operational timers. If GPG uses a passphrase, an interactive unlock
may still be required after reboot; do not weaken GPG protection merely to make
replication unattended without an explicit security decision.
