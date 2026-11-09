#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# XCTest is not supplied by Apple's Command Line Tools. The same Foundation-only
# behavioral checks run as an executable on both CLT and full Xcode installations.
swift run CoreChecks
