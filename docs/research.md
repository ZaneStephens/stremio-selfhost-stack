# Research Notes

Last checked: 2026-05-28.

## AIOStreams

- Official deployment docs recommend Docker Compose and show `ghcr.io/viren070/aiostreams:latest`, `BASE_URL`, `SECRET_KEY`, and `/app/data` persistence.
- Current docs say only `BASE_URL` and `SECRET_KEY` are required bootstrap variables; most runtime settings should be configured from the dashboard unless you want to pin them.
- Templates can be added with the `TEMPLATE_URLS` environment variable or `/app/data/templates`.
- TamTaro and Vidhin template sync is implemented here through environment variables because these are instance-level template availability settings, not per-user app choices.

Sources:
- https://docs.aiostreams.viren070.me/getting-started/deployment/
- https://docs.aiostreams.viren070.me/configuration/environment-variables/
- https://docs.aiostreams.viren070.me/reference/templates/
- https://github.com/Tam-Taro/SEL-Filtering-and-Sorting
- https://github.com/Vidhin05/Releases-Regex

## AIOMetadata

- The upstream README uses `ghcr.io/cedya77/aiometadata:latest`, port `3232`, a persistent `/app/addon/data` volume, and Redis.
- Current environment docs require `DATABASE_URL`, `REDIS_URL`, `HOST_NAME`, and `TMDB_API_KEY` for a useful production setup.
- SQLite is supported, so this automation defaults to SQLite plus Redis for low-admin VPS deployment.

Sources:
- https://github.com/cedya77/aiometadata
- https://github.com/cedya77/aiometadata/blob/main/docs/ENVIRONMENT_VARIABLES.md

## NzbDav

- The upstream README describes NzbDav as a WebDAV server with a SABnzbd-compatible API and recommends the `nzbdav/nzbdav:latest` image.
- The setup guide uses port `3000`, `/config` persistence, `PUID`, `PGID`, and optional rclone sidecar for library mounting.
- For AIOStreams on-demand Stremio use, the guide says rclone is not required; the service can be configured inside AIOStreams after NzbDav onboarding.

Sources:
- https://github.com/nzbdav-dev/nzbdav
- https://raw.githubusercontent.com/nzbdav-dev/nzbdav/main/docs/setup-guide.md
- https://github.com/Viren070/AIOStreams/wiki/Usenet

## Gluetun

- Gluetun supports routing another container through its network namespace with `network_mode: "service:gluetun"`.
- It also supports an internal HTTP proxy using `HTTPPROXY=on` and `HTTPPROXY_LISTENING_ADDRESS=:8888`.
- Firewall options include `FIREWALL_INPUT_PORTS` for ports reachable through the default interface and `FIREWALL_OUTBOUND_SUBNETS` for LAN/Docker subnets; avoid overlap with VPN tunnel ranges.

Sources:
- https://raw.githubusercontent.com/qdm12/gluetun-wiki/main/setup/connect-a-container-to-gluetun.md
- https://raw.githubusercontent.com/qdm12/gluetun-wiki/main/setup/options/http-proxy.md
- https://raw.githubusercontent.com/qdm12/gluetun-wiki/main/setup/options/firewall.md

## Portainer And Nginx Proxy Manager

- Portainer can upload a Compose file and load environment variables, but a fully inlined generated Compose file is more reliable across copy/paste, upload, and SSH.
- Nginx Proxy Manager official setup exposes ports 80, 443, and 81 and persists `/data` plus `/etc/letsencrypt`.
- NPM has token and proxy-host API schemas in the upstream repo. This automation uses those APIs only to create missing proxy hosts and does not overwrite existing hosts.

Sources:
- https://docs.portainer.io/2.21/user/docker/stacks/add
- https://nginxproxymanager.com/setup/
- https://raw.githubusercontent.com/NginxProxyManager/nginx-proxy-manager/master/backend/schema/paths/tokens/post.json
- https://raw.githubusercontent.com/NginxProxyManager/nginx-proxy-manager/master/backend/schema/paths/nginx/proxy-hosts/post.json
