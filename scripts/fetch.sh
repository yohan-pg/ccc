#!/bin/bash
# Pull a file or directory back from the cluster.
# Usage: fetch.sh <remote-absolute-path> <local-dest>
# Remote path must be absolute — ~ does not expand under the automation wrapper.
set -euo pipefail

REMOTE=${1:?usage: fetch.sh <remote-absolute-path> <local-dest>}
DEST=${2:?usage: fetch.sh <remote-absolute-path> <local-dest>}

source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

[[ $REMOTE == /* ]] || { echo "remote path must be absolute: $REMOTE" >&2; exit 1; }

mkdir -p "$(dirname "${DEST%/}")"
rsync -azh --no-g --no-p --partial --info=progress2 "$CC_HOST:$REMOTE" "$DEST"
