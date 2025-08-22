# Self-Hosted Agent Setup Guide

Use self-hosted agents when you need:
- Access to private network resources (databases, internal APIs)
- Custom tools or large cached SDKs
- Specific hardware (GPU, high memory)
- Tighter control over the build environment

## Option 1: VM Scale Set Agent Pool (Recommended)

The VMSS agent pool automatically scales agents in/out based on pipeline demand. Azure DevOps manages the agent lifecycle.

### Deploy infrastructure

```bash
az group create --name rg-devops-agents --location eastus

az deployment group create \
    --resource-group rg-devops-agents \
    --template-file infrastructure/bicep/main.bicep \
    --parameters @infrastructure/bicep/parameters/dev.json \
    --parameters agentAdminPassword="SECURE_PASSWORD"
```

### Register the VMSS pool in Azure DevOps

1. Go to **Organization Settings > Agent pools > Add pool**
2. Select **Azure virtual machine scale set**
3. Choose the VMSS deployed above
4. Set **Maximum agents** and **Recycle agent after each use**

---

## Option 2: Single Linux VM (Quick Start)

Use the `manage-agents.sh` script to install and manage an agent on any Linux host.

### Install

```bash
sudo ./scripts/bash/manage-agents.sh install \
    --org   https://dev.azure.com/YOUR_ORG \
    --pat   "$ADO_PAT" \
    --pool  MyPool \
    --agent "$(hostname)"
```

### Manage

```bash
sudo ./scripts/bash/manage-agents.sh status
sudo ./scripts/bash/manage-agents.sh stop
sudo ./scripts/bash/manage-agents.sh start
sudo ./scripts/bash/manage-agents.sh uninstall
```

---

## Option 3: Docker Agent

Run agents in containers for ephemeral, reproducible environments.

```dockerfile
FROM ubuntu:22.04

ARG AGENT_VERSION=3.245.0
ARG TARGETARCH=x64

RUN apt-get update && apt-get install -y curl git jq libicu70 && \
    curl -fsSL https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-${TARGETARCH}-${AGENT_VERSION}.tar.gz \
    | tar -xz -C /azp

WORKDIR /azp
COPY start.sh .
RUN chmod +x start.sh
CMD ["./start.sh"]
```

`start.sh` configures and runs the agent on container start.

---

## Maintenance

### Remove offline agents

```powershell
.\scripts\powershell\Manage-BuildAgents.ps1 `
    -Organization myorg `
    -PoolName     MyPool `
    -Action       DeleteOffline `
    -PersonalAccessToken $env:ADO_PAT
```

### Update agent version

For VMSS pools: update the `AGENT_VERSION` in `manage-agents.sh` and redeploy.

For single VMs: uninstall the current agent, then reinstall with the new version.

### Monitor agent health

- **Organization Settings > Agent pools > [Pool] > Agents** shows online/offline status.
- Set up alerts on agent count via Azure Monitor if using VMSS.

---

## Agent Capabilities

Capabilities are key-value pairs that agents advertise. Use them to route jobs to the right agents:

```yaml
# In your pipeline, demand a specific capability
pool:
  name: MyPool
  demands:
    - dotnet8
    - docker
```

Add custom capabilities in **Organization Settings > Agent pools > [Agent] > Capabilities**.
