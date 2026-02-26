.PHONY: lint test stamp

lint:
	markdownlint-cli2 "**/*.md"

test:
	bats tests/

stamp:
	scripts/stamp-skills.sh
