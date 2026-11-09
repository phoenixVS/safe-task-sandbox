#!/usr/bin/env bash
# Turns examples/hello-node into a throwaway local git repo and prints a ready sandbox.env.
# Usage: examples/make-demo-repo.sh /tmp/demo-repo > sandbox.env
set -euo pipefail
dest="${1:?usage: make-demo-repo.sh <empty-or-new-dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
[[ ! -e "$dest" || -z "$(ls -A "$dest")" ]] || { echo "$dest is not empty" >&2; exit 1; }
mkdir -p "$dest" && dest="$(cd "$dest" && pwd)"
cp -R "$here/hello-node/." "$dest/"
git -C "$dest" init -q
git -C "$dest" add -A
git -C "$dest" -c user.name=demo -c user.email=demo@example.invalid commit -q -m "demo: hello-node"
cat <<EOF
REPO_PATH=$dest
REPO_URL=/src
EXPECTED_COMMIT=$(git -C "$dest" rev-parse HEAD)
INSTALL_CMD="npm install"
START_CMD="npm start"
TEST_CMD="npm test"
PORTS="3000"
EOF
