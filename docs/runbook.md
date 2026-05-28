# Runbook

## 1. Create The Config

```powershell
.\scripts\new-config.ps1 -BaseDomain example.com -Email you@example.com -EnableNzbDav -VpnMode http-proxy
notepad .\config\stack.env
```

Fill in at least:

- `BASE_DOMAIN`
- `LETSENCRYPT_EMAIL`
- `TMDB_API_KEY`
- `AIOSTREAMS_AUTH_USER`
- VPN values if `VPN_MODE` is not `off`

## 2. Render

```powershell
.\scripts\render-stack.ps1
```

Outputs:

- `rendered/docker-compose.yml`
- `rendered/proxy-hosts.json`
- `rendered/next-steps.md`

## 3. Portainer Deployment

1. Open Portainer.
2. Go to Stacks, Add stack.
3. Name it `stremio-stack`.
4. Paste or upload `rendered/docker-compose.yml`.
5. Deploy the stack.

If using an existing Nginx Proxy Manager container, make sure it is attached to the same Docker network as the stack. The SSH deploy script can do this automatically with `NPM_CONTAINER_NAME`.

## 4. SSH Deployment

```powershell
.\scripts\deploy-ssh.ps1 -Host oracle.example.com -User ubuntu
```

Useful options:

```powershell
.\scripts\deploy-ssh.ps1 -Host 1.2.3.4 -User ubuntu -RemoteDir /opt/stremio-stack -SshKey C:\Users\you\.ssh\oracle.key
```

The script:

- renders first unless `-SkipRender` is passed,
- creates the remote directory,
- uploads `rendered/docker-compose.yml`,
- creates the external proxy network if configured,
- optionally attaches an existing NPM container,
- runs `docker compose up -d`.

## 5. Configure Nginx Proxy Manager

If you supplied NPM credentials in `config/stack.env`, run:

```powershell
.\scripts\configure-npm.ps1
```

Dry run:

```powershell
.\scripts\configure-npm.ps1 -DryRun
```

The script creates missing proxy hosts only. Existing domains are skipped so it will not overwrite your mate's current NPM setup.

For Let's Encrypt, DNS must already point to the VPS and ports 80/443 must reach NPM.

## 6. First App Setup

AIOStreams:

- Open `https://aiostreams.example.com/stremio/configure`.
- Use the generated `AIOSTREAMS_AUTH_USER` and `AIOSTREAMS_AUTH_PASSWORD`.
- Use the TamTaro complete template from the landing page, or use the deep link printed in `rendered/next-steps.md`.
- Configure debrid/Usenet credentials and install to Stremio.

AIOMetadata:

- Open `https://metadata.example.com/configure`.
- Configure catalogs/providers.
- Save and install the generated addon URL in Stremio.

NzbDav:

- Open `https://nzbdav.example.com` if enabled and proxied.
- Create the admin user.
- Configure Usenet provider settings.
- Configure WebDAV credentials.
- In AIOStreams, add the NzbDav service.

For `VPN_MODE=hybrid`, use `http://gluetun:3000` as the internal NzbDav URL from AIOStreams.

## 7. Check Health

```powershell
.\scripts\check-remote.ps1 -Host oracle.example.com -User ubuntu
```

The script prints Docker service state and tries configured public health endpoints.

## 8. Back Up Before Updates

```powershell
.\scripts\backup-remote.ps1 -Host oracle.example.com -User ubuntu
```

This creates a tarball on the remote host and downloads it into `backups/`.

## 9. Update

```powershell
.\scripts\backup-remote.ps1 -Host oracle.example.com -User ubuntu
.\scripts\deploy-ssh.ps1 -Host oracle.example.com -User ubuntu
```

The compose file uses `latest` tags by default. To pin versions, set image tag variables in `config/stack.env` before rendering.
