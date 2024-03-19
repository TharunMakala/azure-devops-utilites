# CI Pipelines

Language-specific Continuous Integration pipeline definitions.

| File | Stack | Triggers |
|------|-------|----------|
| `dotnet-ci.yml` | .NET 8 | `main`, `develop`, PRs |
| `node-ci.yml` | Node.js 20 LTS | `main`, `develop`, PRs |
| `python-ci.yml` | Python 3.12 | `main`, `develop`, PRs |

## Setup

1. Copy the relevant pipeline file to your project root as `azure-pipelines.yml`, or reference it from your project pipeline using `extends`.
2. Configure the required variable group (see each file's `variables` section).
3. Register the pipeline in Azure DevOps under **Pipelines > New Pipeline**.
