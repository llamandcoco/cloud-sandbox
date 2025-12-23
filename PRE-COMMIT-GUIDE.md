# Pre-commit Configuration Guide

## Overview
pre-commit is a framework that automatically runs code quality checks before Git commits.
The cloud-sandbox project uses it to validate Terragrunt configuration files.

## Quick Start

### Step 1: Install pre-commit
```bash
# macOS
brew install pre-commit

# Or using pip (all OS)
pip install pre-commit
```

### Step 2: Install Required Tools
```bash
# macOS
brew install terragrunt

# Or individually:
# - Terragrunt: https://terragrunt.gruntwork.io/docs/getting-started/install/
```

### Step 3: Automatic Setup (Recommended)
```bash
cd cloud-sandbox
chmod +x .pre-commit-setup.sh
./.pre-commit-setup.sh
```

### Or Manual Setup
```bash
cd cloud-sandbox
pre-commit install
pre-commit install --hook-type commit-msg
pre-commit autoupdate
```

## Usage

### Automatic Execution
```bash
# Hooks run automatically on git commit
git add .
git commit -m "feat: add new stack"
# → pre-commit automatically runs checks
```

### Manual Execution
```bash
# Run on specific files
pre-commit run --files aws/10-plt/03-networking/terragrunt.hcl

# Run on all files (takes time)
pre-commit run --all-files

# Run specific hooks only
pre-commit run trailing-whitespace --all-files
pre-commit run check-yaml --all-files
```

### Skip Hooks
```bash
# Bypass hooks if needed (not recommended)
git commit --no-verify

# Or using environment variable
SKIP=trailing-whitespace git commit -m "..."
```

## Included Hooks

### File Format Checks
| Hook | Purpose |
|------|---------|
| `trailing-whitespace` | Remove trailing whitespace |
| `end-of-file-fixer` | Ensure files end with newline |
| `check-yaml` | Validate YAML syntax |
| `check-json` | Validate JSON syntax |
| `check-merge-conflict` | Detect merge conflict markers |
| `detect-private-key` | Detect private key files |

### Commit Message
| Hook | Rule |
|------|------|
| `conventional-pre-commit` | Enforce Conventional Commits format |

**Format Examples:**
```
feat: add echo worker deployment
fix: resolve SQS policy timeout
docs: update architecture diagram
chore: update Terragrunt version
```

## Customize Hook Configuration

Edit `.pre-commit-config.yaml` to customize:

```yaml
# Disable specific hooks
  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v4.3.0
    hooks:
      - id: conventional-pre-commit
        stages: [manual]  # Change to manual execution
```

## Troubleshooting

### 1. "Permission denied" error
```bash
# Make setup script executable
chmod +x .pre-commit-setup.sh

# Re-run setup
./.pre-commit-setup.sh
```

### 2. Commit message validation fails
```bash
# Use Conventional Commits format
# Examples: feat:, fix:, docs:, chore:, refactor:
git commit -m "feat: describe your change"

# Or skip for now
SKIP=conventional-pre-commit git commit -m "..."
```

### 3. "files were modified by this hook"
```bash
# Pre-commit auto-fixed formatting issues
# Review and stage the changes
git add .
git commit -m "..."
```

## Performance Optimization

### 1. Run checks only on changed files (default)
Pre-commit runs only on staged files, not entire repo.

### 2. Skip checks on specific file types
Edit `.pre-commit-config.yaml`:
```yaml
exclude: |
  (?x)^(
    \.terragrunt-cache/|
    \.terraform/|
    node_modules/
  )
```

### 3. Use pre-push hook (optional)
```bash
# Run hooks before push instead of commit
pre-commit install -t pre-push

# Then add to .pre-commit-config.yaml:
# stages: [pre-push]
```

## CI/CD Integration

GitHub Actions already run checks:
- `terragrunt-check.yml` - Runs validation on PRs
- `terragrunt-fmt-fix.yml` - Auto-fixes formatting on main branch

Local pre-commit hooks are **additional tools to speed up local development**.

## Team Standardization

Keep all developers in sync:
```bash
# Update to latest hook versions (regularly)
pre-commit autoupdate

# Commit updated versions
git add .pre-commit-config.yaml
git commit -m "chore: update pre-commit hooks"
```

## Additional Resources
- [Pre-commit Documentation](https://pre-commit.com/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [General Pre-commit Hooks](https://github.com/pre-commit/pre-commit-hooks)
