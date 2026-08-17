# jumpserver-ha development guidance

## Compatibility and roles

- Preserve Debian 10 compatibility unless a major release explicitly changes it.
- Keep active and standby behavior role-aware and fail closed on an unknown role.
- The active is the sole operational writer; installation never promotes a node.

## Safety

- Never commit internal addresses, private keys, credentials, host-key pins or inventory exports.
- Keep network fetch unprivileged and privileged apply local, fixed and reviewable.
- Package installation, secret replication, timer activation and promotion must remain explicit.
- Never silently overwrite conflicting account names, UIDs or GIDs.

## Workflow

- Start changes from an up-to-date `main` on a `codex/<short-name>` branch.
- Update English and Romanian documentation for behavior changes.
- Run `.codex/setup.sh` and `git diff --check` before committing.
- Use semantic versions, focused commits and reviewed releases for deployment.
