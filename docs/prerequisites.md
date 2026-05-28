# Stremio Self-Hosted Stack: Prerequisites & Setup Guide

This guide is designed for both technical and non-technical users. It covers everything you need to prepare **before** running the installation wizard, explains what the questions in the installer actually mean in plain English, and walks you through what to do **after** the setup script finishes.

---

## 1. Server & Network Requirements (Oracle Always Free Setup)

The self-hosted stack runs via Docker. You will need a Virtual Private Server (VPS) or a home server running Linux (Ubuntu 22.04 or 24.04 LTS is highly recommended). 

### ☁️ Free Option: Oracle Cloud "Always Free" VM Standard
Oracle Cloud Infrastructure (OCI) offers an exceptionally generous **Always Free Tier** that is perfect for this stack. Follow this exact order to avoid console glitches.

#### **Step 1: Sign up for Oracle Cloud**
1. Register for an account at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/). 
2. Choose your **Home Region** carefully (this is where your server will be hosted; select a region close to you).

#### **Step 2: Network Setup (Create VCN & Open Firewall) — Do This First!**
Creating your network first using OCI's dedicated wizard is the cleanest method and avoids server creation errors.
1.  In your OCI Console, click the top-left menu icon (three lines) -> **Networking** -> **Virtual Cloud Networks**.
2.  Click the big **[Start VCN Wizard]** button.
3.  Select **"VCN with Internet Connectivity"** and click **Start VCN Wizard**.
4.  Name the VCN `my-stremio-network` and click **Next** -> **Create**. (Oracle will build your VCN, subnets, and gateways in 5 seconds).
5.  Click your newly created network `my-stremio-network` to open it.
6.  Under **Resources** on the left menu, click **Security Lists**.
7.  Click on the list named **"default security list for my-stremio-network"**.
8.  Click the blue **[Add Ingress Rules]** button, and add your web rules:
    *   **Rule 1 (HTTP & HTTPS Traffic)**:
        *   *Source CIDR*: `0.0.0.0/0`
        *   *IP Protocol*: `TCP`
        *   *Destination Port Range*: `80, 443`
    *   **Rule 2 (Portainer Web Panel)**:
        *   *Source CIDR*: `0.0.0.0/0` (or `your-home-public-ip/32` for extra security)
        *   *IP Protocol*: `TCP`
        *   *Destination Port Range*: `9443`
9.  Click **[Add Ingress Rules]** at the bottom to save.

#### **Step 3: Create your Always Free Server**
1. In the OCI Console, navigate to **Compute** -> **Instances** -> **Create Instance**.
2. **Image**: Click *Edit*, select **Canonical Ubuntu Linux** (version 22.04 or 24.04).
3. **Shape**: Click *Edit* -> *Change Shape*. Select **Ampere (ARM-based)**. Select the **VM.Standard.A1.Flex** shape. 
   * *Allocation*: Configure it with **4 OCPUs** and **24 GB of RAM**. *(See Capacity Troubleshooting below if OCI throws an error here).*
4. **Networking**: 
   * Select **"Select existing virtual cloud network"** and choose `my-stremio-network`.
   * Select **"Select existing subnet"** and choose `public subnet-my-stremio-network`.
   * Under **Public IPv4 address assignment**, click the toggle for **"Automatically assign public IPv4 address"** to **ON** (turning it blue).
5. **SSH Keys**: Click **"Download private key"** and save the `.key` file securely on your computer. You cannot log into your server without this!
6. Click **Create** and wait for the status to show *Running*. Note your **Public IP Address**.

