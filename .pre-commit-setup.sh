#!/bin/bash
# Pre-commit setup script for cloud-sandbox
# Installs and configures pre-commit hooks for Terragrunt development

set -e

echo "🔧 Setting up pre-commit hooks..."

# Check if pre-commit is installed
if ! command -v pre-commit &> /dev/null; then
    echo "📦 Installing pre-commit..."
    pip install pre-commit
fi

# Check if required tools are installed
REQUIRED_TOOLS=(terraform terragrunt tflint trivy)
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "⚠️  Warning: $tool not found. Please install it:"
        case $tool in
            terraform)
                echo "  brew install terraform  # macOS"
                echo "  choco install terraform  # Windows"
                ;;
            terragrunt)
                echo "  brew install terragrunt  # macOS"
                ;;
            tflint)
                echo "  brew install tflint  # macOS"
                ;;
            trivy)
                echo "  brew install trivy  # macOS"
                ;;
        esac
    fi
done

# Install pre-commit hooks
echo "📝 Installing pre-commit hooks..."
pre-commit install
pre-commit install --hook-type commit-msg

# Update hook repositories
echo "🔄 Updating hook repositories..."
pre-commit autoupdate

# Test run on all files (optional, takes time)
echo "🧪 Running pre-commit on all files (this may take a while)..."
pre-commit run --all-files --verbose || echo "⚠️  Some checks failed, but hooks are installed"

echo ""
echo "✅ Pre-commit setup complete!"
echo ""
echo "📌 Usage:"
echo "  - Hooks will run automatically on 'git commit'"
echo "  - Run manually: pre-commit run --all-files"
echo "  - Skip hooks: git commit --no-verify"
echo "  - Update hooks: pre-commit autoupdate"
