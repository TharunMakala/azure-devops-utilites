# Pipeline Templates

Reusable YAML step templates shared across CI and CD pipelines.

| Template | Description |
|----------|-------------|
| `build-template.yml` | Generic build steps — restore, build, publish artifacts |
| `test-template.yml` | Run unit and integration tests, publish results and coverage |
| `deploy-template.yml` | Deploy artifacts to an Azure App Service or Kubernetes cluster |

## Parameters Reference

Each template documents its parameters at the top of the file. All parameters include types and defaults where applicable.
