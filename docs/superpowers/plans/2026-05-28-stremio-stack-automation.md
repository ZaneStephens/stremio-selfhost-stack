# Stremio Stack Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a generated deployment kit for AIOStreams, AIOMetadata, optional NzbDav, optional Gluetun routing, Nginx Proxy Manager proxy-host setup, Portainer import, and direct SSH deployment.

**Architecture:** Keep a single user-edited `config/stack.env` as source of truth. PowerShell scripts render a fully inlined `rendered/docker-compose.yml`, `rendered/proxy-hosts.json`, and runbooks so Portainer and SSH use the same deployment artifact.

**Tech Stack:** PowerShell 5+/7, Docker Compose v2 on the VPS, Portainer optional, Nginx Proxy Manager optional API, upstream Docker images from GHCR/Docker Hub.

---

### Task 1: Configuration Skeleton

**Files:**
- Create: `config/stack.env.example`
- Create: `.gitignore`
- Create: `README.md`

- [x] **Step 1: Define the source-of-truth config**

Create `config/stack.env.example` with domain, app enablement, credentials, NPM, SSH, and Gluetun variables.

- [x] **Step 2: Protect generated secrets**

Ignore `config/stack.env`, `rendered/`, and `.upstream/`.

### Task 2: Render Script

**Files:**
- Create: `scripts/render-stack.ps1`

- [x] **Step 1: Parse dotenv input**

Read `config/stack.env`, preserve quoted values, ignore comments, and provide defaults for derived hosts and public URLs.

- [x] **Step 2: Render Compose**

Generate one inlined Compose file with no service `env_file` dependency so Portainer upload/copy works.

- [x] **Step 3: Render NPM proxy metadata**

Generate `rendered/proxy-hosts.json` with forward host/port values that match the selected VPN mode.

### Task 3: Bootstrap, Deploy, Check, Backup

**Files:**
- Create: `scripts/new-config.ps1`
- Create: `scripts/deploy-ssh.ps1`
- Create: `scripts/check-remote.ps1`
- Create: `scripts/backup-remote.ps1`
- Create: `scripts/configure-npm.ps1`

- [x] **Step 1: Generate an editable config**

Copy the example config and generate strong random values for AIOStreams `SECRET_KEY`, auth password, and AIOMetadata `ADMIN_KEY`.

- [x] **Step 2: Deploy over SSH**

Upload rendered files, create the proxy network when needed, optionally attach an existing NPM container to that network, and run `docker compose up -d`.

- [x] **Step 3: Configure NPM**

Use NPM token auth and proxy-host API to create missing proxy hosts. Skip existing hosts instead of overwriting them.

- [x] **Step 4: Verify and back up**

Add scripts for container/endpoint checks and remote tar backups before updates.

### Task 4: Documentation And Verification

**Files:**
- Create: `docs/research.md`
- Create: `docs/plan.md`
- Create: `docs/runbook.md`
- Create: `scripts/test-render.ps1`

- [x] **Step 1: Capture source-backed research**

Document key current upstream facts and their links.

- [x] **Step 2: Write the operator runbook**

Cover Portainer, SSH, NPM, Gluetun modes, NzbDav UI handoff, update, rollback, and health checks.

- [x] **Step 3: Verify rendering**

Run a local render test with a temporary config and assert key services and proxy-host metadata are produced.
