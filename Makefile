.PHONY: all clean lint lint-fix test stamp

all: lint test

clean:
	# No build artifacts — placeholder for future use

lint:
	markdownlint-cli2 "**/*.md"

lint-fix:
	markdownlint-cli2 --fix "**/*.md"

test:
	bats tests/

stamp:
	scripts/stamp-skills.sh
