# Stremio Self-Hosted Stack Automation

This repo builds a deployment kit for a self-hosted AIOStreams + AIOMetadata stack, with optional NzbDav, Gluetun, Nginx Proxy Manager automation, Portainer deployment, and direct SSH deployment.

The quickest path:

```powershell
.\scripts\new-config.ps1 -BaseDomain example.com -Email you@example.com -EnableNzbDav -VpnMode http-proxy
notepad .\config\stack.env
.\scripts\render-stack.ps1
```

Then either:

```powershell
.\scripts\deploy-ssh.ps1 -Host oracle.example.com -User ubuntu
```

or upload/copy `rendered/docker-compose.yml` into Portainer as a stack.

Read [docs/runbook.md](docs/runbook.md) for the full process.

## Legal note

Use this stack only with content, services, providers, and indexers you are allowed to access. The scripts automate infrastructure deployment; they do not provide media, indexer accounts, provider accounts, or permission to ignore provider terms.
