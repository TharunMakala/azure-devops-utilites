# Compliance Checker

Validates Azure DevOps project configurations against security and compliance policies.

## Checks

| ID | Category | Check |
|----|----------|-------|
| BP-001 | Branch Policies | Minimum 2 reviewers on default branch |
| BP-002 | Branch Policies | Build validation required for PRs |
| SC-001 | Service Connections | Workload Identity Federation preferred |
| SC-002 | Service Connections | Shared connections flagged |
| VG-001 | Variable Groups | Sensitive variables must be secrets |
| VG-002 | Variable Groups | Key Vault linkage recommended |
| PL-001 | Pipelines | YAML pipelines preferred over classic |

## Usage

```bash
pip install -r requirements.txt

python checker.py \
  --org "https://dev.azure.com/myorg" \
  --pat "$AZDO_PAT" \
  --project "MyProject" \
  --fail-on-critical
```

## CI Integration

Add to your pipeline to enforce compliance on every PR:
```yaml
- script: python tools/compliance-checker/checker.py --fail-on-critical
  env:
    AZDO_ORG_URL: $(System.CollectionUri)
    AZDO_PAT: $(System.AccessToken)
    AZDO_PROJECT: $(System.TeamProject)
```
