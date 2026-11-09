#!/usr/bin/env bash
# Runs inside the container WITH internet, in two separate container runs:
#   setup.sh clone    - gets GIT_TOKEN, clones + verifies the commit. Runs NO repo code.
#   setup.sh install  - never sees the token. Runs INSTALL_CMD (repo code may run here).
set -euo pipefail
cd /work
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit "${2:-1}"; }
git config --global --add safe.directory '*'
git config --global advice.detachedHead false

case "${1:-}" in
clone)
  export GIT_TERMINAL_PROMPT=0   # never ask for a username/password
  REPO_URL="${REPO_URL:-/src}"
  [[ "${EXPECTED_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || die "EXPECTED_COMMIT must be the full 40-character SHA you reviewed." 2
  case "$REPO_URL" in
    https://*|/src) ;;
    *) die "REPO_URL must be https://... or /src (a local repo mounted with REPO_PATH). Got: $REPO_URL" 2 ;;
  esac
  [[ "$REPO_URL" != *@* ]] || die "Do not put credentials in REPO_URL. Pass GIT_TOKEN instead." 2
  if [[ -n "${REPO_REF:-}" && ! "$REPO_REF" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]]; then die "REPO_REF looks unsafe: $REPO_REF" 2; fi

  if [[ -d /work/app/.git && "${FORCE:-}" != 1 ]]; then
    extra=$(cd /work/app && { git status --porcelain --untracked-files=all; git log --branches --not --remotes --oneline; } || true)
    if [[ -n "$extra" ]]; then
      echo "A repo copy with your work already exists (changes or local-only commits):"
      echo "$extra" | head -15
      echo "Setup would delete it. Keep it: just run ./sandbox.sh up. Start over anyway: FORCE=1 ./sandbox.sh setup"
      exit 4
    fi
  fi

  say "Cloning ${REPO_URL}"
  rm -rf /work/app
  auth=()
  if [[ "$REPO_URL" == https://* && -n "${GIT_TOKEN:-}" ]]; then
    # One-off HTTP header, scoped to this host only: never in the URL, .git/config or on disk.
    origin=$(printf '%s' "$REPO_URL" | sed -E 's#^(https://[^/]+/).*#\1#')
    auth=(-c "http.${origin}.extraHeader=Authorization: Basic $(printf '%s:%s' "${GIT_TOKEN_USER:-x-access-token}" "$GIT_TOKEN" | base64 -w0)")
  fi
  if ! git "${auth[@]}" clone --no-local --no-recurse-submodules "$REPO_URL" /work/app; then
    echo "Clone failed. For a private repo pass a read-only token (it is not printed):"
    echo "  GIT_TOKEN=\$(gh auth token) ./sandbox.sh setup"
    exit 2
  fi
  cd /work/app
  if [[ -n "${REPO_REF:-}" ]]; then
    ref_sha=$(git rev-parse --verify "${REPO_REF}^{commit}") || die "REPO_REF '$REPO_REF' not found in the repo." 3
    git checkout --detach "$ref_sha"
  fi

  say "Verifying commit"
  head=$(git rev-parse HEAD)
  git log -1 --format='%H  %an  %ad  %s'
  if [[ "$head" != "$EXPECTED_COMMIT" ]]; then
    printf '\n\033[1;31m!! HEAD is %s, expected %s\033[0m\n' "$head" "$EXPECTED_COMMIT"
    echo "!! The repo changed since it was reviewed. Files changed:"
    git diff --stat "$EXPECTED_COMMIT" HEAD 2>/dev/null || echo "(reviewed commit not in history: history was rewritten)"
    echo "!! Stopping. Review the changes, then set EXPECTED_COMMIT=$head if they are safe."
    rm -rf /work/app
    exit 3
  fi
  echo "OK: matches the reviewed commit."
  ;;

install)
  if [[ -n "${GIT_TOKEN:-}" || -n "${GIT_PUSH_TOKEN:-}" ]]; then die "Refusing: install must not see a git token."; fi
  cd /work/app || die "Nothing cloned. Run ./sandbox.sh setup"
  say "Install hooks found in the repo (disabled for npm, listed for your review)"
  { find . -name package.json -not -path '*/node_modules/*' -maxdepth 4 -print0 | xargs -0 -r grep -nE '"(pre|post)?install"|"prepare"'; } || echo "none"
  if [[ -z "${INSTALL_CMD:-}" ]]; then
    echo "INSTALL_CMD is empty: nothing to install."
  else
    say "Running INSTALL_CMD: ${INSTALL_CMD}"
    bash -c "$INSTALL_CMD"
  fi
  say "Setup done. Start with: ./sandbox.sh up"
  ;;

*) echo "usage: setup.sh clone|install"; exit 2 ;;
esac
