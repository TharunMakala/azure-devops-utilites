#!/usr/bin/env bash
# =============================================================================
# setup-environment.sh
# Bootstrap a Linux machine with Azure CLI, ADO extension, Docker, and kubectl.
# Tested on Ubuntu 22.04 / 24.04 and Debian 12.
# =============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (sudo ./setup-environment.sh)."
    exit 1
fi

# ── OS detection ─────────────────────────────────────────────────────────────
if ! grep -qi 'ubuntu\|debian' /etc/os-release 2>/dev/null; then
    warn "This script is designed for Ubuntu/Debian. Proceed with caution."
fi

info "Updating package lists..."
apt-get update -qq

# ── Common utilities ─────────────────────────────────────────────────────────
info "Installing common utilities..."
apt-get install -y -qq \
    curl wget git jq unzip apt-transport-https \
    ca-certificates gnupg lsb-release software-properties-common

# ── Azure CLI ─────────────────────────────────────────────────────────────────
if command -v az &>/dev/null; then
    success "Azure CLI already installed: $(az version --query '\"azure-cli\"' -o tsv)"
else
    info "Installing Azure CLI..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    success "Azure CLI installed: $(az version --query '\"azure-cli\"' -o tsv)"
fi

# ── Azure DevOps extension ────────────────────────────────────────────────────
if az extension show --name azure-devops &>/dev/null; then
    info "Updating azure-devops extension..."
    az extension update --name azure-devops --only-show-errors
else
    info "Installing azure-devops extension..."
    az extension add --name azure-devops --only-show-errors
fi
success "azure-devops extension ready."

# ── Docker ───────────────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
    success "Docker already installed: $(docker --version)"
else
    info "Installing Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    success "Docker installed: $(docker --version)"
fi

# ── kubectl ───────────────────────────────────────────────────────────────────
if command -v kubectl &>/dev/null; then
    success "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    info "Installing kubectl..."
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
        https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
        | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    apt-get update -qq
    apt-get install -y -qq kubectl
    success "kubectl installed."
fi

# ── PowerShell ────────────────────────────────────────────────────────────────
if command -v pwsh &>/dev/null; then
    success "PowerShell already installed: $(pwsh --version)"
else
    info "Installing PowerShell..."
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    wget -q "https://packages.microsoft.com/config/ubuntu/$(. /etc/os-release && echo "$VERSION_ID")/packages-microsoft-prod.deb" \
        -O /tmp/packages-microsoft-prod.deb
    dpkg -i /tmp/packages-microsoft-prod.deb
    apt-get update -qq
    apt-get install -y -qq powershell
    success "PowerShell installed: $(pwsh --version)"
fi

# ── Helm ─────────────────────────────────────────────────────────────────────
if command -v helm &>/dev/null; then
    success "Helm already installed: $(helm version --short)"
else
    info "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    success "Helm installed: $(helm version --short)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Environment setup complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo "  1. Run: az login"
echo "  2. Run: az devops configure --defaults organization=https://dev.azure.com/YOUR_ORG"
echo "  3. Add your user to the 'docker' group: usermod -aG docker \$USER"
echo ""
