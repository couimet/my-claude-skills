.PHONY: lint lint-fix test stamp

lint:
	markdownlint-cli2 "**/*.md"

lint-fix:
	markdownlint-cli2 --fix "**/*.md"

test:
	bats tests/

stamp:
	scripts/stamp-skills.sh
