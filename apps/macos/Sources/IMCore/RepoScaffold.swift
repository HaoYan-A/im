import Foundation

/// The layout im creates in a memory repository.
///
///     README.md
///     mcp/
///     skills/
///     memory/
///       index.md
///       personal/
///       project/
public enum RepoScaffold {
    public enum Entry: Sendable {
        case file(String, contents: String)
        /// Kept in git with a `.gitkeep` while it has no other content.
        case directory(String)
    }

    public static let entries: [Entry] = [
        .file("README.md", contents: Templates.readme),
        .directory("mcp"),
        .directory("skills"),
        .file("memory/index.md", contents: Templates.memoryIndex),
        .directory("memory/personal"),
        .directory("memory/project"),
    ]

    /// Creates every missing entry under `root`. Existing files are never modified.
    /// - Returns: The paths it created, relative to `root`.
    @discardableResult
    public static func apply(at root: URL) throws -> [String] {
        let fm = FileManager.default
        var created: [String] = []

        func write(_ path: String, _ contents: String) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
            created.append(path)
        }

        for entry in entries {
            switch entry {
            case let .file(path, contents):
                if !fm.fileExists(atPath: root.appendingPathComponent(path).path) {
                    try write(path, contents)
                }
            case let .directory(path):
                let url = root.appendingPathComponent(path)
                let children = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
                if children.allSatisfy({ $0 == ".DS_Store" }) {
                    try write("\(path)/.gitkeep", "")
                }
            }
        }
        return created
    }
}

enum Templates {
    static let readme = """
    # im memory

    This private repository is the shared memory of your AI agents, managed by [im](https://github.com/HaoYan-A/im). \
    Every agent on every machine reads from and writes to it, and Git keeps the full history.

    > [!WARNING]
    > **Keep this repository private.** It holds personal memories and often secrets, such as API keys inside MCP configs. \
    Never make it public, and be careful who you add as a collaborator. Anything ever committed stays in the Git history.

    ## Layout

    ```
    .
    ├── README.md          you are here
    ├── mcp/               MCP server definitions
    ├── skills/            reusable skills
    └── memory/
        ├── index.md       bookmark index of every memory, read this first
        ├── personal/      global memories about you, shared by all projects
        └── project/       per-project memories, one folder per project
            └── <project>/
    ```

    ### `memory/`

    - **`index.md`** is the table of contents. Agents read it first and open only the files they need, \
    so keep it short: one line per memory.
    - **`personal/`** holds memories that apply everywhere: who you are, how you like to work, the tools you prefer.
    - **`project/<project>/`** holds memories that matter for a single project: decisions, constraints, context. \
    Name the folder after the project's repository or directory.

    Each memory is a small Markdown file holding **one fact**, with a short front matter:

    ```markdown
    ---
    name: prefers-pnpm
    description: Use pnpm instead of npm in every JavaScript project
    ---

    Use pnpm to install dependencies and run scripts.

    **Why:** one lockfile format across all machines.
    ```

    ### `skills/`

    One folder per skill, each with a `SKILL.md` that says when and how to use it:

    ```
    skills/
    └── <skill-name>/
        ├── SKILL.md
        └── ...supporting files
    ```

    ### `mcp/`

    One JSON file per MCP server, named after the server, for example `mcp/github.json`:

    ```json
    {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "<token>" }
    }
    ```

    ## Tips

    - **One fact per file.** Small files are easy for agents to find, update and delete.
    - **Keep `memory/index.md` in sync** whenever a memory is added, renamed or removed.
    - **Update instead of duplicating.** Look for an existing memory before writing a new one.
    - **Delete stale memories.** A wrong memory is worse than a missing one.
    - **Use absolute dates** such as `2026-10-19`, never "yesterday" or "last week".
    - **Edit by hand anytime.** It is plain Markdown in Git: clone, edit, commit, push.
    - `.gitkeep` files only keep empty folders in Git. Delete them once a folder has content.

    """

    static let memoryIndex = """
    # Memory index

    Bookmarks to every memory in this repository. Agents read this file first, then open only what they need.

    One line per memory: `- [Title](path/to/file.md) — one-line hook`

    ## Personal

    <!-- - [Prefers pnpm](personal/prefers-pnpm.md) — use pnpm instead of npm everywhere -->

    ## Projects

    <!--
    ### my-app
    - [Deploy target](project/my-app/deploy-target.md) — production runs on Fly.io
    -->

    """
}
