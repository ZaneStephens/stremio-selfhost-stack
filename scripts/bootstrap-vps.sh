#!/bin/bash
# Stremio Self-Hosted Stack: VPS Bootstrap & Docker Auto-Installer
# Supported OS: Ubuntu 20.04 / 22.04 / 24.04 LTS (AMD64 & ARM64)

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=====================================================${NC}"
echo -e "${GREEN}    Stremio Self-Hosted Stack: VPS Auto-Installer    ${NC}"
echo -e "${CYAN}=====================================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script with sudo:${NC}"
  echo -e "sudo bash \$0"
  exit 1
fi

# Detect actual user (supports standard Ubuntu/Oracle cloud-init VM environments)
if id "ubuntu" &>/dev/null; then
  REAL_USER="ubuntu"
else
  REAL_USER=${SUDO_USER:-$USER}
fi
REAL_HOME=$(eval echo "~$REAL_USER")

# Detect total system RAM and auto-create swap if under 2GB (critical for 1GB AMD Always Free Micro VMs)
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_MEM" -lt 2000 ]; then
  echo -e "${YELLOW}Low memory detected (${TOTAL_MEM}MB). Auto-configuring 4GB swap space...${NC}"
  if [ ! -f /swapfile ]; then
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${GREEN}4GB Swap file created and enabled.${NC}"
  else
    echo -e "${GREEN}Swap file already exists. Skipping...${NC}"
  fi
fi

echo -e "${CYAN}[1/5] Updating system packages...${NC}"
apt-get update -y
apt-get upgrade -y

echo -e "${CYAN}[2/5] Installing core dependencies...${NC}"
apt-get install -y curl git apt-transport-https ca-certificates gnupg lsb-release ufw

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo -e "${CYAN}[3/5] Installing Docker using official installer...${NC}"
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm -f get-docker.sh
else
  echo -e "${GREEN}[3/5] Docker is already installed. Skipping...${NC}"
fi

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add real user to the docker group so sudo is not needed later
usermod -aG docker "$REAL_USER"
echo -e "${GREEN}Added user '$REAL_USER' to the 'docker' group.${NC}"

# Install Portainer CE
if ! docker ps -a --format '{{.Names}}' | grep -Eq "^portainer$"; then
  echo -e "${CYAN}[4/5] Deploying Portainer CE...${NC}"
  docker volume create portainer_data
  docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
else
  echo -e "${GREEN}[4/5] Portainer CE is already running. Skipping...${NC}"
fi

# Set up directories and permissions
echo -e "${CYAN}[5/5] Preparing deployment directory...${NC}"
mkdir -p /opt/stremio-stack/data
chown -R "$REAL_USER":"$REAL_USER" /opt/stremio-stack
echo -e "${GREEN}Created directory '/opt/stremio-stack' owned by '$REAL_USER'.${NC}"

# Configure firewall
echo -e "${CYAN}Configuring firewall (UFW)...${NC}"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 9443/tcp
ufw allow 8000/tcp
echo "y" | ufw enable

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}            Bootstrap Complete Successfully!          ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e "Your VPS is now configured and ready."
echo -e ""
echo -e "${CYAN}Web Console Access:${NC}"
echo -e "  * Portainer Admin Panel: ${YELLOW}https://<your-vps-ip>:9443${NC}"
echo -e "    (Accept the self-signed certificate warning on first load)"
echo -e ""
echo -e "${CYAN}Next Steps:${NC}"
echo -e "  1. Open the Portainer link and set up your admin username/password."
echo -e "  2. Log out of this shell session and log back in (forces 'docker' group permissions to apply)."
echo -e "  3. Run the installer script locally on your computer to deploy:"
echo -e "     ${YELLOW}.\\scripts\\setup.ps1${NC}"
echo -e "=====================================================\n"
