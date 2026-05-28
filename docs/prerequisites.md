# Prerequisites Guide

Before running `.\scripts\setup.ps1`, you need to set up a few core pieces of infrastructure: a **server**, a **domain name with proper DNS routing**, and your **external API credentials**.

This guide covers everything you need to prepare, with both **paid (highly recommended)** and **free** options, including a clear breakdown of dynamic DNS limitations.

---

## 1. Server / Hosting Requirements

The self-hosted stack runs via Docker. You will need a Virtual Private Server (VPS) or a home server running Linux (Ubuntu 22.04 or 24.04 LTS is highly recommended). 

### ☁️ Free Route: Oracle Cloud "Always Free" VM Standard
Oracle Cloud Infrastructure (OCI) offers an exceptionally generous **Always Free Tier** that is perfect for this stack. 

#### **Step 1: Sign up for Oracle Cloud**
1. Register for an account at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/). 
2. Choose your **Home Region** carefully (this is where your server will be hosted; select a region close to you).

#### **Step 2: Create your Always Free Server**
1. In your OCI Console, navigate to **Compute** -> **Instances** -> **Create Instance**.
2. **Image**: Click *Edit*, select **Canonical Ubuntu Linux** (version 22.04 or 24.04).
3. **Shape**: Click *Edit* -> *Change Shape*. Select **Ampere (ARM-based)**. Select the **VM.Standard.A1.Flex** shape. 
   * *Allocation*: Configure it with **4 OCPUs** and **24 GB of RAM** (fully "Always Free Eligible"!).
4. **Networking**: Ensure "Assign a public IPv4 address" is checked.
5. **SSH Keys**: Download/Save the private key (`.key`) file. You will need this to access your server!
6. Click **Create** and wait for the status to show *Running*. Note your **Public IP Address**.

#### **Step 3: Open the Oracle Cloud Firewall (VCN Ingress Rules)**
By default, Oracle locks down your server. You must open it for web traffic:
1. In your OCI Console on the instance page, click your **Subnet** name (under Primary VNIC details).
2. Click your **Default Security List**.
3. Click **Add Ingress Rules** and add the following two rules:
   * **Rule 1 (HTTP/S Web Traffic)**:
     * *Source CIDR*: `0.0.0.0/0`
     * *IP Protocol*: `TCP`
     * *Destination Port Range*: `80, 443`
   * **Rule 2 (Portainer Web Panel)**:
     * *Source CIDR*: `0.0.0.0/0` (or your-home-public-ip/32 to restrict access to just your home network).
     * *IP Protocol*: `TCP`
     * *Destination Port Range*: `9443`

---

### 🚀 One-Command Automated Server Setup (Bootstrap)
Once you can SSH into your server, we have fully automated the installation of Docker, Portainer, and firewall rules.

1. Connect to your VPS via SSH (replace with your private key path and IP address):
   ```bash
   ssh -i /path/to/ssh.key ubuntu@<your-vps-ip>
   ```
