# Tools

Python utilities for Azure DevOps automation and reporting.

## Setup

```bash
cd tools/
python3 -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## Scripts

| Script | Description |
|--------|-------------|
| `az_devops_helper.py` | CLI tool for common ADO operations: project info, pipeline runs, work item queries |

## Usage

```bash
# Show all projects in the organization
python az_devops_helper.py projects --org myorg --pat $ADO_PAT

# List recent pipeline runs
python az_devops_helper.py runs --org myorg --project MyProject --pat $ADO_PAT --limit 20

# Export work items to CSV
python az_devops_helper.py workitems --org myorg --project MyProject \
    --pat $ADO_PAT --query "SELECT [Id],[Title],[State] FROM WorkItems WHERE [State] = 'Active'" \
    --output active-items.csv
```
