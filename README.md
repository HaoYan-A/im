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

## Roadmap

- [ ] Project scaffolding (macOS + Windows)
- [ ] GitHub sign-in and private repository connect / create
- [ ] Repository layout spec for memories, skills, MCP and docs
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
