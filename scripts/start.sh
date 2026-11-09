#!/usr/bin/env bash
# Runs inside the app container, which has NO internet. Starts the repo's START_CMD.
set -euo pipefail
cd /work/app || { echo "Not set up yet. Run: ./sandbox.sh setup"; exit 1; }
[[ -n "${START_CMD:-}" ]] || { echo "START_CMD is empty in sandbox.env: nothing to start."; exit 1; }
printf '\n\033[1;36m==> %s\033[0m\n' "Starting: ${START_CMD}"
# Remember: the app must listen on 0.0.0.0 (not 127.0.0.1) for the gateway to reach it.
exec bash -c "$START_CMD"
