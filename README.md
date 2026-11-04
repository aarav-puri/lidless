# Lidless

Cloud mode for local agents. Lidless keeps a Mac awake with the lid closed for exactly as long as a coding agent is working, then lets it sleep. No timers.

- `app/`: the macOS menubar app and `lidless` command line tool (Swift, no dependencies). Build and install with `app/build.command`; `app/build.command --no-install` only builds and runs the self-test.
- `website/`: the landing page, a single static `index.html`.

## How it works

- Claude Code and Codex: hooks (`~/.claude/settings.json`, `~/.codex/hooks.json`, plus `codex_hooks = true` in `~/.codex/config.toml`) on `UserPromptSubmit`, `Stop`, `SessionEnd` and Codex's `Interrupt` write and remove hold files in `~/Library/Application Support/Lidless/holds`. They are installed in the background; Codex asks to review them once. Until an agent's hooks have fired, it is tracked by CPU like the others.
- Other agents (Gemini CLI, Aider, OpenCode, Cursor Agent, Goose, Amp, Qwen Code, Crush, Droid, Copilot CLI): detected from the process list, working while the agent's process tree uses CPU, released after two quiet minutes.
- Anything else: `lidless run -- <command>`.
- While anything is working: `sudo -n pmset -a disablesleep 1` plus an idle-sleep assertion. When everything finishes: `disablesleep 0`, and if the lid is shut with no external display, `pmset sleepnow`.
- Safety: lets go at 20% battery on battery power, on a critical thermal state, and on quit. A crash is repaired on next launch.
- Set Up installs `/etc/sudoers.d/lidless` (only the two pmset commands) and links `/usr/local/bin/lidless`. Uninstall in the menu removes everything.

## Privacy

No network access, no telemetry, no analytics.
