# Pipeline Monitor

A Go CLI tool for monitoring Azure DevOps pipeline runs in real-time.

## Features

- **Watch** - Real-time pipeline monitoring with failure alerts
- **Status** - Pipeline status summary table
- **Metrics** - Performance analytics (pass rate, duration trends)
- **Slack notifications** - Alert on failures via webhook

## Build

```bash
cd tools/pipeline-monitor
go build -o pipeline-monitor .
```

## Usage

```bash
export AZDO_ORG_URL="https://dev.azure.com/myorg"
export AZDO_PAT="your-pat-token"
export AZDO_PROJECT="MyProject"

# Watch all pipelines
./pipeline-monitor watch --interval 30

# Show status of failed/running pipelines
./pipeline-monitor status --top 20

# Show metrics for the last 30 days
./pipeline-monitor metrics --days 30
```
