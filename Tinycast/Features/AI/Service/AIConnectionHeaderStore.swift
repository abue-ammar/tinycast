import Foundation

struct AIConnectionHeaderStore: Sendable {
    enum StoreError: Error {
        case unavailable
    }

    private struct StoredHeaders: Codable {
        let provider: AIProviderKind
        let baseURL: String
        let values: [String: String]
    }

    private let read: @Sendable (UUID) throws -> String?
    private let write: @Sendable (String?, UUID) throws -> Void

    init(
        read: @escaping @Sendable (UUID) throws -> String?,
        write: @escaping @Sendable (String?, UUID) throws -> Void
    ) {
        self.read = read
        self.write = write
    }

    func headers(for connection: AIConnection) throws -> [String: String] {
        let names = connection.headerNames ?? []
        guard !names.isEmpty else { return [:] }
        guard let encoded = try read(connection.id) else { throw StoreError.unavailable }
        do {
            let stored = try JSONDecoder().decode(StoredHeaders.self, from: Data(encoded.utf8))
            guard stored.provider == connection.provider,
                stored.baseURL == connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                Set(stored.values.keys.map { $0.lowercased() }) == Set(names.map { $0.lowercased() })
            else { throw StoreError.unavailable }
            return try AIRequestHeaders.validated(
                stored.values.map { AIRequestHeaders.Entry(name: $0.key, value: $0.value) })
        } catch {
            throw StoreError.unavailable
        }
    }

    func save(
        _ headers: [String: String], for connection: AIConnection,
        updatingKey: () throws -> Void
    ) throws {
        let values = try AIRequestHeaders.validated(
            headers.map { AIRequestHeaders.Entry(name: $0.key, value: $0.value) })
        let encoded: String?
        if values.isEmpty {
            encoded = nil
        } else {
            let stored = StoredHeaders(
                provider: connection.provider,
                baseURL: connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                values: values)
            let data = try JSONEncoder().encode(stored)
            encoded = String(decoding: data, as: UTF8.self)
        }
        try replace(encoded, for: connection.id, updatingKey: updatingKey)
    }

    func remove(for id: UUID, updatingKey: () throws -> Void) throws {
        try replace(nil, for: id, updatingKey: updatingKey)
    }

    private func replace(
        _ encoded: String?, for id: UUID, updatingKey: () throws -> Void
    ) throws {
        let previous = try read(id)
        try write(encoded, id)
        do {
            try updatingKey()
        } catch {
            try write(previous, id)
            throw error
        }
    }
}
