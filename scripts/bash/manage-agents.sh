#!/usr/bin/env bash
# =============================================================================
# manage-agents.sh
# Install, configure, and manage Azure Pipelines self-hosted agents on Linux.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

AGENT_VERSION="3.245.0"   # Pin agent version for reproducibility
AGENT_DIR="/opt/azure-devops-agent"
AGENT_USER="azagent"

usage() {
    cat <<EOF
Usage: $0 <COMMAND> [OPTIONS]

Commands:
  install    Download and configure a new self-hosted agent
  start      Start the agent service
  stop       Stop the agent service
  status     Show agent service status
  uninstall  Remove the agent and service

Install options:
  --org       Azure DevOps organization URL (https://dev.azure.com/myorg)
  --pat       Personal Access Token with "Agent Pools > Read & Manage"
  --pool      Agent pool name (default: Default)
  --agent     Agent name (default: hostname)
  --dir       Installation directory (default: $AGENT_DIR)

Examples:
  $0 install --org https://dev.azure.com/myorg --pat \$ADO_PAT --pool MyPool
  $0 status
  $0 stop
  $0 uninstall
EOF
    exit 0
}

[[ $# -eq 0 ]] && usage

COMMAND="$1"; shift

case "$COMMAND" in
  install)
    ORG=""; PAT=""; POOL="Default"; AGENT_NAME="$(hostname)"; INSTALL_DIR="$AGENT_DIR"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --org)   ORG="$2";        shift 2 ;;
            --pat)   PAT="$2";        shift 2 ;;
            --pool)  POOL="$2";       shift 2 ;;
            --agent) AGENT_NAME="$2"; shift 2 ;;
            --dir)   INSTALL_DIR="$2";shift 2 ;;
            *) error "Unknown option: $1" ;;
        esac
    done

    [[ -z "$ORG" ]] && error "--org is required."
    [[ -z "$PAT" ]] && error "--pat is required."

    # Create dedicated user
    if ! id "$AGENT_USER" &>/dev/null; then
        info "Creating agent user '$AGENT_USER'..."
        useradd -m -s /bin/bash "$AGENT_USER"
    fi

    # Download agent package
    AGENT_PKG="vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz"
    AGENT_URL="https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/${AGENT_PKG}"
    TMP_DIR=$(mktemp -d)

    info "Downloading agent v${AGENT_VERSION}..."
    curl -fsSL "$AGENT_URL" -o "$TMP_DIR/$AGENT_PKG"

    info "Extracting to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    tar xzf "$TMP_DIR/$AGENT_PKG" -C "$INSTALL_DIR"
    chown -R "$AGENT_USER":"$AGENT_USER" "$INSTALL_DIR"
    rm -rf "$TMP_DIR"

    # Configure agent
    info "Configuring agent '$AGENT_NAME' in pool '$POOL'..."
    sudo -u "$AGENT_USER" "$INSTALL_DIR/config.sh" \
        --unattended \
        --url           "$ORG" \
        --auth          pat \
        --token         "$PAT" \
        --pool          "$POOL" \
        --agent         "$AGENT_NAME" \
        --replace \
        --acceptTeeEula

    # Install and start systemd service
    info "Installing systemd service..."
    "$INSTALL_DIR/svc.sh" install "$AGENT_USER"
    "$INSTALL_DIR/svc.sh" start

    success "Agent '$AGENT_NAME' installed and running."
    ;;

  start)
    [[ -f "$AGENT_DIR/svc.sh" ]] || error "Agent not installed at $AGENT_DIR."
    "$AGENT_DIR/svc.sh" start && success "Agent service started."
    ;;

  stop)
    [[ -f "$AGENT_DIR/svc.sh" ]] || error "Agent not installed at $AGENT_DIR."
    "$AGENT_DIR/svc.sh" stop && success "Agent service stopped."
    ;;

  status)
    [[ -f "$AGENT_DIR/svc.sh" ]] || error "Agent not installed at $AGENT_DIR."
    "$AGENT_DIR/svc.sh" status
    ;;

  uninstall)
    warn "This will remove the agent service and configuration."
    read -rp "Continue? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { info "Aborted."; exit 0; }
    [[ -f "$AGENT_DIR/svc.sh" ]] || error "Agent not installed at $AGENT_DIR."
    "$AGENT_DIR/svc.sh" stop  2>/dev/null || true
    "$AGENT_DIR/svc.sh" uninstall 2>/dev/null || true
    "$AGENT_DIR/config.sh" remove --unattended 2>/dev/null || true
    success "Agent uninstalled. You may now delete $AGENT_DIR."
    ;;

  --help|-h) usage ;;
  *) error "Unknown command: $COMMAND. Use --help for usage." ;;
esac
