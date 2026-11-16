import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Enforces the fixed loopback endpoint; redirects are refused so bearer credentials cannot be forwarded.
private final class SnapNoteRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public final class SnapNoteLocalTransport: SnapNoteHTTPTransport, @unchecked Sendable {
    public static let endpoint = URL(string: "http://127.0.0.1:31090/snapnote/data-source/mcp")!
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config, delegate: SnapNoteRedirectBlocker(), delegateQueue: nil)
    }

    public func post(body: Data, headers: [String: String], timeout: TimeInterval) async throws -> SnapNoteHTTPResponse {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
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
