#!/bin/sh
set -eu

python3 -m unittest discover -s tests -p 'test_*.py'
python3 -m py_compile bin/shadow-ha-packages
for script in install.sh bin/shadow-ha-export bin/shadow-ha-sync bin/shadow-ha-apply bin/jumpserver-ha-update; do
  bash -n "$script"
done
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
fi
if grep -R -nE '10\.22\.|BEGIN (OPENSSH|PGP) PRIVATE KEY|password[[:space:]]*=' \
    --exclude-dir=.git --exclude='*.pyc' .; then
  echo 'Potential environment-specific or secret content detected.' >&2
  exit 2
fi
echo 'jumpserver-ha development checks passed'
