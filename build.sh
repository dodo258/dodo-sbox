#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p dist
file=$(mktemp dist/.bundle.XXXXXX)
trap 'rm -f "$file"' EXIT
printf '#!/usr/bin/env bash\n# DODO_SBOX_BUNDLE\nset -o pipefail\nDODO_SELF=$(readlink -f -- "${BASH_SOURCE[0]}")\n' > "$file"
for part in common config system certificates menu routing main; do cat "lib/$part.sh" >> "$file"; done
printf '\nif [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi\n' >> "$file"
bash -n "$file"
chmod 755 "$file"
mv "$file" dist/dodo-sbox
if command -v sha256sum >/dev/null; then (cd dist && sha256sum dodo-sbox > SHA256SUMS); else (cd dist && shasum -a 256 dodo-sbox > SHA256SUMS); fi
