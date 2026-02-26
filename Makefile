.PHONY: lint test

lint:
	markdownlint-cli2 "**/*.md"

test:
	bats tests/
