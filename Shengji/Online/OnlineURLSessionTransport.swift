import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends online requests with URLSession. Network failures and timeouts throw (the API turns them into
/// `OnlineError.offline`); cancelling the calling task cancels the request.
struct URLSessionOnlineTransport: OnlineTransport {
    var session: URLSession = .shared

    func send(_ request: OnlineHTTPRequest) async throws -> OnlineHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return OnlineHTTPResponse(statusCode: status, body: data)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }
}

/// One live connection: `URLSessionWebSocketTask` reading text frames.
final class URLSessionOnlineLiveSocket: OnlineLiveSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
        task.resume()
    }

    func receive() async throws -> String {
        do {
            switch try await task.receive() {
            case let .string(text):
                return text
            case let .data(data):
                return String(decoding: data, as: UTF8.self)
            @unknown default:
                return ""
            }
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            // The server closes with 4004 when the game is deleted, and refuses to open the connection
            // when the session or the game is gone.
            if task.closeCode.rawValue == OnlineLiveGameClosed.closeCode { throw OnlineLiveGameClosed() }
            if let status = (task.response as? HTTPURLResponse)?.statusCode,
               OnlineLiveGameClosed.refusedStatuses.contains(status) {
                throw OnlineLiveGameClosed()
            }
            throw error
        }
    }

    func sendPing() async throws {
        try await task.send(.string("ping"))
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

/// Opens real WebSocket connections.
struct URLSessionOnlineLiveConnector: OnlineLiveConnector {
    func connect(to url: URL) -> OnlineLiveSocket {
        URLSessionOnlineLiveSocket(url: url)
    }
}
