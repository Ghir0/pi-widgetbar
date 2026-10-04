# Pi Agent Status for Omarchy

A Quickshell bar widget for Omarchy that shows Pi coding-agent sessions at a glance. The bar indicator reflects active work and sessions waiting for a response; clicking it opens a panel with session and token-usage summaries.

## Features

- Per-session status: working, waiting for a response, or idle
- Session details including project directory, model, provider, thinking level, message count, and age
- Token usage totals for today and all saved sessions
- Opens Pi in a new terminal from the panel
- Reads session files locally; prompts and tool contents are never displayed or sent anywhere

## Requirements

- Omarchy with the shell plugin system
- Pi coding agent with session files under `~/.pi/agent/sessions`
- Python 3

Set `PI_CODING_AGENT_DIR` if your Pi agent data directory is not `~/.pi/agent`.

## Install

```bash
omarchy plugin add https://github.com/Ghir0/pi-widgetbar.git --enable
```

The widget is enabled in the bar using its manifest default placement. To move it:

```bash
omarchy bar move io.github.ghir0.pi-agent --section center
```

To remove it:

```bash
omarchy plugin remove io.github.ghir0.pi-agent
```

## Status and privacy

A session is considered active for 120 seconds after its latest message. A recent user message or assistant tool call is shown as working; a completed assistant response is shown as waiting for a response.

The helper reads local Pi session JSONL files and emits only session metadata and token usage. It does not include prompt text, assistant response text, tool arguments/results, or credentials in its output. Session files are not modified, and no data is transmitted.

## Development

The plugin consists of `manifest.json`, `Panel.qml`, and `status.py`. Validate the plugin with:

```bash
omarchy plugin validate .
```

## License

MIT. See [LICENSE](LICENSE).
