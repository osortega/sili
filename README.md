# sili

A small CLI that manages GitHub Codespaces and transparently starts a VS Code
tunnel inside them, so you can attach from `vscode.dev` or desktop VS Code
without ever running `code tunnel` by hand.

`sili` is a **resource manager**, not an attach tool. You use it to spin a
codespace up or down. Once it prints a tunnel URL, you connect through that
URL in your editor.

## Install

Requires [`gh`](https://cli.github.com/) (authenticated via `gh auth login`)
and `ssh`. Optional: `fzf` for nicer pickers, `jq` for richer parsing.

```sh
git clone https://github.com/osortega/sili.git
cd sili
./install.sh                    # symlinks bin/sili into ~/.local/bin
```

## Usage

```
sili create [-r OWNER/REPO] [-b BRANCH] [-m MACHINE] [-l LOCATION] [--stable]
sili start  [NAME] [--stable]
sili list
sili stop   [NAME]
sili delete [NAME]
```

`create` provisions a new codespace and starts the tunnel inside it. `start`
wakes an existing (possibly stopped) codespace and ensures the tunnel is
running. Both print a URL like:

```
Tunnel: https://insiders.vscode.dev/tunnel/<name>
```

Open it in your browser, or in desktop VS Code use the **Remote — Tunnels**
extension.

## Tunnel quality

Defaults to `code-insiders tunnel`. To use stable VS Code instead:

```sh
sili start my-codespace --stable
# or
SILI_QUALITY=stable sili start my-codespace
```

## How the tunnel runs

Inside the codespace, `sili` runs (idempotently):

```sh
nohup code-insiders tunnel \
  --accept-server-license-terms \
  --name "$codespace_name" \
  >> ~/.sili/tunnel.log 2>&1 &
```

A `pgrep` check short-circuits if a tunnel is already running, so re-running
`sili start foo` is always safe.
