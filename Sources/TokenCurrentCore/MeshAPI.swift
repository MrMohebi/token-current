import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MeshAPIError: Error, LocalizedError {
    case endpoint, rejected(Int), oversized, invalid
    public var errorDescription: String? {
        switch self {
        case .endpoint: "Use an HTTPS server origin. HTTP is allowed only for localhost or Tailscale IPs."
        case .rejected(let code): code == 401 ? "Pairing token rejected. Update the token and reconnect." : "Server rejected the request (\(code))."
        case .oversized: "Server response was too large."
        case .invalid: "Server returned an unsupported response."
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct MeshAPI: Sendable {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()
    public let origin: URL
    public let token: String
    public init(origin: String, token: String) throws {
        guard let u = Self.endpoint(origin), !token.isEmpty else { throw MeshAPIError.endpoint }
        self.origin = u; self.token = token
    }
    public static func endpoint(_ raw: String) -> URL? {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host?.lowercased(), !host.isEmpty, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/" else { return nil }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let v4 = parts.count == 4 ? parts.compactMap { UInt8($0) } : []
        let tailnet = v4.count == 4 && v4[0] == 100 && (64...127).contains(v4[1])
        let loopback = host == "localhost" || host == "[::1]" || host == "::1" || (v4.count == 4 && v4[0] == 127)
        let v6 = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).hasPrefix("fd7a:115c:a1e0:")
        guard c.scheme == "https" || (c.scheme == "http" && (loopback || tailnet || v6)) else { return nil }
        return c.url
    }
    public func mesh() async throws -> NetworkMesh { try await decode("GET", "/api/v1/mesh") }
    public func enroll(name: String, platform: String) async throws -> NetworkEnrollment {
        try await decode("POST", "/api/v1/instances", body: JSONEncoder().encode(["name": name, "platform": platform]))
    }
    public func rotate(id: String) async throws -> NetworkEnrollment {
        try await decode("POST", "/api/v1/instances/\(safe(id))/rotate")
    }
    public func remove(id: String) async throws { _ = try await request("DELETE", "/api/v1/instances/\(safe(id))") }
    public func publish(_ sample: NetworkSnapshot) async throws { _ = try await request("POST", "/api/v1/report", body: JSONEncoder().encode(sample)) }
    private func safe(_ id: String) -> String { id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "invalid" }
    private func decode<T: Decodable>(_ method: String, _ path: String, body: Data? = nil) async throws -> T {
        let data = try await request(method, path, body: body)
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw MeshAPIError.invalid }
    }
    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: origin.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method; request.timeoutInterval = 3
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        #if os(macOS)
        let (bytes, response) = try await Self.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw MeshAPIError.invalid }
        guard (200..<300).contains(http.statusCode) else { throw MeshAPIError.rejected(http.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw MeshAPIError.oversized }
            data.append(byte)
        }
        return data
        #else
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MeshAPIError.invalid }
        guard (200..<300).contains(http.statusCode) else { throw MeshAPIError.rejected(http.statusCode) }
        guard data.count <= 1_048_576 else { throw MeshAPIError.oversized }
        return data
        #endif
    }
}
