import Foundation

public struct CommandError: LocalizedError {
    public let command: String
    public let status: Int32
    public let output: String

    public var errorDescription: String? {
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return L("`\(command)` failed (exit \(status))", "`\(command)` 执行失败（退出码 \(status)）")
            + (detail.isEmpty ? "" : L(":", "：") + "\n\(detail)")
    }
}

enum Command {
    /// Runs a process to completion and returns its combined stdout and stderr. Blocks the calling thread.
    static func run(
        _ executable: URL,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        // One pipe for both streams so a full stderr buffer can never block us while we drain stdout.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let name = executable.lastPathComponent
            throw CommandError(command: ([name] + arguments).joined(separator: " "), status: process.terminationStatus, output: output)
        }
        return output
    }
}

/// Who commits when git has no identity configured.
public struct GitIdentity: Sendable, Codable, Equatable {
    public let name: String
    public let email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

/// Runs the system git. The GitHub token is handed over through environment-provided config,
/// so it never ends up in a remote URL, `.git/config` or the process arguments.
public struct Git: Sendable {
    public var executable = URL(fileURLWithPath: "/usr/bin/git")
    public var token: String?
    /// Extra environment, e.g. to isolate tests from the user's global git config.
    public var environment: [String: String] = [:]

    public init(token: String? = nil, environment: [String: String] = [:]) {
        self.token = token
        self.environment = environment
    }

    @discardableResult
    public func run(_ arguments: [String], in directory: URL? = nil) throws -> String {
        try Command.run(executable, arguments, in: directory, environment: processEnvironment)
    }

    /// Sets the repository's commit identity from `fallback` for whatever git has no value for.
    public func ensureIdentity(in repository: URL, fallback: GitIdentity) throws {
        if (try? run(["config", "user.name"], in: repository)) == nil {
            try run(["config", "user.name", fallback.name], in: repository)
        }
        if (try? run(["config", "user.email"], in: repository)) == nil {
            try run(["config", "user.email", fallback.email], in: repository)
        }
    }

    private var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        if let token {
            let basic = Data("x-access-token:\(token)".utf8).base64EncodedString()
            env["GIT_CONFIG_COUNT"] = "2"
            env["GIT_CONFIG_KEY_0"] = "http.https://github.com/.extraheader"
            env["GIT_CONFIG_VALUE_0"] = "AUTHORIZATION: basic \(basic)"
            // Don't let a credential helper store or substitute credentials for this session.
            env["GIT_CONFIG_KEY_1"] = "credential.helper"
            env["GIT_CONFIG_VALUE_1"] = ""
        }
        env.merge(environment) { _, new in new }
        return env
    }
}
