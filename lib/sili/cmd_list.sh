# shellcheck shell=bash
# sili list — list all codespaces the user owns.

sili::cmd_list() {
  gh codespace list "$@"
}
