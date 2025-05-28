# Policies

Configuration templates for Azure DevOps branch policies and pipeline permissions.

## Files

| File | Description |
|------|-------------|
| `branch-policies.json` | Branch protection policy configuration (PR reviews, build validation, merge strategy) |
| `pipeline-permissions.json` | Pipeline security and permission matrix |

## Applying Branch Policies

Branch policies must be applied via the Azure DevOps REST API or UI. Use the PowerShell helper:

```powershell
# Apply branch policies to a repository
$policy = Get-Content ./policies/branch-policies.json | ConvertFrom-Json
.\scripts\powershell\Invoke-AzureDevOpsApi.ps1 `
    -Organization myorg `
    -ApiPath "/MyProject/_apis/policy/configurations?api-version=7.1" `
    -Method POST `
    -Body $policy `
    -PersonalAccessToken $env:ADO_PAT
```

Or via Azure CLI:

```bash
az devops invoke \
    --area policy \
    --resource configurations \
    --http-method POST \
    --in-file policies/branch-policies.json \
    --api-version 7.1
```

## Recommended Policies for Main Branch

- Minimum 2 reviewer approvals
- Reset votes on new pushes
- Require linked work items
- Build validation (CI pipeline must pass)
- Comment resolution required
- Squash merge only (clean history)
