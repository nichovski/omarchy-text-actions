# Changelog

All notable changes to this project are documented here.

## [Unreleased]

## [0.2.1] - 2026-09-29

### Security
- The API key and the selected text reach `curl` through files, never the process command line.
- Provider responses are capped with `--max-filesize`, and result/error text is truncated before buffering.
- Models are saved over stdin instead of as a command-line argument.

## [0.2.0] - 2026-09-29

### Added
- In-overlay settings screen (`Ctrl+,`) to add, edit, delete, and choose your own models.
- Support for any OpenAI-compatible endpoint and Azure OpenAI.
- API keys from a literal value, an environment variable, or a command that prints it, so no secret tool is required.
- `config`, `models`, `model-save`, `model-delete`, and `set-model` subcommands.
- README, MIT license, and an example config.

### Changed
- Configuration is now a single `models`-based file (version 2). Old `provider`/`providers` configs are upgraded on first run.
- `run` takes `--model <id>` and a `--` separator before the text.

### Fixed
- A failed API-key lookup no longer continues and calls the provider with an empty key.

## [0.1.0] - 2026-09-29

### Added
- Omarchy overlay that runs an AI action on the current selection from any window.
- Seven built-in actions plus free-form instructions.
- Result can replace the selection or be copied to the clipboard.
