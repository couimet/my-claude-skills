.PHONY: lint test stamp

lint:
	markdownlint-cli2 "**/*.md"

test:
	bats tests/

stamp:
	@CALVER=$$(grep -m1 '^## [0-9]' CHANGELOG.md | sed 's/^## //'); \
	SHA=$$(git rev-parse --short HEAD); \
	VERSION="$${CALVER}@$${SHA}"; \
	echo "Stamping skills with version $${VERSION}"; \
	scripts/stamp-skills.sh "$${VERSION}"
