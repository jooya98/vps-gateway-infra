#!/usr/bin/env bash
set -euo pipefail
DRY_RUN=${DRY_RUN:-0}
VERSION=${SNIPROXY_VERSION:-2.4.1}
INSTALL_PATH=${SNIPROXY_BIN:-/usr/local/bin/sniproxy}
API_BASE=https://api.github.com/repos/mosajjal/sniproxy/releases
case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in amd64|x86_64) ARCH=amd64;; arm64|aarch64) ARCH=arm64;; *) printf 'sniproxy: unsupported architecture\n' >&2; exit 1;; esac
if [[ "$DRY_RUN" == 1 ]]; then printf 'sniproxy: dry-run architecture=%s version=%s\n' "$ARCH" "$VERSION"; exit 0; fi
[[ "$(id -u)" == 0 ]] || { printf 'sniproxy: root is required\n' >&2; exit 1; }
command -v curl >/dev/null || { printf 'sniproxy: curl is required\n' >&2; exit 1; }
command -v python3 >/dev/null || { printf 'sniproxy: python3 is required\n' >&2; exit 1; }
command -v tar >/dev/null || { printf 'sniproxy: tar is required\n' >&2; exit 1; }
release_json=$(mktemp); archive=$(mktemp --suffix=.tar.gz); extract_dir=$(mktemp -d); trap 'rm -f "$release_json" "$archive"; rm -rf "$extract_dir"' EXIT
curl -fsSL --compressed --retry 3 "$API_BASE/tags/v${VERSION#v}" -o "$release_json"
IFS=$'\t' read -r asset_url digest asset_name < <(python3 - "$release_json" "$ARCH" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); arch=sys.argv[2]
name=f'sniproxy-v{r["tag_name"].removeprefix("v")}-linux-{arch}.tar.gz'
for a in r.get('assets',[]):
    if a['name']==name:
        print(a['browser_download_url'],a.get('digest',''),a['name'],sep='\t'); break
else: raise SystemExit(f'asset not found: {name}')
PY
)
printf 'sniproxy: downloading %s (%s)\n' "$asset_name" "$ARCH"
curl -fsSL --compressed --connect-timeout 30 --max-time 120 --retry 3 "$asset_url" -o "$archive"
if [[ "$digest" == sha256:* ]]; then expected=${digest#sha256:}; actual=$(sha256sum "$archive"|awk '{print $1}'); [[ "$actual" == "$expected" ]] || { printf 'sniproxy: checksum verification failed\n' >&2; exit 1; }; fi
tar -xzf "$archive" -C "$extract_dir"
binary=$(find "$extract_dir" -type f -name sniproxy -print -quit)
[[ -n "$binary" ]] || { printf 'sniproxy: binary missing from release\n' >&2; exit 1; }
install -m 0755 "$binary" "$INSTALL_PATH"
"$INSTALL_PATH" --version >/dev/null
printf 'sniproxy: installed and validated %s\n' "$VERSION"
