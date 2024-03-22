#!/bin/bash
set -euo pipefail

: "${AZP_URL:?AZP_URL is required}"
: "${AZP_TOKEN:?AZP_TOKEN is required}"
: "${AZP_POOL:=Default}"
: "${AZP_AGENT_NAME:=$(hostname)}"
: "${AZP_WORK:=_work}"

cleanup() {
  trap "" EXIT
  if [ -e config.sh ]; then
    echo "Removing agent..."
    ./config.sh remove --unattended --auth pat --token "${AZP_TOKEN}"
  fi
}

print_header() {
  echo -e "\n=========================================="
  echo -e "  $1"
  echo -e "==========================================\n"
}

# Download agent if not already present
if [ ! -f "bin/Agent.Listener" ]; then
  print_header "Downloading Azure Pipelines agent..."
  
  AZP_AGENT_PACKAGES=$(curl -fsSL \
    -H "Authorization: Bearer ${AZP_TOKEN}" \
    "${AZP_URL}/_apis/distributedtask/packages/agent?platform=linux-x64&top=1" \
    2>/dev/null)
  
  AZP_AGENT_PACKAGE_URL=$(echo "${AZP_AGENT_PACKAGES}" | jq -r '.value[0].downloadUrl')
  
  if [ -z "${AZP_AGENT_PACKAGE_URL}" ] || [ "${AZP_AGENT_PACKAGE_URL}" = "null" ]; then
    echo "Error: Could not determine agent download URL."
    exit 1
  fi
  
  curl -fsSL "${AZP_AGENT_PACKAGE_URL}" | tar -xz &
  wait $!
fi

print_header "Configuring agent: ${AZP_AGENT_NAME}"

./config.sh \
  --unattended \
  --url "${AZP_URL}" \
  --auth pat \
  --token "${AZP_TOKEN}" \
  --pool "${AZP_POOL}" \
  --agent "${AZP_AGENT_NAME}" \
  --work "${AZP_WORK}" \
  --replace \
  --acceptTeeEula

trap cleanup EXIT

print_header "Running agent: ${AZP_AGENT_NAME}"
chmod +x run.sh
exec ./run.sh "$@"
