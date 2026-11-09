# safe-task-sandbox

Run a take-home test task (or any repo you don't fully trust) in Docker, without letting it near your laptop.

```
 your machine ── 127.0.0.1:PORTS ──► gateway ──► app (NO internet) ◄── tests, start
                                                  ▲
                          setup (internet): clone → verify commit → install
```

- **Pinned commit.** Setup refuses to continue unless the repo is exactly the commit you reviewed.
- **Token never meets repo code.** The git token is used only by the clone step. The install step, where the repo's code can run, refuses to start if it sees one.
- **Offline app.** The app and its tests run on a Docker `internal` network with no route to the internet or to your machine. Only an nginx gateway forwards the ports you list, and only to `127.0.0.1`.
- **Locked-down containers.** Non-root user, all capabilities dropped, read-only root filesystem, `no-new-privileges`, memory and process limits.
- **No install hooks.** npm lifecycle scripts are off in every image, and `./sandbox.sh check` verifies it.
- **Nothing from your machine is mounted.** No home folder, SSH keys, wallets, browser data or Docker socket. An optional local repo is mounted read-only.

Read [SECURITY.md](SECURITY.md) for what this does **not** protect against.

## Requirements

Docker with Compose v2 (Docker Desktop, OrbStack, or Docker Engine) and bash. Works on macOS and Linux. Windows: use WSL2.

## Quickstart

```bash
cp sandbox.env.example sandbox.env
$EDITOR sandbox.env          # REPO_URL, EXPECTED_COMMIT, INSTALL_CMD, START_CMD, TEST_CMD, PORTS

./sandbox.sh setup           # clone + verify commit + install (has internet)
./sandbox.sh up              # start the app (NO internet) and the port gateway
./sandbox.sh status          # proves the app container cannot reach the internet
./sandbox.sh test            # run TEST_CMD offline
./sandbox.sh browser         # clean Chrome profile at the first port
./sandbox.sh reset           # delete everything
```

**Always review the code first, then copy the commit SHA** (`git log -1 --format=%H`) into `EXPECTED_COMMIT`. That SHA is what you vouch for.

### Private repo

Use a fine-grained, read-only token for that one repo. The token is not printed and is not written to disk:

```bash
GIT_TOKEN=$(gh auth token) ./sandbox.sh setup        # GitHub CLI login
read -rs GIT_TOKEN && export GIT_TOKEN && ./sandbox.sh setup
```

### Try it in 2 minutes (no network repo needed)

```bash
examples/make-demo-repo.sh /tmp/demo-repo > sandbox.env
./sandbox.sh setup && ./sandbox.sh up && ./sandbox.sh test && ./sandbox.sh status
curl localhost:3000
./sandbox.sh reset -y
```

## Configuration

Everything lives in `sandbox.env` (see [sandbox.env.example](sandbox.env.example)). Variables you set in your shell win over the file.

| Variable | Meaning |
|---|---|
| `REPO_URL` | `https://...` URL, or `/src` for a local repo given by `REPO_PATH` |
| `EXPECTED_COMMIT` | **Required.** Full 40-char SHA you reviewed |
| `REPO_REF` | Optional branch or tag to check out before verifying |
| `INSTALL_CMD` | Runs in the setup container, with internet, without any token |
| `START_CMD` | Runs in the offline app container. Must listen on `0.0.0.0` |
| `TEST_CMD` | Run by `./sandbox.sh test`, offline |
| `PORTS` | Space-separated ports forwarded to `127.0.0.1` |
| `BASE_IMAGE` | Debian/Ubuntu based image. Default `node:22-bookworm-slim` |

Other languages: set `BASE_IMAGE=python:3.12-slim-bookworm` and `INSTALL_CMD="pip install --only-binary=:all: -r requirements.txt"` (wheels only, so no `setup.py` runs), or `golang:1.23-bookworm` with `go mod download`.

## Commands

| Command | What it does |
|---|---|
| `setup` | Build, clone, verify commit, install |
| `up` / `down` / `restart` | Start and stop the app and gateway |
| `logs` / `shell` / `status` | Follow logs, open a shell, show containers and the offline proof |
| `test [cmd...]` | Run `TEST_CMD`, or your own command, in the offline container |
| `check` | Install hooks off, git identity, config sane |
| `online <cmd...>` | One command with internet and no token, e.g. `online npm install left-pad` |
| `import <path> [dir]` | Copy a file or folder from your machine into the repo, with no network |
| `push <branch>` | Push using `GIT_PUSH_TOKEN` (fine-grained, this repo only) |
| `bundle <branch>` | Write `out/<branch>.bundle` instead of pushing |
| `agent` | Optional Claude Code container, see below |
| `reset [-y]` | Delete containers and volumes |

Your work lives in a Docker volume, not on your disk. Get it out with `push` or `bundle`.

## Using an AI coding agent (optional)

`./sandbox.sh agent` starts [Claude Code](https://claude.com/claude-code) in its own container. It can reach the app at `http://app:PORT`. It needs `ANTHROPIC_API_KEY` or a `/login` inside the container, which is kept in its own volume.

**The agent container has internet** (it must call the model API) and it can run the repo's code. That is only acceptable for a commit you reviewed. Keep the agent honest with a `CLAUDE.md` and a `.claude/settings.json` that blocks `git commit`, `git push` and `.env` edits, and re-run every test it reports yourself with `./sandbox.sh test`. Use a separate API key with a spend limit, and run `reset` when done.

## Workflow that works

1. Read the code. Note the commit SHA.
2. `setup`, `up`, `status`.
3. Do the task. Review every diff yourself.
4. Run `./sandbox.sh test` yourself, offline.
5. Commit, then `push` or `bundle`.
6. `reset`.

## License

MIT