2. Run this single command to download and run our **[bootstrap-vps.sh](file:///c:/Users/mounc/OneDrive/Documents/Streamio%20build%20and%20research/scripts/bootstrap-vps.sh)** bootstrap script:
   ```bash
   curl -sSL https://raw.githubusercontent.com/ZaneStephens/stremio-selfhost-stack/main/scripts/bootstrap-vps.sh | sudo bash
   ```

#### **What this script automates for you:**
* Updates Ubuntu package indices.
* Installs standard dependencies (`curl`, `git`, `ufw`).
* Installs **Docker Engine** using official Docker convenience scripts.
* Adds your user (`ubuntu`) to the `docker` group so you don't have to prefix commands with `sudo`.
* Sets up and starts **Portainer CE** (secured at `https://<your-vps-ip>:9443`).
* Configures local Ubuntu firewall (`ufw`) to block everything except SSH, HTTP (80), HTTPS (443), and Portainer (9443, 8000).
* Prepares the deployment directory `/opt/stremio-stack/data` with correct permissions.

---

## 2. Domain & DNS Configuration (Paid vs. Free Paths)

To access your AIOStreams, AIOMetadata, and NzbDav services securely over HTTPS, you must have a base domain pointing to your server's public IP address.

### 🟢 Option A: Paid Route (Highly Recommended)
Acquiring a custom domain gives you maximum flexibility, security, and a professional setup.

1.  **Register a Domain**: Buy a domain from a registrar. **Cloudflare**, **Namecheap**, **Porkbun**, or **GoDaddy** are excellent choices. TLDs like `.xyz`, `.net`, or `.com` often cost as little as $2 to $10 per year.
2.  **Point Nameservers to Cloudflare**: (Optional but highly recommended) Point your domain's nameservers to Cloudflare for fast, free DNS management and secure SSL certificates.
3.  **Configure DNS Records**:
    *   **A Record**: Map `@` (your base domain, e.g., `yourdomain.com`) to your **Server Public IP**.
    *   **Wildcard CNAME Record**: Create a record with Name/Host `*` pointing to `@` (or `yourdomain.com`).
    *   *Why this is great*: A single wildcard record (`*`) automatically handles routing for `aiostreams.yourdomain.com`, `metadata.yourdomain.com`, and `nzbdav.yourdomain.com` directly to your Nginx Proxy Manager without having to create separate records for each service.

---

### 🟡 Option B: Free Route (Dynamic DNS via DuckDNS)
If you want to host this on a home server with a dynamic home IP address, or want a completely free path for staging, you can use **DuckDNS**.

1.  **Register on DuckDNS**: Log in at [duckdns.org](https://www.duckdns.org) using OAuth (GitHub, Google, etc.).
2.  **Create a Subdomain**: Create a free subdomain like `mystremio.duckdns.org`.
3.  **Point to Server IP**: DuckDNS will automatically map this domain to your current public IP.

#### ⚠️ Critical Limitations & Pitfalls of Free Dynamic DNS:
While DuckDNS is free, it introduces several severe limitations that you must design around:

*   **No Free Wildcards (`*`)**: DuckDNS **does not support wildcard DNS subdomains** on the standard free tier. 
    *   *The Issue*: You cannot point `*.mystremio.duckdns.org` to your server.
    *   *The Workaround*: You must register **separate, individual DuckDNS subdomains** for each service (e.g., `mystremio-aio.duckdns.org`, `mystremio-meta.duckdns.org`, and `mystremio-nzb.duckdns.org`). Since DuckDNS limits you to **5 subdomains per account**, this will consume 3 of your slots.
*   **Let's Encrypt Rate Limits**: The `duckdns.org` suffix is shared by millions of users. Let's Encrypt enforces strict rate-limits on the number of SSL certificates generated per second/week per base domain. You may occasionally experience delays or certificate generation failures in Nginx Proxy Manager because the global `duckdns.org` domain is temporarily rate-limited.
*   **Dynamic IP Drifts**: If you host this at home, your Internet Service Provider (ISP) changes your public IP address periodically. If your IP changes, your stack will go offline.
    *   *The Workaround*: You must configure a dynamic DNS updater utility (like a DuckDNS cron job on your host or a ddclient container) to continuously ping DuckDNS and update your IP address.

---

### ⚪ Option C: Local-Only Route (No Domain Purchased)
If you want to test-drive the stack entirely on a local network or home lab without exposing it to the internet or buying a domain, you can map domains locally:

1.  **Pick a Fake Domain**: Choose something like `stremio.local`.
2.  **Edit your Local `hosts` file**:
    *   **On Windows**: Run Notepad as Administrator and open `C:\Windows\System32\drivers\etc\hosts`.
    *   **On Linux/macOS**: Open terminal and run `sudo nano /etc/hosts`.
3.  **Add the entries**:
    ```text
    127.0.0.1   stremio.local
    127.0.0.1   aiostreams.stremio.local
    127.0.0.1   metadata.stremio.local
    127.0.0.1   nzbdav.stremio.local
    ```
4.  *Note*: When using the local-only route, you **must use HTTP** (`http://`) instead of HTTPS (`https://`) during setup, as Let's Encrypt cannot validate and issue certificates for local `.local` domains.

---

## 3. External API Credentials Checklist

To make the stack useful once deployed, prepare the following API keys and account details:

| Provider / Service | Required For | Where to Get | Importance |
| :--- | :--- | :--- | :--- |
| **TMDB API Key** | Catalog and metadata populating in AIOMetadata | [TMDB API Dashboard](https://www.themoviedb.org/settings/api) | **Highly Recommended** |
| **Debrid Credentials** | Torrent cloud caching in AIOStreams | RealDebrid, Premiumize, or AllDebrid account | **Essential for Streaming** |
| **Usenet Provider** | Usenet indexer downloads in NzbDav | E.g. Newshosting, Frugal, UsenetServer, etc. | Optional (Only if using NzbDav) |
| **VPN WireGuard / OpenVPN** | Gluetun IP masking for traffic | E.g. Mullvad, ProtonVPN, NordVPN, AirVPN | Optional (Required if using VPN Mode) |
| **TVDB API Key** | Extended metadata catalogs | [TVDB Account Dashboard](https://thetvdb.com/dashboard/account/apikeys) | Optional |
| **Trakt Client ID/Secret** | Syncing watching history and lists | [Trakt API Applications](https://trakt.tv/oauth/applications) | Optional |
| **Gemini API Key** | Smart recommendations / LLM catalogs | [Google AI Studio](https://makersuite.google.com/app/apikey) | Optional |

Once you have these items configured or ready to paste, proceed to run:
```powershell
.\scripts\setup.ps1
```
