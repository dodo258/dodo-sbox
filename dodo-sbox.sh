#!/usr/bin/env bash
set -o pipefail
DODO_SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DODO_SELF=$DODO_SOURCE/dist/dodo-sbox
for part in common config system certificates menu routing updates main; do
    # shellcheck source=/dev/null
    source "$DODO_SOURCE/lib/$part.sh" || exit 1
done
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
