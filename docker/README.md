# Docker Configurations

## Self-Hosted Agent

Build and run a containerized Azure Pipelines agent:

```bash
cd docker/agent
cp .env.example .env  # Configure your org URL and PAT
docker compose up -d
```

Scale agents horizontally:
```bash
docker compose up -d --scale azure-agent=5
```

## Dev Container

VS Code development container with all tools pre-installed. Open the repo in VS Code and select "Reopen in Container".
