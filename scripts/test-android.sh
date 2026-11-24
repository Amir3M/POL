#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"

pol_require_language_tools
(
    cd -- "$POL_REPO_ROOT/core"
    go vet ./...
    go test ./...
    go vet -tags with_gvisor ./internal/tunstack/
    go test -tags with_gvisor ./internal/tunstack/
)
(
    cd -- "$POL_REPO_ROOT/app"
    pol_pub_get
    flutter analyze --no-pub
    flutter test --no-pub
)
