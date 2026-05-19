#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BREWFILE="${ROOT_DIR}/config/brew/Brewfile"

DRY_RUN=false
NO_UPGRADE=false
SKIP_AI_INIT=false

usage() {
  cat <<'EOF'
Usage: scripts/macos/bootstrap.sh [options]

Options:
  --dry-run      Print planned actions without installing packages.
  --no-upgrade   Skip brew upgrade before package installation.
  --skip-ai-init Skip Codex and Claude Code initialization scripts.
  -h, --help     Show this help message.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --no-upgrade)
      NO_UPGRADE=true
      ;;
    --skip-ai-init)
      SKIP_AI_INIT=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script must run on macOS." >&2
    exit 1
  fi
}

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return
  fi

  if [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Homebrew is not installed. It would be installed."
    return
  fi

  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

require_brewfile() {
  if [[ ! -f "$BREWFILE" ]]; then
    echo "Brewfile not found: $BREWFILE" >&2
    exit 1
  fi
}

run_brew_bundle() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Brewfile: $BREWFILE"
    sed -n '/^[[:space:]]*#/d;/^[[:space:]]*$/d;p' "$BREWFILE"
    return
  fi

  brew update

  if [[ "$NO_UPGRADE" != "true" ]]; then
    brew upgrade
  fi

  brew bundle --file "$BREWFILE"
}

install_claude_cli() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] curl -kfsSL https://claude.ai/install.sh | bash"
    return
  fi

  echo "Installing Claude CLI with certificate bypass for this request..."
  curl -kfsSL https://claude.ai/install.sh | bash
}

run_ai_init() {
  if [[ "$SKIP_AI_INIT" == "true" ]]; then
    return
  fi

  local codex_dir="/tmp/codex-init"
  local claude_dir="/tmp/claude-init"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] git clone https://github.com/codestreamkr/chatgpt-codex-init.git $codex_dir"
    echo "[dry-run] bash $codex_dir/install.sh"
    echo "[dry-run] git clone https://github.com/codestreamkr/claude-code-init.git $claude_dir"
    echo "[dry-run] bash $claude_dir/install.sh"
    return
  fi

  rm -rf "$codex_dir" "$claude_dir"

  git clone https://github.com/codestreamkr/chatgpt-codex-init.git "$codex_dir"
  bash "$codex_dir/install.sh"

  git clone https://github.com/codestreamkr/claude-code-init.git "$claude_dir"
  bash "$claude_dir/install.sh"
}

main() {
  require_macos
  require_brewfile
  install_homebrew
  run_brew_bundle
  install_claude_cli
  run_ai_init
}

main "$@"
