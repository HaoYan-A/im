import Foundation
import IMCore

/// The repository im is connected to.
struct Connection: Codable, Equatable {
    var fullName: String
    var htmlURL: URL
    var localPath: URL
    /// Commit identity for im's own commits when git has none configured.
    var identity: GitIdentity?
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var connection: Connection?
    /// True while im is talking to GitHub or running git; the cat wags its tail.
    @Published var busy = false

    private static let connectionKey = "connection"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.connectionKey) {
            connection = try? JSONDecoder().decode(Connection.self, from: data)
        }
    }

    /// Switches to `connection`. Skills linked to a different, previous repository are turned back into
    /// real folders first, so the agents don't depend on a clone im no longer manages.
    /// - Returns: How many skills were unlinked.
    @discardableResult
    func connect(_ connection: Connection) async throws -> Int {
        var released = 0
        if let previous = self.connection, previous.fullName != connection.fullName {
            released = try await Self.unlinkSkills(of: previous)
        }
        self.connection = connection
        UserDefaults.standard.set(try? JSONEncoder().encode(connection), forKey: Self.connectionKey)
        return released
    }

    /// Unlinks this repository's skills, then forgets the repository and the token. The local clone is left on disk.
    func disconnect() async throws {
        if let connection {
            try await Self.unlinkSkills(of: connection)
        }
        connection = nil
        UserDefaults.standard.removeObject(forKey: Self.connectionKey)
        TokenStore.delete()
    }

    /// Skills currently linked into the connected repository.
    func linkedSkillCount() async -> Int {
        guard let connection else { return 0 }
        let environment = SkillEnvironment.live(repository: connection.localPath)
        return await Task.detached { SkillScanner.scan(environment).filter { !$0.linkedAgents.isEmpty }.count }.value
    }

    @discardableResult
    private static func unlinkSkills(of connection: Connection) async throws -> Int {
        let linker = SkillLinker(environment: .live(repository: connection.localPath))
        return try await Task.detached { try linker.unlinkAll() }.value
    }
}
