#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Builds the Web host's suite, lib/SwiftOmniUI/SwiftOmniUI.Web/Testing, for WebAssembly
# and runs it: the host's own tests in Node over a page with just enough of a
# DOM, through the host's own relay - or, with --browser, the tests that need a
# browser's own page, in one, headless: the conformance suite, whose layout,
# focus, dialogs and input its cases need, and the host's tests that run a host.
# The browser is Google Chrome or Chromium, or the one SWIFTOMNIUI_BROWSER names. A
# conformance run with SWIFTOMNIUI_UPDATE_EXPORTS=1 writes each verdict file under
# the revision its family stands at (lib/SwiftOmniUI/SwiftOmniUI.Conformance/revisions.txt);
# SWIFTOMNIUI_STALE_ONLY=1 runs only the families whose verdicts stand at another
# revision, or at none.
#
# USAGE:
#   test-web.sh [<Class>[/<test>]]
#   test-web.sh --browser [--host | <Family>...]
#
#   a test class, or one test of it, runs that alone; a family named - Button,
#   TextField - its conformance alone; --host the host's own tests that run a
#   host, and no conformance family
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checkout="$(cd "$here/../.." && pwd)"
harness="$checkout/lib/SwiftOmniUI/SwiftOmniUI.Web/Testing"
package="$checkout"
scratch="$package/.build/web-tests"

. "$here/swift-sdk.sh"

SWIFTOMNIUI_HOST=web swift build --package-path "$package" --scratch-path "$scratch" --swift-sdk "$sdk" --build-tests
products="$(SWIFTOMNIUI_HOST=web swift build --package-path "$package" --scratch-path "$scratch" --swift-sdk "$sdk" --show-bin-path)"
program="$products/SwiftOmniUIWebTests-test-runner.wasm"
relay="$checkout/lib/SwiftOmniUI/SwiftOmniUI.Web/JavaScript/swiftomniui-web.js"
conformance="SwiftOmniUIWebTests.WebConformanceTests"
# The classes whose tests need a browser's own page: the host's own, and the conformance suite.
hosts_in_browser="SwiftOmniUIWebTests.WebDrawnChildrenTests,SwiftOmniUIWebTests.WebShapeRoomTests,SwiftOmniUIWebTests.WebKeyboardTests,SwiftOmniUIWebTests.WebFrameReportTests,SwiftOmniUIWebTests.WebWindowClosingTests,SwiftOmniUIWebTests.WebHistoryTests"
in_browser="$conformance,$hosts_in_browser"

browser () {
  if [[ -n "${SWIFTOMNIUI_BROWSER:-}" ]]; then echo "$SWIFTOMNIUI_BROWSER"; return; fi
  for candidate in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    [[ -x "$candidate" ]] && { echo "$candidate"; return; }
  done
  for name in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$name" && return
  done
  echo "ERROR: no Google Chrome or Chromium found - SWIFTOMNIUI_BROWSER names one" >&2
  exit 1
}

if [[ "${1:-}" == "--browser" ]]; then
  shift
  # Every family by name: each runs in a program of its own (run-in-browser.mjs says why).
  families="$(node "$harness/JavaScript/run.mjs" "$relay" "$program" --list-tests | grep -E "^$conformance/" | paste -sd, -)"
  selected="$families,$hosts_in_browser"
  if [[ "${1:-}" == "--host" ]]; then
    selected="$hosts_in_browser"
  elif [[ $# -gt 0 ]]; then
    selected="$(printf "$conformance/test%s," "$@")"
    selected="${selected%,}"
  fi
  exec node "$harness/JavaScript/run-in-browser.mjs" "$(browser)" "$program" "$selected"
fi

# The host's own tests, every one but those the browser runs where none is named.
selected="${1:-}"
if [[ -z "$selected" ]]; then
  selected="$(node "$harness/JavaScript/run.mjs" "$relay" "$program" --list-tests \
    | grep -E '^SwiftOmniUIWebTests\.' | grep -v -E "^(${in_browser//,/|})/" | paste -sd, -)"
fi
exec node "$harness/JavaScript/run.mjs" "$relay" "$program" "$selected"
