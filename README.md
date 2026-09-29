# Text Actions

Run AI actions on the text you have selected in **any** window, from an
Omarchy overlay. Pick a built-in action, or type a free-form instruction.
Add your own models in an in-overlay settings screen. No account, no
hard-coded provider, no dependency on any secret manager.

```
select text  ->  Super+Alt+A  ->  pick an action  ->  Enter replaces the selection
```

## Features

- Works in any app: uses the focused window's copy key (terminals get
  `Ctrl+Shift+C`).
- 7 built-in actions in `actions.json` (Improve, Grammar, Longer, Shorter,
  Simplify, Rephrase, Continue) plus free-form instructions.
- **Manage your own models** inside the overlay: provider, base URL, model,
  and API key source. Saved to one file.
- Any OpenAI-compatible endpoint (OpenRouter, OpenAI, Groq, Ollama, LM Studio,
  vLLM, ...) and Azure OpenAI.
- API key can be a literal value, an environment variable, or a command that
  prints it (so `pass`, `op`, `hort`, ... all work).
- Result can replace the selection or be copied to the clipboard.

## Requirements

`jq`, `curl`, `wtype`, `wl-clipboard`, and Hyprland (`hyprctl`). All are
already present on a normal Omarchy install.

## Install

```bash
omarchy plugin add <git-url> --enable
```

Then bind `Super+Alt+A` to the plugin if it is not already bound:

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + ALT + A", "Text actions", "$HOME/.config/omarchy/plugins/nichovski.text-actions/bin/text-actions toggle")
```

## Usage

1. Select text in any window.
2. Press `Super+Alt+A`. The overlay captures the selection and opens.
3. Type to filter an action and press `Enter`, or type an instruction
   (e.g. "translate to German") and press `Enter`.
4. `Enter` replaces the selection, `Copy` copies the result, `Esc` goes back.

## Models and settings

Open settings from the overlay:

- the **Model: ...** button in the footer, or
- `Ctrl+,`

From there you can add, edit, delete, and choose the default model. Each
model has:

| Field | Meaning |
|---|---|
| Name | Label shown in the list |
| API type | `OpenAI-compatible` or `Azure OpenAI` |
| Base URL | e.g. `https://openrouter.ai/api/v1` (OpenAI-compatible) |
| Model | the provider's model id, e.g. `openai/gpt-4o-mini` |
| Endpoint / Deployment / API version | Azure only |
| API key | literal key, stored in the config file |
| API key env var | name of an environment variable holding the key |
| Key command | a command that prints the key, e.g. `pass show openai` |

The key is resolved in that order: **API key, then env var, then command**.
Use whichever fits you; nothing requires a specific secret tool.

## Config file

Everything is stored in one file:

```
~/.config/text-actions/config.json
```

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

The file may contain an API key, so it is written with `0600` permissions.
Override its location with `TEXT_ACTIONS_CONFIG` if you like.

An old `provider`/`providers` config is upgraded to the model list on first
run.

## Commands

`bin/text-actions` is the engine and can be driven from a terminal:

```
text-actions toggle
text-actions run --action <id> [--model <id>] -- <text>
text-actions run --custom [--model <id>] -- <text> --instruction <instr>
text-actions paste <text>
text-actions copy  <text>
text-actions capture            # print the current selection (debugging)
text-actions list               # actions as JSON
text-actions config             # the whole config as JSON
text-actions models             # model list + default
text-actions model-save <json>  # add or update one model
text-actions model-delete <id>
text-actions set-model <id>
```

## License

MIT