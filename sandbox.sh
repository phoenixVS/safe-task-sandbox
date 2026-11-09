#!/usr/bin/env bash
# safe-task-sandbox: run an untrusted test-task repo in isolated Docker containers.
set -euo pipefail
cd "$(dirname "$0")"

export COMPOSE_PROJECT_NAME=safe-task-sandbox
IMAGE=safe-task-sandbox:latest
AGENT_IMAGE=safe-task-sandbox-agent:latest
WORK_VOLUME=${COMPOSE_PROJECT_NAME}_work
ENV_FILE=${SANDBOX_ENV:-sandbox.env}

die() { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./sandbox.sh <command>

  setup                  clone + verify EXPECTED_COMMIT + INSTALL_CMD (has internet)
  up | down | restart    start / stop the app (NO internet) and the port gateway
  logs | shell | status  follow logs / shell into the app / show containers + prove it is offline
  test [cmd...]          run TEST_CMD (or your own command) in the OFFLINE app container
  check                  install hooks off in the images, git identity set, config sane
  browser                open a clean Chrome profile at the first forwarded port
  agent [args]           optional: Claude Code in its own container (has internet)
  online <cmd...>        run one command WITH internet in the repo dir (e.g. online npm install left-pad)
  import <path> [dir]    copy a file or folder from your machine into the repo (no network)
  push <branch>          push with GIT_PUSH_TOKEN (fine-grained, this repo only)
  bundle <branch>        write out/<branch>.bundle instead of pushing
  reset [-y]             delete all containers and volumes
EOF
}

# Config value: shell environment first, then sandbox.env (so `EXPECTED_COMMIT=... ./sandbox.sh setup` works).
cfg() {
  local v="${!1:-}"
  if [[ -z "$v" && -f "$ENV_FILE" ]]; then
    v=$(grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true)
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  fi
  printf '%s' "$v"
}

# Write the gateway config and the published ports from PORTS. Ports are always bound to 127.0.0.1.
gen() {
  mkdir -p .generated/no-repo
  local ports p
  ports=$(cfg PORTS); ports=${ports:-3000}
  for p in $ports; do
    if ! [[ "$p" =~ ^[0-9]+$ ]] || (( p < 1024 || p > 65535 )); then die "PORTS: '$p' is not a port between 1024 and 65535"; fi
  done
  {
    echo "worker_processes 1;"
    echo "pid /tmp/nginx.pid;"
    echo "events { worker_connections 256; }"
    echo "# Plain TCP forwarding (also carries websockets)."
    echo "stream {"
    echo "  resolver 127.0.0.11 valid=10s;"
    for p in $ports; do echo "  server { listen $p; set \$u app:$p; proxy_pass \$u; }"; done
    echo "}"
  } > .generated/nginx.conf
  {
    echo "services:"; echo "  gateway:"; echo "    ports:"
    for p in $ports; do echo "      - \"127.0.0.1:$p:$p\""; done
  } > .generated/ports.yaml
  export HEALTH_PORT="${ports%% *}"
  FIRST_PORT="$HEALTH_PORT"
}

dc() { docker compose --env-file "$ENV_FILE" -f compose.yaml -f .generated/ports.yaml "$@"; }

cmd="${1:-help}"
case "$cmd" in help|-h|--help|check|import) ;; *)
  [[ -f "$ENV_FILE" ]] || die "No $ENV_FILE. Run: cp sandbox.env.example sandbox.env  (then set EXPECTED_COMMIT)"
  command -v docker >/dev/null || die "docker not found"
  gen ;;
esac

# Commits made inside the agent container use your global git identity.
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$(git config --global user.name 2>/dev/null || true)}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"

