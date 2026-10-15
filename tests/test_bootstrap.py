"""Exercise bootstrap control flow without installing software or using the network."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'scripts/macos/bootstrap.sh').read_text()
SOURCE = SOURCE.replace(
    'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
    f'SCRIPT_DIR={shlex.quote(str(ROOT / "scripts/macos"))}',
).rsplit('main "$@"', 1)[0]


class BootstrapTests(unittest.TestCase):
    def run_shell(self, commands):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, HOME=directory, XDG_STATE_HOME=directory + '/state')
            return subprocess.run(
                ['bash', '-c', SOURCE + '\n' + commands], env=env,
                text=True, capture_output=True,
            )

    def test_no_upgrade_reaches_bundle(self):
        result = self.run_shell('''
            brew() { printf '%s\\n' "$*"; }
            NO_UPGRADE=true
            run_brew_bundle
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--no-upgrade', result.stdout)
        self.assertNotIn('\nupgrade\n', result.stdout)

    def test_default_updates_existing_packages_including_casks(self):
        result = self.run_shell('''
            brew() { printf '%s\\n' "$*"; }
            run_brew_bundle
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('upgrade --greedy', result.stdout)
        self.assertIn('bundle --file', result.stdout)
        self.assertNotIn('--no-upgrade', result.stdout)

    def test_existing_claude_updates_by_default(self):
        result = self.run_shell('''
            claude() { echo "claude $*"; }
            install_claude_cli
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('claude update', result.stdout)

    def test_claude_update_is_skipped_when_disabled_or_dry_run(self):
        for option in ('NO_UPGRADE=true', 'DRY_RUN=true'):
            result = self.run_shell('''
                claude() { echo unexpected >&2; return 99; }
            ''' + option + '\ninstall_claude_cli')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('unexpected', result.stderr)

    def test_claude_update_failure_is_propagated(self):
        result = self.run_shell('''
            claude() { return 7; }
            install_claude_cli
        ''')
        self.assertEqual(result.returncode, 7, result.stderr)

    def test_initialization_runs_with_cli_and_skips_after_success(self):
        result = self.run_shell('''
            codex() { :; }
            git() {
                mkdir -p "$3"
                printf 'echo initialized\\n' > "$3/install.sh"
            }
            destination="$HOME/repo"
            run_ai_init_repository codex example "$destination"
            run_ai_init_repository codex example "$destination"
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines().count('initialized'), 1)
        self.assertIn('Already initialized: codex', result.stdout)

    def test_failed_initialization_has_no_success_marker(self):
        result = self.run_shell('''
            git() {
                mkdir -p "$3"
                printf 'exit 7\\n' > "$3/install.sh"
            }
            trap 'test ! -f "$XDG_STATE_HOME/dev-init/codex.initialized" || exit 99' EXIT
            run_ai_init_repository codex example "$HOME/repo"
        ''')
        self.assertEqual(result.returncode, 7, result.stderr)

    def test_dry_run_writes_no_initialization_state(self):
        result = self.run_shell('''
            DRY_RUN=true
            run_ai_init_repository codex example "$HOME/repo"
            test ! -e "$XDG_STATE_HOME"
            test ! -e "$HOME/repo"
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_shared_ai_repository_runs_once_and_ignores_legacy_markers(self):
        result = self.run_shell('''
            mkdir -p "$XDG_STATE_HOME/dev-init"
            touch "$XDG_STATE_HOME/dev-init/codex.initialized"
            touch "$XDG_STATE_HOME/dev-init/claude.initialized"
            # Redirect the destination so the test never touches shared /tmp paths.
            git() {
                echo "repository: $2"
                mkdir -p "$3"
                printf 'echo shared-initialized\\n' > "$3/install.sh"
            }
            run_ai_init_repository ai-comm-init https://github.com/codestreamkr/ai-comm-init.git "$HOME/repo"
            run_ai_init_repository ai-comm-init https://github.com/codestreamkr/ai-comm-init.git "$HOME/repo"
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('repository:'), 1)
        self.assertEqual(result.stdout.splitlines().count('shared-initialized'), 1)

    def test_ai_entrypoint_routes_once_and_honors_skip(self):
        result = self.run_shell('''
            run_ai_init_repository() { echo "route: $*"; }
            run_ai_init
            SKIP_AI_INIT=true
            run_ai_init
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            'route: ai-comm-init https://github.com/codestreamkr/ai-comm-init.git /tmp/ai-comm-init'
        ])

    def test_claude_path_is_persistent_and_not_duplicated(self):
        result = self.run_shell('''
            configure_claude_path
            configure_claude_path
            test "${PATH%%:*}" = "$HOME/.local/bin"
            test "$(grep -c '.local/bin' "$HOME/.zprofile")" = 1
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_claude_path_dry_run_does_not_write(self):
        result = self.run_shell('''
            DRY_RUN=true
            configure_claude_path
            test ! -e "$HOME/.zprofile"
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_mybox_downloads_verifies_installs_and_cleans_up(self):
        result = self.run_shell('''
            TMPDIR="$HOME/downloads"
            mkdir -p "$TMPDIR"
            sw_vers() { echo 14.0; }
            curl() { echo "download: $*"; touch "${@: -1}"; }
            pkgutil() { echo 'Developer ID Installer: NAVER Corp. (K9UP278937)'; }
            sudo() { echo "install: $*"; }
            MYBOX_APP="$HOME/MYBOX.app"
            mkdir -p "$MYBOX_APP"
            install_mybox
            test -z "$(ls -A "$TMPDIR")"
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('download: -fsSL https://appdown.pstatic.net/', result.stdout)
        self.assertIn('install: installer -pkg', result.stdout)

    def test_mybox_no_upgrade_skips_installed_app(self):
        result = self.run_shell('''
            MYBOX_APP="$HOME/MYBOX.app"
            mkdir -p "$MYBOX_APP"
            NO_UPGRADE=true
            curl() { exit 99; }
            install_mybox
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('upgrades disabled', result.stdout)

    def test_mybox_dry_run_does_not_install(self):
        result = self.run_shell('''
            DRY_RUN=true
            sudo() { exit 99; }
            curl() { exit 99; }
            install_mybox
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('[dry-run]', result.stdout)

    def test_mybox_rejects_untrusted_download_and_cleans_up(self):
        for failure in ('curl() { return 7; }',
                        'pkgutil() { return 1; }',
                        "pkgutil() { echo 'Developer ID Installer: Other Vendor'; }"):
            result = self.run_shell('''
                TMPDIR="$HOME/downloads"
                mkdir -p "$TMPDIR"
                trap 'test -z "$(ls -A "$TMPDIR")" || exit 98' EXIT
                sw_vers() { echo 14.0; }
                curl() { touch "${@: -1}"; }
                pkgutil() { echo 'Developer ID Installer: NAVER Corp. (K9UP278937)'; }
                sudo() { exit 99; }
            ''' + failure + '\ninstall_mybox')
            self.assertIn(result.returncode, (1, 7), result.stderr)

    def test_mybox_installer_failure_is_propagated(self):
        result = self.run_shell('''
            TMPDIR="$HOME/downloads"
            mkdir -p "$TMPDIR"
            trap 'test -z "$(ls -A "$TMPDIR")" || exit 98' EXIT
            sw_vers() { echo 14.0; }
            curl() { touch "${@: -1}"; }
            pkgutil() { echo 'Developer ID Installer: NAVER Corp. (K9UP278937)'; }
            sudo() { return 7; }
            install_mybox
        ''')
        self.assertEqual(result.returncode, 7, result.stderr)

    def test_node_path_persists_once_and_takes_precedence(self):
        result = self.run_shell('''
            brew() { echo /opt/homebrew/opt/node@24; }
            configure_node_lts
            configure_node_lts
            test "${PATH%%:*}" = /opt/homebrew/opt/node@24/bin
            test "$(grep -c 'node@24' "$HOME/.zprofile")" = 1
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)


class AdditionalAiCliTests(unittest.TestCase):
    run_shell = BootstrapTests.run_shell

    def test_native_existing_updates_and_honors_skip(self):
        for name in ('agy', 'grok'):
            for option in ('', 'NO_UPGRADE=true', 'DRY_RUN=true'):
                result = self.run_shell(f'''
                    {name}() {{ echo command-called; }}
                    {option}
                    install_native_ai_cli {name} https://example.invalid/install.sh
                ''')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual('command-called' in result.stdout, not option)

    def test_native_update_failure_is_propagated(self):
        for name in ('agy', 'grok'):
            result = self.run_shell(f'''
                {name}() {{ return 7; }}
                install_native_ai_cli {name} https://example.invalid/install.sh
            ''')
            self.assertEqual(result.returncode, 7, result.stderr)

    def test_native_missing_installs_and_requires_initialization(self):
        for name in ('agy', 'grok'):
            result = self.run_shell(f'''
                command() {{
                    if [[ "$1" == -v && "$2" == {name} ]]; then
                        test -f "$HOME/installed"
                    else
                        builtin command "$@"
                    fi
                }}
                curl() {{
                    echo "download: $*" >&2
                    printf 'touch "$HOME/installed"\\n'
                }}
                install_native_ai_cli {name} https://example.invalid/install.sh
                test "$AI_INIT_REQUIRED" = true
            ''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('download: -fsSL https://example.invalid/install.sh', result.stderr)

    def test_native_missing_failure_and_dry_run(self):
        for name in ('agy', 'grok'):
            for option in ('', 'DRY_RUN=true'):
                result = self.run_shell(f'''
                    command() {{
                        if [[ "$1" == -v && "$2" == {name} ]]; then return 1; fi
                        builtin command "$@"
                    }}
                    curl() {{ echo unexpected >&2; return 7; }}
                    {option}
                    install_native_ai_cli {name} https://example.invalid/install.sh
                ''')
                if option:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotIn('unexpected', result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0)

    def test_pi_install_uses_local_prefix_and_marks_initialization(self):
        result = self.run_shell('''
            command() {
                if [[ "$1" == -v && "$2" == pi ]]; then test -f "$HOME/installed"; return; fi
                builtin command "$@"
            }
            npm() { printf 'npm: %s\\n' "$*"; touch "$HOME/installed"; }
            install_pi_cli
            test "$AI_INIT_REQUIRED" = true
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('install --global --prefix ', result.stdout)
        self.assertIn('/.local --ignore-scripts @earendil-works/pi-coding-agent@latest', result.stdout)

    def test_pi_existing_updates_and_honors_skip(self):
        for option in ('', 'NO_UPGRADE=true', 'DRY_RUN=true'):
            result = self.run_shell('''
                pi() { :; }
                npm() { echo npm-called; }
            ''' + option + '\ninstall_pi_cli')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual('npm-called' in result.stdout, not option)

    def test_pi_failure_is_propagated(self):
        result = self.run_shell('''
            pi() { :; }
            npm() { return 7; }
            install_pi_cli
        ''')
        self.assertEqual(result.returncode, 7, result.stderr)

    def test_new_cli_reruns_initialization_despite_marker(self):
        result = self.run_shell('''
            mkdir -p "$XDG_STATE_HOME/dev-init"
            touch "$XDG_STATE_HOME/dev-init/ai-comm-init.initialized"
            AI_INIT_REQUIRED=true
            git() {
                mkdir -p "$3"
                printf 'echo refreshed-links\\n' > "$3/install.sh"
            }
            run_ai_init_repository ai-comm-init example "$HOME/repo"
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('refreshed-links', result.stdout)


if __name__ == '__main__':
    unittest.main()
