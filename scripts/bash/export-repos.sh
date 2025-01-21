#!/usr/bin/env bash
# =============================================================================
# export-repos.sh
# Clone or mirror all Git repositories from an Azure DevOps project.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Clone or mirror all repositories from an Azure DevOps project.

Options:
  -o, --org        Azure DevOps organization URL
  -p, --project    Azure DevOps project name
  -d, --dir        Output directory (default: ./repos)
  -t, --pat        Personal Access Token (or set ADO_PAT env var)
  --mirror         Use --mirror for bare clones (useful for backups)
  --update         Pull latest changes for existing clones
  -h, --help       Show this help

Examples:
  $0 --org https://dev.azure.com/myorg --project MyProject --pat \$ADO_PAT
  $0 --org https://dev.azure.com/myorg --project MyProject --mirror --dir ./backup
  $0 --org https://dev.azure.com/myorg --project MyProject --update
EOF
    exit 0
}

# ── Parse args ────────────────────────────────────────────────────────────────
ORG=""; PROJECT=""; OUTPUT_DIR="./repos"; PAT="${ADO_PAT:-}"; MIRROR=false; UPDATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org)     ORG="$2";        shift 2 ;;
        -p|--project) PROJECT="$2";    shift 2 ;;
        -d|--dir)     OUTPUT_DIR="$2"; shift 2 ;;
        -t|--pat)     PAT="$2";        shift 2 ;;
        --mirror)     MIRROR=true;     shift   ;;
        --update)     UPDATE=true;     shift   ;;
        -h|--help)    usage ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ -z "$ORG" ]]     && error "--org is required."
[[ -z "$PROJECT" ]] && error "--project is required."
[[ -z "$PAT" ]]     && error "--pat or ADO_PAT env var is required."

# ── Fetch repository list ─────────────────────────────────────────────────────
info "Fetching repository list from '$PROJECT'..."
API_URL="${ORG}/${PROJECT}/_apis/git/repositories?api-version=7.1"
AUTH_HEADER="Authorization: Basic $(echo -n ":$PAT" | base64 -w0)"

REPOS_JSON=$(curl -fsSL -H "$AUTH_HEADER" "$API_URL")
REPO_COUNT=$(echo "$REPOS_JSON" | jq '.count')
info "Found $REPO_COUNT repositories."

mkdir -p "$OUTPUT_DIR"

CLONED=0; UPDATED=0; FAILED=0

while IFS=$'\t' read -r REPO_NAME CLONE_URL; do
    DEST="$OUTPUT_DIR/$REPO_NAME"
    # Embed PAT in URL for authentication
    AUTH_URL=$(echo "$CLONE_URL" | sed "s|https://|https://pat:${PAT}@|")

    if [[ -d "$DEST" ]]; then
        if $UPDATE; then
            info "Updating: $REPO_NAME"
            if $MIRROR; then
                git -C "$DEST" remote update 2>/dev/null && { success "Updated: $REPO_NAME"; ((UPDATED++)); } \
                    || { warn "Failed to update: $REPO_NAME"; ((FAILED++)); }
            else
                git -C "$DEST" pull --ff-only 2>/dev/null && { success "Updated: $REPO_NAME"; ((UPDATED++)); } \
                    || { warn "Failed to update: $REPO_NAME"; ((FAILED++)); }
            fi
        else
            warn "Skipping (already exists): $REPO_NAME  [use --update to pull latest]"
        fi
    else
        info "Cloning: $REPO_NAME"
        CLONE_FLAGS=()
        $MIRROR && CLONE_FLAGS+=(--mirror) || CLONE_FLAGS+=(--recurse-submodules)

        if git clone "${CLONE_FLAGS[@]}" "$AUTH_URL" "$DEST" 2>/dev/null; then
            success "Cloned: $REPO_NAME → $DEST"
            ((CLONED++))
        else
            warn "Failed to clone: $REPO_NAME"
            ((FAILED++))
        fi
    fi
done < <(echo "$REPOS_JSON" | jq -r '.value[] | [.name, .remoteUrl] | @tsv')

echo ""
echo -e "${GREEN}Done.${NC} Cloned: $CLONED  Updated: $UPDATED  Failed: $FAILED"
