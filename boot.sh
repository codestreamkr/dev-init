#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="https://github.com/codestreamkr/dev-init.git"
TARGET_DIR="/tmp/dev-init"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
  esac
done

ensure_homebrew() {
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

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew installation completed, but brew was not found in expected paths." >&2
    exit 1
  fi
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return
  fi

  ensure_homebrew

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] brew install git"
    return
  fi

  brew install git
}

main() {
  ensure_git

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] rm -rf $TARGET_DIR"
    echo "[dry-run] git clone $REPOSITORY_URL $TARGET_DIR"
    echo "[dry-run] bash $TARGET_DIR/install.sh $*"
    return
  fi

  rm -rf "$TARGET_DIR"
  git clone "$REPOSITORY_URL" "$TARGET_DIR"
  bash "$TARGET_DIR/install.sh" "$@"
}

main "$@"
