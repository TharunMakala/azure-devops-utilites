# Helm Charts

## Azure DevOps Agent

Deploy self-hosted Azure Pipelines agents on Kubernetes with auto-scaling.

### Install

```bash
helm install azure-agent helm/azure-agent \
  --set azureDevOps.orgUrl="https://dev.azure.com/myorg" \
  --set azureDevOps.pat="your-pat-token" \
  --set azureDevOps.pool="K8s-Pool" \
  --namespace azure-devops --create-namespace
```

### Features

- Horizontal Pod Autoscaler (CPU/memory-based)
- Persistent workspace volumes
- Docker-in-Docker sidecar support
- Pod Disruption Budget for safe upgrades
- Liveness and readiness probes
