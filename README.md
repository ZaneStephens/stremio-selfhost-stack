# Stremio Self-Hosted Stack Automation

This repo builds a deployment kit for a self-hosted AIOStreams + AIOMetadata stack, with optional NzbDav, Gluetun, Nginx Proxy Manager automation, Portainer deployment, and direct SSH deployment.

## 📋 Prerequisites

Before running the setup, you must have a domain name, proper DNS routing, and a server prepared. 

Please read the detailed **[Prerequisites Guide](docs/prerequisites.md)** first.

## 🚀 Quick Start

The quickest path:

```powershell
.\scripts\setup.ps1
```

The setup wizard walks through domains, API keys, optional NzbDav, optional Gluetun, Nginx Proxy Manager, and deployment mode. It prints docs links as it goes and writes a redacted summary to `rendered/setup-summary.md`.

For a manual setup path:

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

Linux/macOS users can run the same workflow with PowerShell:

```bash
pwsh ./scripts/setup.ps1
```

Read [docs/runbook.md](docs/runbook.md) for the full process.

## Legal note

Use this stack only with content, services, providers, and indexers you are allowed to access. The scripts automate infrastructure deployment; they do not provide media, indexer accounts, provider accounts, or permission to ignore provider terms.
