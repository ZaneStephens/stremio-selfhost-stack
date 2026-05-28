# Automation Plan

## What This Automates

1. Creates a local `config/stack.env` with generated secrets.
2. Renders a single Portainer-ready `docker-compose.yml`.
3. Includes AIOStreams with TamTaro SEL and Vidhin REX template sync.
4. Includes AIOMetadata with Redis and SQLite persistence.
5. Optionally includes NzbDav.
6. Optionally includes Gluetun in HTTP-proxy mode or hybrid NzbDav network mode.
7. Optionally includes a fresh Nginx Proxy Manager service, or targets an existing NPM container.
8. Can deploy by SSH, run health checks, configure NPM proxy hosts, and back up remote data.

## What Remains Manual

- API keys and account credentials: TMDB, TVDB, Fanart, MDBList, Trakt, SimKL, VPN, Usenet provider, and indexers.
- First-run UI onboarding in AIOStreams, AIOMetadata, and NzbDav.
- Stremio addon install after the generated configuration is saved.
- NPM certificate success depends on DNS, firewall, port 80/443 reachability, and the NPM account email.

## Deployment Shape

The scripts render `rendered/docker-compose.yml`. That file is intentionally fully inlined so it works in Portainer without relying on sidecar `.env` files. The sensitive source config stays in `config/stack.env`, which is ignored by git.

Default services:

- `aiostreams`
- `aiometadata`
- `aiometadata_redis`

Optional services:

- `nzbdav`
- `gluetun`
- `nginx-proxy-manager`

## Gluetun Modes

- `off`: no VPN service.
- `http-proxy`: starts Gluetun and routes AIOStreams addon requests through `ADDON_PROXY=http://gluetun:8888`; AIOMetadata can also use `HTTP_PROXY` and `HTTPS_PROXY`.
- `hybrid`: same as `http-proxy`, and NzbDav shares Gluetun's network namespace so NNTP/provider traffic leaves through the VPN. In this mode NPM and AIOStreams should talk to NzbDav at `http://gluetun:3000`.

## Recommended First Run

Use `VPN_MODE=http-proxy` first. Once AIOStreams and AIOMetadata are healthy, switch to `hybrid` if you enable NzbDav and want its provider traffic routed through the VPN.
