#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
  bash "${SCRIPT_DIR}/scripts/macos/bootstrap.sh" "$@"
}

main "$@"
