#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=${DRY_RUN:-0}
VERSION=${SING_BOX_VERSION:-latest}
INSTALL_PATH=${SING_BOX_BIN:-/usr/local/bin/sing-box}
API_BASE=https://api.github.com/repos/SagerNet/sing-box/releases

architecture() {
  case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
    amd64|x86_64) printf 'amd64\n';;
    arm64|aarch64) printf 'arm64\n';;
    *) printf 'sing-box: unsupported architecture\n' >&2; exit 1;;
  esac
}
ARCH=$(architecture)

release_url() {
  if [[ "$VERSION" == latest ]]; then printf '%s/latest\n' "$API_BASE"; else printf '%s/tags/v%s\n' "$API_BASE" "${VERSION#v}"; fi
}

if [[ "$DRY_RUN" == 1 ]]; then
  printf 'sing-box: dry-run architecture=%s version=%s\n' "$ARCH" "$VERSION"
  exit 0
fi
[[ "$(id -u)" == 0 ]] || { printf 'sing-box: root is required\n' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf 'sing-box: curl is required\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'sing-box: python3 is required\n' >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { printf 'sing-box: tar is required\n' >&2; exit 1; }

release_json=$(mktemp)
archive=$(mktemp --suffix=.tar.gz)
extract_dir=$(mktemp -d)
cleanup() { rm -f "$release_json" "$archive"; rm -rf "$extract_dir"; }
trap cleanup EXIT
curl -fsSL --compressed --retry 3 "$(release_url)" -o "$release_json"
IFS=$'\t' read -r tag asset_url digest asset_name < <(python3 - "$release_json" "$ARCH" <<'PY'
import json, sys
release=json.load(open(sys.argv[1]))
arch=sys.argv[2]
version=release['tag_name'].removeprefix('v')
name=f'sing-box-{version}-linux-{arch}.tar.gz'
for asset in release.get('assets',[]):
    if asset['name'] == name:
        print(release['tag_name'], asset['browser_download_url'], asset.get('digest',''), asset['name'], sep='\t')
        break
else:
    raise SystemExit(f'asset not found: {name}')
PY
)
printf '%s\n' "sing-box: downloading official release $tag ($ARCH)"
if ! curl -fsSL --compressed --connect-timeout 30 --max-time 120 --retry 3 "$asset_url" -o "$archive"; then
  printf '%s\n' "sing-box: official release asset download failed for $tag ($ARCH); no binary was installed" >&2
  exit 1
fi
if [[ "$digest" == sha256:* ]]; then
  expected=${digest#sha256:}; actual=$(sha256sum "$archive" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || { printf 'sing-box: checksum verification failed\n' >&2; exit 1; }
else
  printf '%s\n' 'sing-box: upstream checksum unavailable; continuing without checksum verification' >&2
fi

tar -xzf "$archive" -C "$extract_dir"
binary=$(find "$extract_dir" -type f -name sing-box -print -quit)
[[ -n "$binary" ]] || { printf 'sing-box: release did not contain sing-box binary\n' >&2; exit 1; }
install -m 0755 "$binary" "$INSTALL_PATH"
"$INSTALL_PATH" version >/dev/null
printf '%s\n' "sing-box: installed and validated $tag"
