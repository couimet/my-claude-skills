#!/usr/bin/env bash

# Shared test helper for Bats test suites.
# Sources this file from .bats files via: load test_helper

# Resolve the project root (parent of tests/)
# shellcheck disable=SC2034
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR:?}"
}
