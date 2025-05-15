# Configuration Manager

Manages multi-environment configurations with validation, drift detection, and promotion workflows.

## Commands

| Command | Description |
|---------|-------------|
| `init` | Generate sample config files for all environments |
| `validate` | Validate config against environment constraints |
| `drift` | Detect configuration differences between environments |
| `show` | Display config tree for all environments |

## Usage

```bash
pip install -r requirements.txt

# Initialize sample configs
python config_manager.py init

# Validate production config
python config_manager.py validate --env production

# Check drift between staging and production
python config_manager.py drift --base staging --target production

# Show all configs
python config_manager.py show
```
