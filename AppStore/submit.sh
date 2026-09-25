#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 || (${3:-} != '' && ${3:-} != --submit) ]]; then
  echo "Usage: AppStore/submit.sh VERSION BUILD [--submit]" >&2
  echo "Without --submit, performs a read-only check." >&2
  exit 2
fi

cd "$(dirname "$0")/.."
export FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1
export FASTLANE_HIDE_CHANGELOG=1 FASTLANE_SKIP_ACTION_SUMMARY=1
export N4X4_ASC_KEY_PATH="${N4X4_ASC_KEY_PATH:-$HOME/.config/n4x4/app-store-api-key.json}"
command -v fastlane >/dev/null || { echo "Install tooling: brew install fastlane" >&2; exit 1; }
lane=app_store_check
[[ ${3:-} != --submit ]] || lane=app_store_submit
exec fastlane "$lane" "version:$1" "build:$2"
