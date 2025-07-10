# Pipeline Best Practices

## Security

### Never store secrets in YAML

```yaml
# BAD — secret visible in repo history
variables:
  API_KEY: "s3cr3t"

# GOOD — reference a variable group linked to Key Vault
variables:
  - group: my-keyvault-vars
```

### Pin task versions

```yaml
# BAD — picks up breaking changes on next run
- task: AzureCLI@latest

# GOOD — deterministic, upgrade intentionally
- task: AzureCLI@2
```

### Use workload identity federation for service connections

Prefer **Workload Identity Federation** over secret-based service principals. No secrets to rotate, no expiry surprises.

### Restrict pipeline permissions

- Set each pipeline to use only the agent pools and service connections it needs.
- Use **Environment** resource locks so only designated pipelines can deploy to production.

---

## Performance

### Cache dependencies

```yaml
- task: Cache@2
  inputs:
    key: 'npm | "$(Agent.OS)" | package-lock.json'
    restoreKeys: 'npm | "$(Agent.OS)"'
    path: $(npm_config_cache)
```

### Parallelize independent jobs

```yaml
jobs:
  - job: UnitTests
  - job: LintCheck       # Runs in parallel with UnitTests
  - job: SecurityScan    # Runs in parallel with both
```

### Use `--no-restore` / `--no-build` flags

After the restore and build steps complete, skip them in subsequent steps:

```yaml
- script: dotnet build --no-restore
- script: dotnet test  --no-build --no-restore
```

---

## Reliability

### Set `timeoutInMinutes` on every job

```yaml
jobs:
  - job: Build
    timeoutInMinutes: 30   # Fail fast; don't let hung jobs block the queue
```

### Use `continueOnError: false` deliberately

Only set `continueOnError: true` on non-critical steps like reporting tasks. Always fail on build and test errors.

### Add `condition` to cleanup steps

```yaml
- task: PublishTestResults@2
  condition: always()     # Publish results even if tests failed
```

---

## Maintainability

### Use templates for shared logic

Extract repeated step sequences into `pipelines/templates/` and reference them with `template:`.

### Use `parameters` with types and `values`

```yaml
parameters:
  - name: environment
    type: string
    values: [dev, staging, production]   # Validates at queue time
```

### Keep stages focused

Each stage should do one thing: Build, Test, SecurityScan, Deploy. Avoid multi-purpose stages.

### Document required variables

Add a comment block at the top of every pipeline listing required variable groups and service connections. Operators shouldn't need to read the whole file to set up a pipeline.

---

## Monitoring

- Enable **Pipeline Analytics** in your ADO project to track pass rates and duration trends.
- Set up **Service Hooks** to post pipeline failures to Teams or Slack.
- Use **Build Tags** (`$(Build.BuildId)`, environment name) on deployed resources for traceability.
