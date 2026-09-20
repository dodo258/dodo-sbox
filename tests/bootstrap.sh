#!/usr/bin/env bash
# Runs as root on disposable Linux CI; curl is replaced with local fixture copies.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
[[ $EUID == 0 && $(uname -s) == Linux ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/assets"
export BOOTSTRAP_FIXTURE=$work/assets BOOTSTRAP_MARKER=$work/executed
cat > "$work/bin/curl" <<'SH'
#!/usr/bin/env bash
set -eu
while (( $# )); do
  case $1 in https://*/dodo-sbox) asset=dodo-sbox;; https://*/SHA256SUMS) asset=SHA256SUMS;; -o) shift; destination=$1;; esac
  shift
done
cp "$BOOTSTRAP_FIXTURE/$asset" "$destination"
SH
chmod 755 "$work/bin/curl"
export PATH="$work/bin:$PATH"
printf '#!/usr/bin/env bash\nprintf "%%s" "$*" > "$BOOTSTRAP_MARKER"\n' > "$work/assets/dodo-sbox"
(cd "$work/assets" && sha256sum dodo-sbox > SHA256SUMS)
bash install.sh version
[[ $(cat "$BOOTSTRAP_MARKER") == version ]]
echo 'PASS bootstrap executes complete verified release and forwards arguments'
rm "$BOOTSTRAP_MARKER"
printf 'tampered\n' >> "$work/assets/dodo-sbox"
if bash install.sh version; then echo 'FAIL tampered bundle executed'; exit 1; fi
[[ ! -e $BOOTSTRAP_MARKER ]]
echo 'PASS bootstrap refuses incorrect checksum without running bundle'
printf 'bad manifest\n' > "$work/assets/SHA256SUMS"
if bash install.sh version; then echo 'FAIL bad manifest accepted'; exit 1; fi
[[ ! -e $BOOTSTRAP_MARKER ]]
echo 'PASS bootstrap refuses invalid manifest'
