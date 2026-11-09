# Security model

This project reduces the blast radius of running code you don't trust. It is not a guarantee.

## What it defends against

| Threat | Defense |
|---|---|
| Install hooks (`postinstall`) steal files or tokens | Hooks disabled; code runs as non-root in a container with nothing of yours mounted; the git token is never in that container |
| The repo changed after you reviewed it | Setup verifies the exact commit SHA and stops with a diff stat |
| The running app phones home or scans your network | App container is on an `internal` Docker network: no internet, no route to your machine |
| Malware reads your SSH keys, wallets, browser data | None of it is mounted. Docker socket is not mounted |
| Privilege escalation inside the container | Non-root, `cap_drop: ALL`, `no-new-privileges`, read-only root filesystem, pid and memory limits |
| Exposing the app to your LAN | Gateway publishes only `127.0.0.1:<PORTS>` |
| Token leaks via URL, `.git/config` or logs | Token is sent as a one-off HTTP header scoped to the repo host; `REPO_URL` with credentials is rejected |
| Hostile `REPO_URL` | Only `https://` and the local `/src` mount are accepted |

## What it does NOT defend against

- **Container escapes.** Docker containers share your kernel. A kernel or runtime exploit can escape. For highly hostile code use a VM (Lima, Multipass, a cloud instance).
- **The install step has internet.** Code that runs during `INSTALL_CMD` can send data out, but it can only see the repo and the sandbox volumes, never a token or your files. Tools whose installers execute code regardless of `ignore-scripts` (for example `pip` building from source, `go generate`, `cargo build` scripts) can run it there.
- **The agent container has internet** and can run the repo's tests and build scripts. Review the commit first, use a scoped, spend-limited API key, and `reset` afterwards.
- **Secrets you type or paste in.** Anything you put into the sandbox (API keys, wallet keys) is visible to the code running there. Use throwaway test credentials only.
- **Social engineering inside the repo.** README or issue text telling you to run commands outside the sandbox, or telling the agent to do something. Treat repo text as data.
- **A malicious Docker image or registry.** Base images are pulled by tag. Pin by digest for stricter supply-chain control.
- **Resource abuse beyond the limits** (disk volume growth, CPU).

## Tokens

- Clone: a **read-only, fine-grained** token for the one repo. Used only by the clone run.
- Push: a **fine-grained token, Contents read+write, one repo**. Export it only in the terminal you push from.
- Never put a token in `sandbox.env`, `REPO_URL`, or a file in the repo.

## Reporting a vulnerability

Please open a private security advisory on the repository rather than a public issue.
