# Setup Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Windows-first guided setup wizard that writes `config/stack.env`, renders the Compose stack, and optionally runs SSH/NPM follow-up scripts.

**Architecture:** `scripts/setup.ps1` owns the user journey and delegates actual rendering/deployment to the existing focused scripts. A JSON answers file drives non-interactive mode so CI-style smoke tests can exercise the workflow without terminal prompts.

**Tech Stack:** PowerShell 5.1+/7, existing stack env format, existing render/deploy/NPM scripts, Docker Compose validation via existing tests.

---

### Task 1: Non-Interactive Test Harness

**Files:**
- Create: `tests/test-setup.ps1`

- [x] **Step 1: Write the failing setup test**

The test creates a temporary answers JSON file, runs `scripts/setup.ps1 -NonInteractive`, and asserts that generated config, rendered compose, proxy metadata, and setup summary exist with expected values.

- [x] **Step 2: Run test to verify RED**

Run: `.\tests\test-setup.ps1`

Expected: FAIL because `scripts/setup.ps1` does not exist yet.

### Task 2: Setup Wizard

**Files:**
- Create: `scripts/setup.ps1`

- [ ] **Step 1: Implement config helpers**

Read the example dotenv file, update key/value pairs, preserve comments/order, generate missing secrets, and write `config/stack.env`.

- [ ] **Step 2: Implement prompt helpers**

Add text, yes/no, and choice prompts with doc links and sensible defaults. Non-interactive mode reads values from answers JSON.

- [ ] **Step 3: Implement setup stages**

Collect domain, core service, API key, NzbDav, VPN, NPM, and deployment choices.

- [ ] **Step 4: Delegate execution**

Call `render-stack.ps1`, optionally `deploy-ssh.ps1`, optionally `configure-npm.ps1`, and write `rendered/setup-summary.md`.

### Task 3: Docs

**Files:**
- Modify: `README.md`
- Modify: `docs/runbook.md`

- [ ] **Step 1: Make setup wizard the primary quick path**

Document `.\scripts\setup.ps1` as the preferred Windows setup command.

- [ ] **Step 2: Add PowerShell-on-Linux note**

Document `pwsh ./scripts/setup.ps1` for Bash-friendly users without maintaining a second wizard.

### Task 4: Verification And Publish

**Files:**
- Modify: no extra source files

- [ ] **Step 1: Run setup test**

Run: `.\tests\test-setup.ps1`

Expected: PASS.

- [ ] **Step 2: Run existing render test**

Run: `.\scripts\test-render.ps1`

Expected: PASS.

- [ ] **Step 3: Run PowerShell parse check**

Run parser across `scripts/*.ps1` and `tests/*.ps1`.

Expected: no parse errors.

- [ ] **Step 4: Commit and push**

Commit message: `Add guided setup wizard`
