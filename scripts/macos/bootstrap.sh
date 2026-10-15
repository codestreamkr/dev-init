#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BREWFILE="${ROOT_DIR}/config/brew/Brewfile"
MYBOX_APP="/Applications/MYBOX.app"

DRY_RUN=false
NO_UPGRADE=false
SKIP_AI_INIT=false
AI_INIT_REQUIRED=false

usage() {
  cat <<'EOF'
Usage: scripts/macos/bootstrap.sh [options]

Options:
  --dry-run      Print planned actions without installing packages.
  --no-upgrade   Skip upgrades, including packages in the Brewfile.
  --skip-ai-init Skip the shared AI initialization script.
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
    echo "[dry-run] brew update"
    if [[ "$NO_UPGRADE" != "true" ]]; then
      echo "[dry-run] brew upgrade --greedy"
    fi
    echo "[dry-run] brew bundle --file $BREWFILE$([[ "$NO_UPGRADE" == "true" ]] && echo " --no-upgrade")"
    sed -n '/^[[:space:]]*#/d;/^[[:space:]]*$/d;p' "$BREWFILE"
    return
  fi

  brew update

  if [[ "$NO_UPGRADE" != "true" ]]; then
    brew upgrade --greedy
  fi

  if [[ "$NO_UPGRADE" == "true" ]]; then
    brew bundle --file "$BREWFILE" --no-upgrade
  else
    brew bundle --file "$BREWFILE"
  fi
}

install_mybox() (
  # Keep temporary downloads isolated and remove them on success or failure.
  if [[ "$NO_UPGRADE" == "true" && -d "$MYBOX_APP" ]]; then
    echo "Already installed; upgrades disabled: NAVER MYBOX"
    return
  fi

  url="https://appdown.pstatic.net/naver/mybox/MAC/installer/MYBOX.pkg"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Download $url and verify the NAVER installer signature."
    echo "[dry-run] sudo installer -pkg <downloaded MYBOX.pkg> -target /"
    return
  fi

  macos_version="$(sw_vers -productVersion)"
  if (( ${macos_version%%.*} < 14 )); then
    echo "NAVER MYBOX requires macOS 14 or later." >&2
    exit 1
  fi

  installer_dir="$(mktemp -d "${TMPDIR:-/tmp}/dev-init-mybox.XXXXXX")"
  trap 'rm -rf "$installer_dir"' EXIT
  curl -fsSL "$url" -o "$installer_dir/MYBOX.pkg"
  signature="$(pkgutil --check-signature "$installer_dir/MYBOX.pkg")"
  if ! printf '%s\n' "$signature" | grep -Fq 'Developer ID Installer: NAVER Corp. (K9UP278937)'; then
    echo "MYBOX installer is not signed by NAVER Corp." >&2
    exit 1
  fi
  sudo installer -pkg "$installer_dir/MYBOX.pkg" -target /
)

configure_node_lts() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo '[dry-run] Add Homebrew node@24/bin to PATH and ~/.zprofile.'
    return
  fi

  local node_bin
  node_bin="$(brew --prefix node@24)/bin"
  export PATH="$node_bin:$PATH"
  local path_line='export PATH="$(brew --prefix node@24)/bin:$PATH"'
  if ! grep -Fqx "$path_line" "$HOME/.zprofile" 2>/dev/null; then
    printf '\n%s\n' "$path_line" >> "$HOME/.zprofile"
  fi
}

configure_claude_path() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo '[dry-run] Add ~/.local/bin to PATH and ~/.zprofile.'
    return
  fi

  export PATH="$HOME/.local/bin:$PATH"
  local path_line='export PATH="$HOME/.local/bin:$PATH"'
  if ! grep -Fqx "$path_line" "$HOME/.zprofile" 2>/dev/null; then
    printf '\n%s\n' "$path_line" >> "$HOME/.zprofile"
  fi
}

install_claude_cli() {
  if command -v claude >/dev/null 2>&1; then
    if [[ "$NO_UPGRADE" == "true" ]]; then
      echo "Already installed; upgrades disabled: Claude CLI"
    elif [[ "$DRY_RUN" == "true" ]]; then
      echo "[dry-run] claude update"
    else
      claude update
    fi
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] curl -fsSL https://claude.ai/install.sh | bash"
    return
  fi

  echo "Installing Claude CLI with certificate validation..."
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
}

install_native_ai_cli() {
  local command_name="$1" installer_url="$2"
  export PATH="$HOME/.local/bin:${GROK_BIN_DIR:-$HOME/.grok/bin}:$PATH"
  if command -v "$command_name" >/dev/null 2>&1; then
    if [[ "$NO_UPGRADE" == "true" ]]; then
      echo "Already installed; upgrades disabled: $command_name"
    elif [[ "$DRY_RUN" == "true" ]]; then
      echo "[dry-run] $command_name update"
    else
      "$command_name" update
    fi
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] curl -fsSL $installer_url | bash"
    return
  fi

  curl -fsSL "$installer_url" | bash
  export PATH="$HOME/.local/bin:${GROK_BIN_DIR:-$HOME/.grok/bin}:$PATH"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Installation completed, but $command_name was not found in PATH." >&2
    return 1
  fi
  AI_INIT_REQUIRED=true
}

install_pi_cli() {
  local already_installed=false
  if command -v pi >/dev/null 2>&1; then
    already_installed=true
    if [[ "$NO_UPGRADE" == "true" ]]; then
      echo "Already installed; upgrades disabled: Pi CLI"
      return
    fi
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] npm install --global --prefix $HOME/.local --ignore-scripts @earendil-works/pi-coding-agent@latest"
    return
  fi

  npm install --global --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent@latest
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v pi >/dev/null 2>&1; then
    echo "Pi CLI installation did not make pi available." >&2
    return 1
  fi
  if [[ "$already_installed" != "true" ]]; then
    AI_INIT_REQUIRED=true
  fi
}

run_ai_init_repository() {
  local command_name="$1"
  local repository="$2"
  local destination="$3"

  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dev-init"
  local marker="$state_dir/$command_name.initialized"

  if [[ -f "$marker" && "$AI_INIT_REQUIRED" != "true" ]]; then
    echo "Already initialized: $command_name"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] git clone $repository $destination"
    echo "[dry-run] bash $destination/install.sh"
    return
  fi

  rm -rf "$destination"
  git clone "$repository" "$destination"
  bash "$destination/install.sh"
  mkdir -p "$state_dir"
  touch "$marker"
}

run_ai_init() {
  if [[ "$SKIP_AI_INIT" == "true" ]]; then
    return
  fi

  run_ai_init_repository \
    "ai-comm-init" \
    "https://github.com/codestreamkr/ai-comm-init.git" \
    "/tmp/ai-comm-init"
}

main() {
  require_macos
  require_brewfile
  install_homebrew
  run_brew_bundle
  install_mybox
  configure_node_lts
  configure_claude_path
  install_claude_cli
  install_native_ai_cli "agy" "https://antigravity.google/cli/install.sh"
  install_native_ai_cli "grok" "https://x.ai/cli/install.sh"
  install_pi_cli
  run_ai_init
}

main "$@"
