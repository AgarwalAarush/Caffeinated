#!/usr/bin/env bash
#
# Development-environment bootstrap for the Caffeinated repository.
#
# IMPORTANT PLATFORM NOTE
# -----------------------
# Caffeinated is a macOS-only menu-bar application. It is built with Xcode and
# links exclusively against Apple SDK frameworks (SwiftUI's MenuBarExtra,
# AppKit, IOKit power-management assertions, ServiceManagement/SMAppService and
# UserNotifications). Building the .app bundle and running the app therefore
# REQUIRE macOS + Xcode and cannot be performed on a Linux Cloud Agent.
#
# What this script CAN set up on Linux is the upstream Swift toolchain
# (swiftc, Swift Package Manager and swift-format). That gives real, useful
# development tooling: syntax checking and formatting of the Swift sources.
#
# The script is idempotent: it can be re-run safely and skips work that has
# already been done.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTLY_HOME_DIR="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}"

if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else SUDO=""; fi

# 1. System libraries required by the Swift runtime/toolchain on Ubuntu.
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends \
  gnupg2 libcurl4-openssl-dev libpython3-dev libxml2-dev libncurses-dev libz3-dev \
  ca-certificates curl

# 2. Install swiftly + the latest stable Swift toolchain (only if missing).
if [ ! -x "$SWIFTLY_HOME_DIR/bin/swiftly" ]; then
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    curl -fsSL -O "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
    tar zxf "swiftly-$(uname -m).tar.gz"
    ./swiftly init --quiet-shell-followup --assume-yes
  )
  rm -rf "$tmp"
fi

# 3. Load swift onto PATH for the current shell and report the version.
# shellcheck disable=SC1091
. "$SWIFTLY_HOME_DIR/env.sh"
hash -r
swift --version

# 4. Syntax gate: verify every app source parses with the Swift toolchain.
#    (Full type-checking is impossible on Linux because the Apple frameworks
#    are unavailable, but a clean parse still catches syntax regressions.)
status=0
for f in "$REPO_ROOT"/Caffeinated/*.swift; do
  if swift format "$f" >/dev/null 2>/tmp/swift_parse_err; then
    echo "parsed OK: ${f#"$REPO_ROOT"/}"
  else
    echo "PARSE FAILED: ${f#"$REPO_ROOT"/}"
    cat /tmp/swift_parse_err
    status=1
  fi
done

exit "$status"
