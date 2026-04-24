#!/bin/bash
# Quick setup script for my-claude-skills contributors

set -e

echo "🚀 Setting up my-claude-skills dev tools..."

# Check if brew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Error: Homebrew is not installed."
    echo ""
    echo "To fix this, install Homebrew from: https://brew.sh"
    echo ""
    echo "After fixing this, run setup again:"
    echo "  ./setup.sh"
    exit 1
fi

echo "✓ Homebrew found: $(brew --version | head -1)"

# Install markdownlint-cli2
echo "📦 Installing markdownlint-cli2..."
brew install markdownlint-cli2

echo "✓ markdownlint-cli2 installed: $(markdownlint-cli2 --version)"

# Install bats-core
echo "📦 Installing bats-core..."
brew install bats-core

echo "✓ bats-core installed: $(bats --version)"

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  Run make lint && make test before pushing a PR"
echo ""
