import Foundation
import IMCore

/// The repository im is connected to.
struct Connection: Codable, Equatable {
    var fullName: String
    var htmlURL: URL
    var localPath: URL
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

    func connect(_ connection: Connection) {
        self.connection = connection
        UserDefaults.standard.set(try? JSONEncoder().encode(connection), forKey: Self.connectionKey)
    }

    /// Forgets the repository and the token. The local clone is left on disk.
    func disconnect() {
        connection = nil
        UserDefaults.standard.removeObject(forKey: Self.connectionKey)
        TokenStore.delete()
    }
}
