# Text Actions - user-managed models

**Date:** 2026-09-29 · **Branch:** main · **Author:** Bogdan

## What it does

An Omarchy shell overlay that runs an AI action on the text you have selected
in any window. Select text, press `Super+Alt+A`, pick a built-in action or type
a free-form instruction, and the result can replace the selection or be copied.

This session added an in-overlay settings screen so anyone can add and manage
their own models, with the whole setup in one config file. It is the first
version meant to be shared and submitted to the Omarchy plugin marketplace.

## Why

The first version hard-wired a single provider and read its key with
`hort --secret`. That only works on a machine that has both. To open the plugin
to other people, the model list and the key source had to become the user's
data, edited from inside the plugin, not from a file only the author knew about.

The design decisions:

- **One file.** Everything lives in `~/.config/text-actions/config.json`
  (`version: 2`). Nothing else is read.
- **Models, not providers.** A `models` array is the unit; each entry picks its
  own provider and model string.
- **Keys three ways.** `apiKey` (literal), `apiKeyEnv` (environment variable),
  or `keyCommand` (a command that prints the key). Resolved in that order, so
  `pass`, `op`, `hort`, or a plain pasted key all work. This keeps the tool
  usable without `hort` while still supporting it.
- **The script owns the config; the QML owns the UI.** The overlay never writes
  JSON. It calls `model-save`, `model-delete`, `set-model`, and `config`, so
  validation and file permissions live in one place.

## How it works

Files:

| File | Role |
|---|---|
| `bin/text-actions` | Selection capture, config read/write, provider calls, paste/copy |
| `TextActions.qml` | Actions list, result pane, settings list, model edit form |
| `actions.json` | The built-in action prompts |
| `manifest.json` | Plugin manifest, id `nichovski.text-actions`, kind `overlay` |

Config schema:

```json
{
  "version": 2,
  "defaultModel": "gpt-4o-mini",
  "models": [
    {
      "id": "gpt-4o-mini",
      "label": "GPT-4o mini",
      "type": "openai",
      "baseUrl": "https://openrouter.ai/api/v1",
      "model": "openai/gpt-4o-mini",
      "apiKey": "",
      "apiKeyEnv": "OPENROUTER_API_KEY",
      "keyCommand": "",
      "endpoint": "",
      "deployment": "",
      "apiVersion": ""
    }
  ]
}
```

- `type` is `openai` (any OpenAI-compatible endpoint) or `azure`.
- The file may hold an API key, so it is written `0600` and migrated from the
  old `provider`/`providers` shape automatically on first run.
- `model-save` normalises the entry, derives an `id` from the label when none is
  given, and validates the URL / Azure fields.

Settings flow in the QML: `Ctrl+,` (or the footer **Model** button) sets
`mode: "settings"` and reloads the config via the `config` subcommand. Selecting
a row opens `mode: "edit"` with the fields bound to `f*` properties; Save posts
the built object to `model-save`. `Ctrl+S` saves, `Esc` goes back.

One bug worth recording: a failed key lookup inside a nested command
substitution (`key="$(api_key_of ...)"`) did not stop the parent shell under
`set -e`, so `run` continued and called the provider with an empty key. Fixed by
making the substitutions fail hard (`|| exit 1`).

## Notes

- **Editing the QML needs `omarchy restart shell`.** The plugin's own hot-reload
  did not pick up the new `TextActions.qml`; a shell restart did. The manifest
  validates and the QML parses, but the running instance stayed on the old code
  until restarted.
- `relay` was skipped for this work: the pi session has no Agent tool with the
  Fable/Sonnet model selectors, so no independent review ran.
- Published at `github.com/nichovski/omarchy-text-actions`.
- Suggested marketplace submission: category `Productivity`, tags
  `ai, quickshell, launcher`.
- Not yet in the marketplace; a submission issue must be filed.