.PHONY: check lint lint-fix lint-md lint-md-fix fmt-check format lint-sh test install-prereqs stamp

include versions.mk

# `check` is the default target and the gate CI mirrors.
check: lint test

lint: install-prereqs lint-md fmt-check lint-sh

lint-fix: install-prereqs lint-md-fix format

lint-md:
	npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) "**/*.md"

lint-md-fix:
	npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) --fix "**/*.md"

fmt-check:
	npx --yes prettier@$(PRETTIER_VERSION) --check .

format:
	npx --yes prettier@$(PRETTIER_VERSION) --write .

lint-sh:
	find . -type f \( -name '*.sh' -o -name '*.bash' \) \
		-not -path '*/.claude-work/*' -not -path '*/.history/*' -not -path '*/demo/*' \
		-exec shellcheck {} +

test: install-prereqs
	bats tests/

install-prereqs:
	@ok=true; \
	command -v node >/dev/null 2>&1 || { echo "Missing: node — install it: brew install node@24"; ok=false; }; \
	command -v bats >/dev/null 2>&1 || { echo "Missing: bats — install it: brew install bats-core"; ok=false; }; \
	command -v shellcheck >/dev/null 2>&1 || { echo "Missing: shellcheck — install it: brew install shellcheck"; ok=false; }; \
	$$ok || { echo; echo "Install the missing prerequisites above, then re-run."; exit 1; }

stamp:
	scripts/stamp-skills.sh
