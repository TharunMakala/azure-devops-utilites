# Pipelines

Reusable Azure Pipelines YAML definitions organized by purpose.

## Directory Structure

```
pipelines/
├── templates/          # Shared, reusable pipeline step templates
├── ci/                 # Continuous Integration pipeline definitions
└── cd/                 # Continuous Deployment pipeline definitions
```

## Usage

### Templates

Templates are designed to be referenced from your main pipeline files using the `template` keyword:

```yaml
steps:
  - template: ../templates/build-template.yml
    parameters:
      buildConfiguration: 'Release'
```

### CI Pipelines

Import or adapt any CI pipeline from `ci/` into your project's `azure-pipelines.yml`. Each pipeline is self-contained and parameterized.

### CD Pipelines

CD pipelines in `cd/` handle multi-environment deployments with approval gates. Configure environment names and service connections before use.

## Best Practices

- Always pin task versions (e.g., `AzureCLI@2`) to avoid unexpected breaking changes.
- Store secrets in Variable Groups linked to Azure Key Vault, never in YAML.
- Use `dependsOn` and `condition` to control stage execution flow.
- Leverage `environments` with approval checks for production deployments.

## References

- [Azure Pipelines documentation](https://learn.microsoft.com/en-us/azure/devops/pipelines/)
- [YAML schema reference](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/)
