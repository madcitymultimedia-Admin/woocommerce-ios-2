import Foundation

/// Mapper: Single Entity ID
///
struct EntityIDMapper: Mapper {

    /// (Attempts) to convert an instance of Data into an into an ID
    ///
    func map(response: Data) throws -> Int64 {
        let decoder = JSONDecoder()

        return try decoder.decode(EntityIDEnvelope.self, from: response).id
    }
}

/// Disposable Entity:
/// Allows us to parse a product ID with JSONDecoder.
///
private struct EntityIDEnvelope: Decodable {
    private let data: [String: Int64]

    // Extracts the entity ID from the underlying data
    var id: Int64 {
        data["id"] ?? .zero
    }

    private enum CodingKeys: String, CodingKey {
        case data = "data"
    }
}
