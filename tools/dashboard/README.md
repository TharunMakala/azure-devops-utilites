# Azure DevOps Dashboard

Project metrics dashboard with terminal, HTML, and JSON output modes.

## Metrics

- **Pipeline Health**: Success rates, failure counts, average durations
- **Pull Requests**: Merge rates, review times, active/abandoned counts
- **Work Items**: Counts by state and type

## Usage

```bash
pip install -r requirements.txt

# Terminal dashboard
python dashboard.py terminal --days 7

# HTML report
python dashboard.py html --output report.html

# JSON export
python dashboard.py json-export --days 30 > metrics.json
```