#### 🛑 Troubleshooting: Oracle "Out of Capacity" ARM Error
Because the 4 vCPU / 24 GB RAM Ampere (ARM) shape is incredibly generous and popular, Oracle occasionally runs out of physical server capacity in certain regions. If you hit this error, try these fixes:
1.  **Switch the Availability Domain (AD)**: Under **Placement**, click **Edit**. If your region has multiple ADs (e.g. AD-2, AD-3), switch to a different AD and try again. *(Some regions like Sydney only have 1 AD, so this option won't exist).*
2.  **Request a smaller ARM instance**: You do not have to claim the full 4 OCPUs and 24 GB RAM. Try allocating **2 OCPUs and 12 GB of RAM** (or even **1 OCPU and 6 GB of RAM**, which is still incredibly fast and more than enough for this stack!). Smaller footprints are much easier for Oracle to fit.
3.  **Fallback to Always Free AMD (Micro) Shape (Immediate Allocation)**: If ARM is completely exhausted and you want to deploy *today*, switch the shape to **VM.Standard.E2.1.Micro** (1 vCPU, 1 GB RAM). This shape almost always has immediate capacity in every region!
    *   *Virtual Memory (Swap Space) Integration*: While 1 GB of RAM is very tight, **our automated bootstrap script (`bootstrap-vps.sh`) automatically detects if your server has less than 2 GB of RAM and automatically configures a 4 GB swap file on your hard drive!** This prevents your database/containers from ever crashing due to memory limits, making the 1 GB server incredibly stable.
4.  **Use an automated OCI Capacity Grabber script**: You can use the OCI CLI or standard community scripts (such as `oci-arm-creator` on GitHub) to continuously request your ARM instance every 30 seconds in the background from your local machine until an allocation opens up.

---

## 2. Automated Server Setup (Docker Auto-Installer)

We have fully automated the installation of Docker, Portainer CE, folders, permissions, and local firewalls. You can choose either the **Zero-Touch** cloud-init method during server creation, or the **One-Command SSH** method.

### **⚡ Option A: Zero-Touch Setup via "Initialization Script" (Highly Recommended)**
You can instruct Oracle to run our auto-install script the very first moment the server boots up! You won't even need to SSH in to do the setup.
1.  Before clicking **Create** on your OCI server page, scroll to the very bottom and expand **Advanced options**.
2.  In the **Initialization script** section, select **Paste XML/Text**.
3.  Copy and paste this exact **2-line script** into the box:
    ```bash
    #!/bin/bash
    curl -sSL https://raw.githubusercontent.com/ZaneStephens/stremio-selfhost-stack/main/scripts/bootstrap-vps.sh | bash
    ```
4.  Click **Create Instance**. Once your server status turns green (Running), wait **60–90 seconds** for the script to finish executing in the background.
5.  Open your browser and navigate directly to: `https://<your-vps-ip>:9443` (Accept the self-signed SSL certificate warning on first load. Your Portainer CE web console is live!).

### **💻 Option B: One-Command SSH Setup**
If you prefer to connect and watch the installation run in real-time:
1.  Connect to your VPS via SSH (replace with your private key path and IP address):
    ```bash
    ssh -i /path/to/ssh.key ubuntu@<your-vps-ip>
    ```
    *Note: If Windows SSH complains about "Unprotected Private Key File / Bad Permissions", run these two commands in PowerShell to lock it down:*
    ```powershell
    icacls.exe "F:\path\to\your\ssh.key" /inheritance:r
    icacls.exe "F:\path\to\your\ssh.key" /grant:r "$($env:USERDOMAIN)\$($env:USERNAME):(R,W)"
    ```
2.  Run this single command to download and execute our bootstrap script:
    ```bash
    curl -sSL https://raw.githubusercontent.com/ZaneStephens/stremio-selfhost-stack/main/scripts/bootstrap-vps.sh | sudo bash
    ```

---

## 3. Domain & DNS Configuration (Paid vs. Free Paths)

### 🟢 Option A: Paid Route (Highly Recommended)
Acquiring a custom domain gives you maximum flexibility, security, and a professional setup.
1.  **Register a Domain**: Buy a domain from a registrar. **Cloudflare**, **Namecheap**, or **Porkbun** are excellent choices ($2 to $10 per year).
2.  **Point Nameservers to Cloudflare**: Point your domain's nameservers to Cloudflare for fast, free DNS management and secure SSL certificates.
3.  **Configure DNS Records**:
    *   **A Record**: Map `@` (your base domain, e.g., `yourdomain.com`) to your **Server Public IP**.
    *   **Wildcard CNAME Record**: Create a record with Name/Host `*` pointing to `@` (or `yourdomain.com`). This single wildcard record (`*`) automatically handles routing for `aiostreams.yourdomain.com`, `metadata.yourdomain.com`, and `nzbdav.yourdomain.com` directly to your server.

### 🟡 Option B: Free Route (Dynamic DNS via DuckDNS)
If you want a completely free path for staging, you can use **DuckDNS**.
1.  **Register on DuckDNS**: Log in at [duckdns.org](https://www.duckdns.org) using OAuth (GitHub, Google, etc.).
2.  **Create Subdomains**: Since **DuckDNS does not support wildcard subdomains (`*`)**, you must register **two separate, individual DuckDNS subdomains** pointing to your server's public IP:
    *   `yourname-aio.duckdns.org` (for AIOStreams)
    *   `yourname-meta.duckdns.org` (for AIOMetadata)
    *(Both of these should point to the exact same server IP address).*

---

## 4. The Installation Wizard Questions (Plain-English Explanations)

When you run `.\scripts\setup.ps1` on your home computer, the wizard will ask you a series of questions. Here is exactly what they mean:

*   **Base Domain**: Enter your dynamic DNS base (e.g., `duckdns.org`) or your custom purchased domain.
*   **Hostnames (AIOStreams & AIOMetadata)**: 
    *   If using a custom domain: Enter `aiostreams.yourdomain.com` and `metadata.yourdomain.com`.
    *   If using DuckDNS: Override the defaults and enter your exact registered DuckDNS subdomains (e.g., `yourname-aio.duckdns.org` and `yourname-meta.duckdns.org`).
*   **Let's Encrypt Email**: Just enter your regular, personal email address (e.g. `yourname@gmail.com`). This is only used to notify you if a certificate is expiring or has a security warning.
*   **AIOStreams admin username & password**: You are creating the login details to protect your AIOStreams configuration panel. Leave the password completely blank and hit Enter—the script will automatically generate a highly secure, random password and print it in your final summary!
*   **TMDB API Key**: Copy and paste the shorter **API Key** (32 characters, e.g., `f7796bb...36be4c69...`) from your TMDB settings. Do NOT use the long "API Read Access Token".
*   **RPDB API Key**: Completely optional. If provided, it overlays ratings (IMDb, Metacritic, RT) directly onto your Stremio cover posters. If you don't have one, just leave it blank and hit Enter to skip.
*   **Include self-hosted NzbDav?**: Answer **`No`** if you are only using torrent streaming / Debrid services. Answer **`Yes`** only if you are a Usenet power-user.
*   **VPN Mode**: Since your streaming traffic is already fully encrypted and proxied by Debrid (Real-Debrid, TorBox, etc.), your server is not downloading torrents directly. Therefore, a VPN is **not** needed. Answer **`off`** (the default) to keep your server speeds incredibly fast!
*   **Nginx Proxy Manager Mode**: Select **`include` (Option 2)**. This bundles a fresh traffic controller service on your server to manage your web traffic and automate SSL certificates.
*   **What should setup do after rendering?**: Select **`ssh` (Option 3)**. This tells the script to connect directly over SSH to your Oracle VPS and deploy the entire stack automatically!

---

## 5. Nginx Proxy Manager Setup & Troubleshooting

When the setup script finishes deploying your stack over SSH, it will ask: `Run NPM proxy-host creation now? [y/N]`. If you select **`Yes`**, it runs `configure-npm.ps1` to automatically set up your DuckDNS subdomains.

Because the configuration script runs locally on your home computer, you may encounter three common connection errors. Here is how to resolve them easily:

### ❌ Issue 1: "Target Machine Actively Refused It" (`127.0.0.1:81`)
*   **Why it happens**: The script runs locally on your Windows machine, so it tries to connect to port 81 on your *local computer* instead of your Oracle server.
*   **The Fix (Secure SSH Tunneling)**: 
    1. Open a **brand-new, separate PowerShell window** on your computer.
    2. Run this command to open a secure tunnel (replace with your private key path and IP address):
       ```powershell
       ssh -i "F:\path\to\your\ssh.key" -L 81:127.0.0.1:81 ubuntu@<your-vps-ip> -N
       ```
       *(This window will look like it is hanging—**leave it open** in the background!)*
    3. Go back to your original PowerShell window and run: `.\scripts\configure-npm.ps1`.

### ❌ Issue 2: "502 Bad Gateway OpenResty"
*   **Why it happens**: When Nginx Proxy Manager boots up for the very first time, it takes **30 to 60 seconds** to run database migrations and start its background API.
*   **The Fix**: Simply wait 20 seconds for the database to initialize, and run `.\scripts\configure-npm.ps1` again.

### ❌ Issue 3: "Internal Error" (SSL/Let's Encrypt failure)
*   **Why it happens**: During first-run, NPM immediately tries to request SSL padlocks. If your DuckDNS subdomains are not yet pointed to your server IP, or if Let's Encrypt is temporarily rate-limited, the API fails and returns a `500 Internal Error`.
*   **The Fix (Bypass SSL first, add later)**:
    1. Open your project's **`config/stack.env`** file.
    2. Change `NPM_REQUEST_LETSENCRYPT=true` to **`NPM_REQUEST_LETSENCRYPT=false`** and save the file.
    3. Run `.\scripts\configure-npm.ps1` again. It will succeed instantly in less than 2 seconds!
    4. Once the script finishes, you can secure your subdomains directly in the NPM browser dashboard in 10 seconds (see below).

---

## 6. What to do AFTER the Setup Script Finishes

### **Step 1: Verify your Nginx Proxy Manager Dashboard**
1.  Open your browser and navigate to: `http://127.0.0.1:81` (Only works while the SSH tunnel in **Issue 1** is open).
2.  Log in using your NPM credentials from `config/stack.env` (or default: `admin@example.com` / `changeme`).
3.  You will see your **2 Proxy Hosts** successfully created and mapped!

### **Step 2: Secure with SSL Padlocks (If you bypassed in Issue 3)**
Once your subdomains are successfully pointed to your server IP on duckdns.org, you can secure them inside the dashboard:
1.  In your NPM dashboard, go to **Hosts** -> **Proxy Hosts**.
2.  For each host, click the **three dots** on the right -> **Edit**.
3.  Click the **SSL** tab, change *None* to **"Request a new SSL Certificate"**, and check **"I Agree to the Let's Encrypt Terms"**.
4.  Click **Save**. Your links are now fully HTTPS secured!

### **Step 3: Onboard and Install in Stremio**

#### **1. AIOStreams Configuration**
1.  Go to: `https://yourname-aio.duckdns.org/stremio/configure` *(use `http://` if SSL is not active yet)*.
2.  Log in using:
    *   **Username**: `admin`
    *   **Password**: *(Grab your generated password from `rendered/setup-summary.md`)*.
3.  Add your **Real-Debrid** or **TorBox** credentials, configure your sorting, and click **Install** to add it to Stremio!

#### **2. AIOMetadata Configuration**
1.  Go to: `https://yourname-meta.duckdns.org/configure`
2.  Configure your TMDB API Key, select your catalogs/providers, and click **Save**.
3.  Copy your generated addon URL and paste it directly into Stremio's search bar to install!

---
*Congratulations! Your self-hosted Stremio stack is officially deployed, fully automated, and secure on your Always Free Oracle Cloud VPS!*
