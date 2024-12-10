#!/usr/bin/env bash
# =============================================================================
# create-service-connection.sh
# Create an Azure Resource Manager service connection in Azure DevOps.
# Requires: Azure CLI + azure-devops extension, logged-in session.
# =============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Create an Azure Resource Manager service connection in Azure DevOps.

Options:
  -o, --org          Azure DevOps organization URL (e.g. https://dev.azure.com/myorg)
  -p, --project      Azure DevOps project name
  -n, --name         Service connection display name
  -s, --subscription Azure subscription ID
  -t, --tenant       Azure tenant ID
  -r, --resource-group  (optional) Scope to a specific resource group
  -h, --help         Show this help message

Examples:
  $0 --org https://dev.azure.com/myorg --project MyProject \\
     --name "Azure Production" --subscription <sub-id> --tenant <tenant-id>

  $0 --org https://dev.azure.com/myorg --project MyProject \\
     --name "Azure Dev RG" --subscription <sub-id> --tenant <tenant-id> \\
     --resource-group rg-dev
EOF
    exit 0
}

# ── Parse arguments ───────────────────────────────────────────────────────────
ORG=""; PROJECT=""; NAME=""; SUBSCRIPTION=""; TENANT=""; RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org)            ORG="$2";            shift 2 ;;
        -p|--project)        PROJECT="$2";        shift 2 ;;
        -n|--name)           NAME="$2";           shift 2 ;;
        -s|--subscription)   SUBSCRIPTION="$2";   shift 2 ;;
        -t|--tenant)         TENANT="$2";         shift 2 ;;
        -r|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
        -h|--help)           usage ;;
        *) error "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ── Validation ────────────────────────────────────────────────────────────────
[[ -z "$ORG" ]]          && error "--org is required."
[[ -z "$PROJECT" ]]      && error "--project is required."
[[ -z "$NAME" ]]         && error "--name is required."
[[ -z "$SUBSCRIPTION" ]] && error "--subscription is required."
[[ -z "$TENANT" ]]       && error "--tenant is required."

# ── Pre-flight checks ─────────────────────────────────────────────────────────
command -v az &>/dev/null || error "Azure CLI not found. Install it first."
az account show &>/dev/null || error "Not logged in to Azure. Run 'az login'."

info "Creating service connection '$NAME' in project '$PROJECT'..."

# ── Build scope ───────────────────────────────────────────────────────────────
SCOPE_LEVEL="Subscription"
SCOPE_VALUE="/subscriptions/$SUBSCRIPTION"
if [[ -n "$RESOURCE_GROUP" ]]; then
    SCOPE_LEVEL="AzureResourceGroup"
    SCOPE_VALUE="/subscriptions/$SUBSCRIPTION/resourceGroups/$RESOURCE_GROUP"
    info "Scoping to resource group: $RESOURCE_GROUP"
fi

# ── Create service connection ─────────────────────────────────────────────────
ENDPOINT_ID=$(az devops service-endpoint azurerm create \
    --azure-rm-service-principal-authentication-scheme WorkloadIdentityFederation \
    --azure-rm-subscription-id   "$SUBSCRIPTION" \
    --azure-rm-subscription-name "$(az account show --subscription "$SUBSCRIPTION" --query name -o tsv)" \
    --azure-rm-tenant-id         "$TENANT" \
    --name                       "$NAME" \
    --org                        "$ORG" \
    --project                    "$PROJECT" \
    --query id -o tsv)

# ── Grant pipeline access ─────────────────────────────────────────────────────
info "Granting access to all pipelines..."
az devops service-endpoint update \
    --id      "$ENDPOINT_ID" \
    --enable-for-all true \
    --org     "$ORG" \
    --project "$PROJECT" \
    --output  none

success "Service connection '$NAME' created (ID: $ENDPOINT_ID)."
echo ""
echo "View it at: ${ORG}/${PROJECT}/_settings/adminservices?resourceId=${ENDPOINT_ID}"
