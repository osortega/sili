# sili

> A tiny CLI that manages GitHub Codespaces and transparently starts a VS Code
> tunnel inside them, so you can attach from `vscode.dev` or desktop VS Code
> without ever running `code tunnel` by hand.

`sili` is a **resource manager**, not an attach tool. You use it to spin a
codespace up, wake it from sleep, or tear it down. Once it prints a tunnel
URL, you connect through that URL in your editor — `sili` itself stays out
of the way.

```text
$ sili create -r osortega/sili -b main
[sili] creating codespace (-r osortega/sili -b main)
[sili] created: literate-spork-7q4j5
[sili] ensuring 'code-insiders tunnel' is running in literate-spork-7q4j5
[remote] started: code-insiders tunnel --name literate-spork-7q4j5
[remote] log: /home/codespace/.sili/tunnel.log

Tunnel: https://insiders.vscode.dev/tunnel/literate-spork-7q4j5
```

## Why

The default `gh codespace` workflow has three rough edges this tool smooths
over:

1. Restoring a stopped codespace and starting a tunnel inside it is two
   manual steps.
2. `code tunnel` (stable) and `code-insiders tunnel` (insiders) are different
   binaries — easy to forget which one your codespace has.
3. The tunnel needs to survive SSH disconnect, but `gh codespace ssh` doesn't
   detach background processes for you.

`sili create` and `sili start` collapse all three into one command.

## Requirements

| Tool                                          | Required | Used for                              |
|-----------------------------------------------|----------|---------------------------------------|
| [`gh`](https://cli.github.com/)               | yes      | all codespace operations              |
| `ssh`                                         | yes      | transport for `gh codespace ssh`      |
| `bash` 4+                                     | yes      | the scripts themselves                |
| [`fzf`](https://github.com/junegunn/fzf)      | optional | nicer interactive picker              |
| [`jq`](https://stedolan.github.io/jq/)        | optional | parsing `gh codespace list --json`    |

You must be logged in via `gh auth login` before using `sili`. The first run
will fail loudly if you aren't.

## Install

```sh
git clone https://github.com/osortega/sili.git
cd sili
./install.sh
```

`install.sh` symlinks `bin/sili` into `~/.local/bin` (or `$SILI_INSTALL_DIR`
if set). Make sure that directory is on your `$PATH`.

To uninstall:

```sh
rm "$(command -v sili)"
```

## Usage

```
sili create [-r OWNER/REPO] [-b BRANCH] [-m MACHINE] [-l LOCATION] [--stable]
sili start  [NAME] [--stable]
sili list
sili stop   [NAME]
sili delete [NAME]
sili help
```

### `sili create`

Provisions a new codespace via `gh codespace create`, then starts a tunnel
inside it. All flags after the subcommand are forwarded to `gh codespace
create`, except `--stable`, which `sili` consumes itself.

```sh
sili create -r osortega/sili -b main
sili create -r osortega/sili -m standardLinux32gb -l WestUs2
```

### `sili start [NAME]`

Wakes an existing codespace (resuming it if stopped) and ensures the tunnel
is running. If `NAME` is omitted, an interactive picker appears: `fzf` if
installed, a numbered prompt otherwise.

```sh
sili start                       # pick interactively
sili start literate-spork-7q4j5  # by name
```

Re-running `sili start` against a codespace whose tunnel is already up is a
safe no-op — it just re-prints the URL.

### `sili list` / `sili stop` / `sili delete`

Thin pass-throughs to `gh codespace`. `stop` and `delete` accept an optional
name and otherwise show the picker.

## Configuration

| Variable             | Default              | Effect                                                          |
|----------------------|----------------------|-----------------------------------------------------------------|
| `SILI_QUALITY`       | `insiders`           | `stable` switches to `code tunnel` instead of `code-insiders`.  |
| `SILI_TUNNEL_NAME`   | codespace name       | Overrides the registered tunnel display name.                   |
| `SILI_INSTALL_DIR`   | `~/.local/bin`       | Used by `install.sh` to choose the symlink directory.           |

The `--stable` flag is equivalent to `SILI_QUALITY=stable` for a single
invocation and takes precedence.

## How it works

`sili` is a Bash dispatcher in `bin/sili` that sources subcommand files from
`lib/sili/`. The only non-trivial piece is `lib/sili/ensure_tunnel.sh`, which
ships a self-contained shell script into the codespace via
`gh codespace ssh -- bash -s`. Inside the codespace it:

1. Short-circuits via `pgrep -f '<bin> tunnel'` if a tunnel is already up.
2. Falls back from `code-insiders` to `code` (or vice versa) if only one is
   on the codespace's `PATH`.
3. Starts the tunnel detached:

   ```sh
   nohup code-insiders tunnel \
     --accept-server-license-terms \
     --name "$codespace_name" \
     >> ~/.sili/tunnel.log 2>&1 &
   disown
   ```

4. Echoes the URL the user should open.

There is no local state file. `gh codespace list` is the source of truth.

## Authentication

`sili` itself stores no credentials. It piggybacks on three layers of auth:

- **GitHub API** — handled by `gh`. Run `gh auth login` once.
- **SSH to the codespace** — handled by `gh codespace ssh`, which provisions
  keys automatically.
- **The tunnel** — handled by `code tunnel` itself, which registers under
  your GitHub or Microsoft account on first run.

See [Troubleshooting](#troubleshooting) for the first-run tunnel auth case.

## Troubleshooting

### First-run tunnel auth: "where do I enter the device code?"

The very first time `code tunnel` runs in a fresh codespace it prints a
device-code prompt like `To grant access, open https://github.com/login/device
and enter ABCD-1234`. Because `sili` runs the tunnel detached with output
redirected to `~/.sili/tunnel.log`, that prompt does not appear in your
terminal. Tail the log to grab it:

```sh
gh codespace ssh -c <name> -- tail -f ~/.sili/tunnel.log
```

Once you authorize the tunnel, the codespace remembers it. Subsequent
`sili start` calls are silent.

### `gh: not authenticated`

Run `gh auth login` and re-try. `sili` checks `gh auth status` up front and
refuses to do anything until that passes.

### `neither code nor code-insiders available on PATH`

Rare — the standard codespaces base image ships both. If you see this on a
custom image, add the binary to your devcontainer or pass `--stable` /
`SILI_QUALITY=stable` to switch to whichever one you do have.

### The tunnel URL 404s

Two common causes: (1) the tunnel hasn't finished registering yet — wait a
few seconds and refresh; (2) you're signed into a different account in the
browser than the one that authorized the tunnel.

## Layout

```
bin/sili                   # dispatcher
lib/sili/common.sh         # logging, deps, picker, quality resolver
lib/sili/ensure_tunnel.sh  # the remote tunnel-start routine
lib/sili/cmd_create.sh     # create handler
lib/sili/cmd_start.sh      # wake handler
lib/sili/cmd_list.sh
lib/sili/cmd_stop.sh
lib/sili/cmd_delete.sh
install.sh                 # symlink installer
```

## Contributing

Bug reports and PRs welcome. Before sending a patch:

```sh
shellcheck bin/sili lib/sili/*.sh install.sh
bash -n  bin/sili lib/sili/*.sh install.sh
```
