# Troubleshooting

## Pipelines

### "No hosted parallelism has been purchased or granted"

**Cause:** Free Microsoft-hosted parallel jobs require a one-time approval for new organizations.

**Fix:**
1. Request free parallelism: `https://aka.ms/azpipelines-parallelism-request`
2. Or use self-hosted agents (no parallelism limit).
3. Or purchase parallel jobs under **Organization Settings > Billing**.

---

### Pipeline queued but never starts

**Checklist:**
- All agents in the pool are offline → restart or provision agents.
- The pipeline demands a capability no agent has → check agent capabilities.
- The pipeline is waiting for a manual approval → check **Environments** for pending approvals.
- Concurrency limit reached → check parallel job count.

---

### "Resource not authorized" on service connection / variable group

**Cause:** The pipeline hasn't been granted access to the resource.

**Fix:**
1. Navigate to the failing resource (service connection, variable group, environment).
2. Go to **Security** or **Pipeline permissions**.
3. Add the pipeline or grant access to all pipelines.

---

### YAML syntax errors at queue time

Use the Azure DevOps YAML validator before committing:

```bash
az pipelines run --name "My Pipeline" --open   # Previews without running
```

Or install the Azure Pipelines extension for VS Code for inline validation.

---

### Task version not found

**Cause:** A task version referenced in YAML doesn't exist (e.g., `@3` when only `@2` is available).

**Fix:** Check available task versions at **Organization Settings > Extensions** or use `az pipelines task list`.

---

## Agents

### Agent shows as offline

1. SSH into the agent machine.
2. Check service status: `sudo ./scripts/bash/manage-agents.sh status`
3. Check agent logs: `tail -n 100 /opt/azure-devops-agent/_diag/Agent_*.log`
4. Restart: `sudo ./scripts/bash/manage-agents.sh start`

---

### "Access denied" when agent tries to checkout

**Cause:** The Project Build Service account lacks read access to the repository.

**Fix:** In the repo settings, grant **Contribute** (for PR pipelines) or **Read** to `[Project] Build Service`.

---

### Agent runs out of disk space

Build artifacts and source caches accumulate on self-hosted agents.

```bash
# Clean all pipeline working directories older than 7 days
find /opt/azure-devops-agent/_work -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +
```

Add a scheduled pipeline or cron job to automate this.

---

## Scripts

### PowerShell: "Az module not found"

```powershell
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
```

### Bash: "az: command not found"

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az extension add --name azure-devops
```

### REST API returns 401 Unauthorized

- Verify the PAT hasn't expired (check at `https://dev.azure.com/YOUR_ORG/_usersSettings/tokens`).
- Confirm the PAT has the required scopes for the operation.
- Ensure the PAT belongs to a user with sufficient ADO permissions.

### REST API returns 403 Forbidden

The authenticated user doesn't have permission for the requested operation. Check the user's role in **Project Settings > Permissions**.

---

## Infrastructure

### Bicep deployment fails: "StorageAccountName already taken"

Storage account names must be globally unique. Change `projectName` in your parameters file to something more unique.

### VMSS agents don't register in Azure DevOps

1. Confirm the VMSS pool is correctly linked in **Organization Settings > Agent pools**.
2. Verify the agent identity has network access to `dev.azure.com` (check NSG rules).
3. Check VMSS instance logs in Azure Monitor.

---

## Getting More Help

- [Azure DevOps Status](https://status.dev.azure.com/) — check for ongoing incidents.
- [Azure DevOps Developer Community](https://developercommunity.visualstudio.com/AzureDevOps)
- [Stack Overflow — azure-devops tag](https://stackoverflow.com/questions/tagged/azure-devops)
- Open an issue in this repository for utility-specific problems.
