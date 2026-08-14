# Official installation sources

## Sources

- sing-box is downloaded from the official GitHub release API for
  `SagerNet/sing-box`.
- cloudflared is downloaded from the official GitHub release API for
  `cloudflare/cloudflared`.
- Debian packages are not used for either service.

The installers select the official Linux `amd64` or `arm64` artifact based on
Debian architecture. Unsupported architectures fail before downloading.

## Latest versus pinned versions

`config/versions.env.example` defaults both services to `latest`. This is
convenient for development but resolves a moving release and is not fully
reproducible.

For a reproducible rebuild, copy the version variables into the deployment
environment and set explicit release versions, for example:

```text
SING_BOX_VERSION=1.13.18
CLOUDFLARED_VERSION=2026.8.1
```

The values are release versions, not Debian package versions. A leading `v` is
accepted for sing-box and cloudflared tags.

## Verification

Each installer:

1. Resolves the requested official release through GitHub's release API.
2. Selects the architecture-specific upstream asset.
3. Downloads it over HTTPS.
4. Verifies the GitHub API-provided SHA-256 digest when present.
5. Installs to `/usr/local/bin`.
6. Runs `sing-box version` or `cloudflared --version`.

If upstream release metadata has no digest, the installer reports that fact and
continues. A future hardening phase can require a separately pinned checksum
manifest. The deployment logs never print secret environment values or token
contents.
