import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Refuses HTTP redirects so bearer credentials cannot be forwarded to another target.
private final class SnapNoteRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public final class SnapNoteLocalTransport: SnapNoteHTTPTransport, @unchecked Sendable {
    public static let defaultEndpointString = "http://127.0.0.1:31090/snapnote/data-source/mcp"
    public static let defaultPort: Int = 31090
    public static let defaultMCPPath = "/snapnote/data-source/mcp"
    public static let endpoint = URL(string: defaultEndpointString)!

    public let endpointURL: URL
    private let session: URLSession

    public init(endpoint: URL = SnapNoteLocalTransport.endpoint) {
        self.endpointURL = endpoint
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config, delegate: SnapNoteRedirectBlocker(), delegateQueue: nil)
    }

    public convenience init(endpointString: String) throws {
        let normalized = try Self.normalizeEndpoint(endpointString)
        self.init(endpoint: normalized)
    }

    public static func normalizeEndpoint(_ raw: String, fallbackPort: Int? = nil) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              var components = URLComponents(string: trimmed) else {
            throw SnapNoteError.invalidEndpoint
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw SnapNoteError.invalidEndpoint
        }
        components.scheme = scheme

        guard let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw SnapNoteError.invalidEndpoint
        }

        if let port = components.port {
            guard (1...65535).contains(port) else {
                throw SnapNoteError.invalidEndpoint
            }
        } else {
            // Ensure no invalid ":nonNumericOrOutOfRangePort" was silently dropped by URLComponents
            if let schemeRange = trimmed.range(of: "://") {
                let afterScheme = trimmed[schemeRange.upperBound...]
                let authority = afterScheme.prefix { $0 != "/" }
                if authority.contains(":") && !authority.hasSuffix("]") {
                    throw SnapNoteError.invalidEndpoint
                }
            }
            if let fallbackPort {
                guard (1...65535).contains(fallbackPort) else {
                    throw SnapNoteError.invalidEndpoint
                }
                components.port = fallbackPort
            }
        }

        let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty || path == "/" {
            components.path = defaultMCPPath
        } else if path.count > 1 && path.hasSuffix("/") {
            components.path = String(path.dropLast())
        }

        guard let url = components.url else {
            throw SnapNoteError.invalidEndpoint
        }
        return url
    }

    public static func validEndpoint(_ raw: String) -> Bool {
        (try? normalizeEndpoint(raw)) != nil
    }

    public static func extractPort(from rawEndpoint: String) -> Int? {
        guard let url = try? normalizeEndpoint(rawEndpoint),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.port
    }

    public static func replacingPort(in rawEndpoint: String, with newPort: Int) -> String? {
        guard (1...65535).contains(newPort) else { return nil }
        let baseURL = (try? normalizeEndpoint(rawEndpoint)) ?? endpoint
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.port = newPort
        if components.path.isEmpty || components.path == "/" {
            components.path = defaultMCPPath
        }
        return components.url?.absoluteString
    }

    public func post(body: Data, headers: [String: String], timeout: TimeInterval) async throws -> SnapNoteHTTPResponse {
        var request = URLRequest(url: endpointURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"; request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SnapNoteError.protocolError }
            guard data.count <= 5_000_000 else { throw SnapNoteError.protocolError }
            var values: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String { values[key] = value }
            }
            return SnapNoteHTTPResponse(statusCode: http.statusCode, headers: values, data: data)
        } catch is CancellationError { throw SnapNoteError.cancelled }
        catch let error as SnapNoteError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw SnapNoteError.cancelled }
            if error.code == .timedOut { throw SnapNoteError.timeout }
            throw SnapNoteError.unavailable
        } catch { throw SnapNoteError.unavailable }
    }
}
