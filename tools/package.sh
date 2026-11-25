#!/bin/bash
# Builds the release files in dist/:
#   PlayerTags.zip                      the stable download the README links to
#   PlayerTags-<version>-forever.zip    the same zip, named the way WowUp
#                                       looks for a WoW: Forever file
#   release.json                        tells WowUp and other updaters which
#                                       zip is for which game (flavor forever)
# Each zip holds one folder, PlayerTags/, ready to drop into Interface/AddOns.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(sed -n 's/^## Version: //p' PlayerTags/PlayerTags.toc | tr -d '\r')
interface=$(sed -n 's/^## Interface: //p' PlayerTags/PlayerTags.toc | tr -d '\r')
mkdir -p dist
rm -f dist/PlayerTags.zip dist/PlayerTags-*-forever.zip dist/release.json
zip -rqX dist/PlayerTags.zip PlayerTags -x '*/.*'
forever="PlayerTags-${version}-forever.zip"
cp dist/PlayerTags.zip "dist/${forever}"
cat > dist/release.json <<JSON
{"releases":[{"name":"Player Tags","version":"${version}","filename":"${forever}","nolib":false,"metadata":[{"flavor":"forever","interface":${interface}}]}]}
JSON
echo "dist/PlayerTags.zip: $(unzip -Z1 dist/PlayerTags.zip | wc -l) entries, version ${version}"
echo "dist/${forever} and dist/release.json for WowUp"