case "$cmd" in
  setup)   # The clone run gets the token and runs no repo code; the install run never sees the token.
           [[ "$(cfg EXPECTED_COMMIT)" =~ ^[0-9a-f]{40}$ ]] || die "Set EXPECTED_COMMIT (full 40-char SHA you reviewed) in $ENV_FILE"
           dc build
           if [[ -n "${GIT_TOKEN:-}" ]]; then
             dc --profile setup run --rm -e GIT_TOKEN setup /opt/sandbox/setup.sh clone
           else
             dc --profile setup run --rm setup /opt/sandbox/setup.sh clone
           fi
           dc --profile setup run --rm setup /opt/sandbox/setup.sh install ;;
  up)      dc up -d app gateway
           for p in $(cfg PORTS); do echo "  http://localhost:$p"; done
           echo "Follow the app with: ./sandbox.sh logs" ;;
  down)    dc down ;;
  logs)    dc logs -f app ;;
  shell)   dc exec app bash ;;
  restart) dc restart app && echo "Restarted." ;;
  status)  dc ps
           echo; echo "Internet from the app container (must be blocked):"
           if dc exec -T app timeout 4 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then
             echo "  REACHABLE  <-- not isolated!"; exit 1
           else
             echo "  blocked  ✓"
           fi ;;
  check)   docker info >/dev/null 2>&1 || die "Docker is not running"
           for img in "$IMAGE" "$AGENT_IMAGE"; do
             printf '%-36s ignore-scripts=' "$img"
             docker run --rm --network none "$img" npm config get ignore-scripts 2>/dev/null || echo "(image not built, or no npm in it)"
           done
           if [[ -n "${GIT_AUTHOR_NAME:-}" && -n "${GIT_AUTHOR_EMAIL:-}" ]]; then
             echo "git identity: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>  ✓"
           else
             echo "git identity: NOT SET (only needed for the agent). Run: git config --global user.name/user.email"
           fi
           if [[ -f "$ENV_FILE" ]]; then
             [[ "$(cfg EXPECTED_COMMIT)" =~ ^[0-9a-f]{40}$ ]] && echo "EXPECTED_COMMIT: set  ✓" || echo "EXPECTED_COMMIT: NOT SET in $ENV_FILE"
           else
             echo "$ENV_FILE: missing (cp sandbox.env.example sandbox.env)"
           fi ;;
  browser) # Separate Chrome profile: no real wallets, passwords or cookies.
           ports=$(cfg PORTS); url="$(cfg BROWSER_URL)"; url="${url:-http://localhost:${ports%% *}}"
           profile="$HOME/.chrome-sandbox-profile"
           if [[ "$(uname)" == Darwin ]]; then
             open -na "Google Chrome" --args --user-data-dir="$profile" --no-first-run "$url"
           else
             "$(command -v google-chrome || command -v chromium || die "Chrome/Chromium not found")" --user-data-dir="$profile" --no-first-run "$url" &
           fi ;;
  agent)   # Optional Claude Code container (build once; its login is kept in the agent-home volume)
           shift
           dc --profile agent build agent >/dev/null && dc --profile agent run --rm agent claude "$@" ;;
  test)    # Re-run tests yourself in the OFFLINE app container.
           shift
           if [[ -n "$(dc ps --status running -q app)" ]]; then runner=(dc exec -T app); else runner=(dc run --rm --no-deps -T app); fi
           if (( $# )); then
             "${runner[@]}" bash -c 'cd /work/app && exec "$@"' _ "$@"
           else
             [[ -n "$(cfg TEST_CMD)" ]] || die "TEST_CMD is empty in $ENV_FILE"
             "${runner[@]}" bash -c 'cd /work/app && bash -c "$TEST_CMD"'
           fi ;;
  online)  # One command WITH internet (no git token). Repo code can run here, so use it knowingly.
           shift; (( $# )) || die "usage: ./sandbox.sh online <cmd...>"
           dc --profile setup run --rm setup bash -c 'cd /work/app && exec "$@"' _ "$@" ;;
  import)  # Copy a host file/folder into the repo: ./sandbox.sh import ~/Desktop/notes.md docs
           src_in="${2:?usage: ./sandbox.sh import <path> [repo-dir]}"; dest="${3:-import}"
           [[ -e "$src_in" ]] || die "$src_in does not exist"
           src="$(cd "$(dirname "$src_in")" && pwd)/$(basename "$src_in")"
           docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges --user 1000:1000 \
             -v "$WORK_VOLUME":/work -v "$src":/in/"$(basename "$src")":ro \
             "$IMAGE" sh -c "mkdir -p '/work/app/$dest' && cp -r /in/. '/work/app/$dest/'" \
             && echo "Copied to /work/app/$dest/$(basename "$src")" ;;
  push)    # export GIT_PUSH_TOKEN=<fine-grained, Contents read+write, this repo only> in your terminal first.
           branch="${2:?usage: ./sandbox.sh push <branch>}"
           [[ -n "${GIT_PUSH_TOKEN:-}" ]] || die "Set GIT_PUSH_TOKEN first."
           # The token travels as an env var and a one-off HTTP header scoped to the remote host. Never written to disk or git config.
           dc --profile setup run --rm -T -e GIT_PUSH_TOKEN -e BRANCH="$branch" setup bash -c '
             set -euo pipefail; cd /work/app
             url=$(git remote get-url origin)
             [[ "$url" == https://* ]] || { echo "origin is $url, not https. Re-run setup with an https REPO_URL."; exit 1; }
             origin=$(printf "%s" "$url" | sed -E "s#^(https://[^/]+/).*#\1#")
             auth=$(printf "%s:%s" "${GIT_TOKEN_USER:-x-access-token}" "$GIT_PUSH_TOKEN" | base64 -w0)
             git -c "http.${origin}.extraHeader=Authorization: Basic $auth" push -u origin "$BRANCH"
             echo; echo "Now open a pull request for $BRANCH on the host of: ${url%.git}"' ;;
  bundle)  # Export the branch to ./out as a git bundle (fallback when you cannot push)
           branch="${2:?usage: ./sandbox.sh bundle <branch>}"; file="${branch//\//-}.bundle"
           base="$(cfg BASE_REF)"; base="${base:-origin/HEAD}"
           mkdir -p out
           docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges --user 1000:1000 \
             -v "$WORK_VOLUME":/work -v "$PWD/out":/out "$IMAGE" \
             sh -c "cd /work/app && git bundle create '/out/$file' '$base..$branch'" \
             && echo "Wrote out/$file  (apply with: git fetch out/$file $branch:$branch)" ;;
  reset)   if [[ "${2:-}" != "-y" ]]; then
             read -r -p "Delete ALL sandbox containers and volumes (repo copy, agent login)? [y/N] " a
             [[ "$a" == [yY] ]] || { echo "Cancelled."; exit 0; }
           fi
           dc --profile setup --profile agent down -v --remove-orphans && echo "Containers and volumes deleted." ;;
  help|-h|--help) usage ;;
  *)       usage; exit 2 ;;
esac
