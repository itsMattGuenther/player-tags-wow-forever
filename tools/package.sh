#!/bin/bash
# Builds dist/PlayerTags.zip, the file people download from the Releases page.
# The zip holds one folder, PlayerTags/, ready to drop into Interface/AddOns.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
rm -f dist/PlayerTags.zip
zip -rqX dist/PlayerTags.zip PlayerTags -x '*/.*'
echo "dist/PlayerTags.zip: $(unzip -Z1 dist/PlayerTags.zip | wc -l) entries, version $(sed -n 's/^## Version: //p' PlayerTags/PlayerTags.toc)"
