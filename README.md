# im

> **i**nfinite **m**emory for your AI agents — one private Git repo, every agent, every machine.

`im` is a cross-platform (macOS & Windows) desktop tool that gives all of your AI agents a single, shared, version-controlled home for their **memories**, **skills**, **MCP servers**, and **documents**.

> **Status:** early stage / pre-alpha. The design is being worked out in the open — expect breaking changes.

---

## The problem

If you use more than one AI agent (Claude Code, Codex, Cursor, Gemini CLI, Copilot, ...) across more than one machine, you have probably run into this:

- **Memories are siloed.** Each agent keeps its own notes, preferences and project context in its own format and location. What one agent learned, the others never see.
- **Skills and prompts are copy-pasted.** The same skill or rule file lives in five places, slowly drifting apart.
- **MCP configs are scattered.** Every agent has its own MCP config file with its own schema. Adding one server means editing several files on every machine.
- **Nothing is portable.** A new laptop, or a Windows box next to your Mac, means rebuilding everything by hand.
- **No history.** When an agent overwrites a memory or a config, there is no easy way to see what changed or roll it back.

## The idea

`im` uses a **private Git repository as a remote database**.

```
              ┌────────────────────────────┐
              │  Private GitHub repository │  ← single source of truth:
              │  memories · skills · MCP   │    versioned, private, yours
              │  docs · ...                │
              └─────────────▲──────────────┘
                            │ git pull / push
           ┌────────────────┼────────────────┐
           │                │                │
     ┌─────┴─────┐    ┌─────┴─────┐    ┌─────┴─────┐
     │ im        │    │ im        │    │ im        │
     │ (macOS)   │    │ (Windows) │    │ (...)     │
     └─────┬─────┘    └───────────┘    └───────────┘
           │ sync into each agent's native format
     ┌─────┼─────┬─────────┐
     ▼     ▼     ▼         ▼
  Claude Codex Cursor     ...
```

1. On first launch, `im` connects to an existing private GitHub repository — or creates a new one for you.
2. That repository becomes the canonical store for everything your agents should share.
3. `im` keeps a local clone in sync and projects its contents into each agent's native locations and formats (memory files, skill folders, MCP config files, ...).
4. Changes made by any agent on any machine are committed and pushed back, so every other agent and machine picks them up.

Because the backend is plain Git, you get versioning, diffs, rollback, offline use and full ownership of your data for free — no extra server, no vendor lock-in.

## ⚠️ Security: keep your repository private

> [!WARNING]
> **Your `im` repository must always be private. Never make it public.**
>
> The data `im` syncs is personal and often sensitive. MCP server configs in particular frequently contain API keys and access tokens (for example in their `env` fields), and these are stored in the repository as-is.
>
> - Only connect `im` to a **private** repository, and never change its visibility to public.
> - Be careful when adding collaborators — anyone with access can read everything in it, including secrets.
> - Anything committed stays in Git history. Deleting a file later does **not** remove a leaked secret; if one is ever exposed, revoke and rotate it immediately.
> - Protect the GitHub account and token that `im` uses (enable 2FA).

## What gets managed

| Kind        | Examples                                                        |
|-------------|-----------------------------------------------------------------|
| Memories    | user preferences, project notes, feedback, long-term context    |
| Skills      | reusable skills / prompts / rule files                          |
| MCP servers | server definitions, rendered into each agent's MCP config       |
| Documents   | reference docs, checklists, anything your agents should read    |

## Goals

- **Private by default** — your data lives only in a private repository you own.
- **Agent-agnostic** — one canonical format, with adapters per agent.
- **Cross-platform** — first-class support for macOS and Windows.
- **Git-native** — human-readable files, meaningful commits, easy to inspect and edit by hand.
- **Zero server** — nothing to host; GitHub is the only remote.

## Repository layout

When `im` connects to a repository it adds this layout (existing files are never overwritten):

```
README.md            how the repository is organized, plus tips
mcp/                 MCP server definitions, one JSON file per server
skills/              reusable skills, one folder per skill with a SKILL.md
memory/
  index.md           bookmark index of every memory, read first by agents
  personal/          global memories about you
  project/<name>/    memories for a single project
```

The local copy lives in `~/.im/repos/<owner>/<repo>`.

## Getting started (macOS)

Requirements: macOS 13 or later, Xcode 15 or later (or the Swift toolchain), and git.

```sh
cd apps/macos
scripts/build-app.sh          # builds apps/macos/build/im.app
open build/im.app
```

A cat appears in the menu bar. On first launch `im` asks you to:

1. **Sign in to GitHub**, either by reusing an existing [GitHub CLI](https://cli.github.com) login or by pasting a personal access token with the `repo` scope. The token is stored in the macOS Keychain.
2. **Create a new private repository** or **pick an existing private one**. Public repositories are refused.

`im` then clones it, adds the layout above, and pushes.

For development, `swift run` starts the app straight from the package and `swift test` runs the tests.

### Skills

`im` finds the personal skills of **Claude Code** (`~/.claude/skills`) and **Codex**, CLI and desktop app (`~/.agents/skills`, plus the legacy `~/.codex/skills`). It asks which ones to link:

- A **linked** skill lives once in the repository's `skills/<name>/`. Each agent you pick gets a symlink to it, so a skill that only existed in Claude Code can also be used by Codex.
- Copies are compared by content. Identical copies merge on their own. When they differ, you see which files differ and choose the version to keep.
- Skills you don't link stay exactly where they are. Replaced folders are moved to `~/.im/backup/`, never deleted.
- **Reload** (or **Skills…** in the menu) commits edits to linked skills, pulls what other machines added, pushes, and shows the list again.
- Disconnecting or switching repositories first turns linked skills back into regular folders, so the agents keep working.

> Linked skills point into the local clone under `~/.im/repos/`. Don't delete or move it while skills are linked; disconnect from the menu instead.

### Pick your cat

The menu bar cat comes in five breeds: **Calico** (default), **British Blue**, **Orange Tabby**, **Ragdoll** and **American Shorthair**. Choose one from the **Cat** menu.

The choice is stored in `~/.im/config.json`, which `im` watches. You (or your AI agent) can switch cats by editing it:

```json
{ "cat": "ragdoll" }
```

### Language

`im` speaks **English** (default) and **Simplified Chinese**. Switch in the **Language** menu, or set `"language": "en"` or `"zh-Hans"` in `~/.im/config.json`.

### Custom cats

To draw your own cat, choose **Cat → Open Cats Folder…** and add a `<id>.json` file there. A cat is pixel art: a palette plus rows of characters. The folder's README documents the format with the built-in calico as an example. New and edited cats show up immediately, and a file with a mistake is listed in the menu with the reason.

## Roadmap

- [x] macOS menu bar app
- [x] GitHub sign-in and private repository connect / create
- [x] Repository layout for memories, skills and MCP
- [ ] Windows app
- [ ] Local clone + background sync (pull / commit / push)
- [ ] Agent adapters (starting with Claude Code)
- [ ] MCP config rendering per agent
- [ ] Conflict handling
- [ ] More agents and more Git hosts (GitLab, Gitea, self-hosted, ...)

Initially, **GitHub is the only supported remote**.

## Contributing

The project is just getting started. Issues, ideas and discussion are very welcome — please open an issue to share how you use multiple agents today and what you would like `im` to handle.

## License

[MIT](LICENSE)
