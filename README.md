# sili

A tiny CLI for managing GitHub Codespaces with an automatic VS Code tunnel.

`sili` wakes a codespace and prints a `vscode.dev/tunnel/...` URL you can
open in any browser or attach to from desktop VS Code. That's it — once
you're connected, you don't go back to `sili` until it's time to stop or
delete the codespace.

```text
$ sili start
[sili] waking literate-spork-7q4j5
[sili] ensuring tunnel is running

Tunnel: https://insiders.vscode.dev/tunnel/literate-spork-7q4j5
```

## Install

### Homebrew (recommended)

```sh
brew install osortega/tap/sili
```

### From source

```sh
git clone https://github.com/osortega/sili.git
cd sili
./install.sh
```

Make sure [`gh`](https://cli.github.com/) is installed and you've run
`gh auth login`.

## Usage

```
sili create [gh-codespace-create flags] [--stable]
sili start  [NAME] [--stable]
sili list
sili stop   [NAME]
sili delete [NAME]
```

- `sili create` — provision a new codespace and start a tunnel inside it.
- `sili start` — wake an existing codespace (resuming if stopped) and
  ensure the tunnel is running. Without a name, an interactive picker
  appears.
- `sili list` / `sili stop` / `sili delete` — manage existing codespaces.

By default the tunnel uses VS Code Insiders. Pass `--stable` to use
stable VS Code instead.

## Configuration

| Variable           | Effect                                      |
|--------------------|---------------------------------------------|
| `SILI_QUALITY`     | `stable` or `insiders` (default: insiders)  |
| `SILI_TUNNEL_NAME` | Override the tunnel display name            |

## Troubleshooting

**First time you start a tunnel in a codespace, the URL 404s.**
The tunnel needs to register with GitHub once. Tail the log to find
the device-code prompt:

```sh
gh codespace ssh -c <name> -- tail -f ~/.sili/tunnel.log
```

After you authorize it, `sili start` is silent on subsequent runs.
