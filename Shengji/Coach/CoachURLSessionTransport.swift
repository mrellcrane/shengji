import Foundation

/// Sends coach requests with URLSession and streams the reply line by line (`URLSession.bytes(for:)`).
/// Network failures and timeouts become `CoachClientError.offline`; cancelling the task cancels the request.
/// (Kept tiny and separate: `URLSession.bytes` doesn't exist on Linux, where the rest is checked.)
struct URLSessionCoachTransport: CoachTransport {
    var session: URLSession = .shared

    func send(_ request: CoachHTTPRequest) async throws -> CoachHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        let result: (URLSession.AsyncBytes, URLResponse)
        do {
            result = try await session.bytes(for: urlRequest)
        } catch {
            throw Self.map(error)
        }
        let bytes = result.0
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0

        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return CoachHTTPResponse(statusCode: status, lines: lines)
    }

    private static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let urlError = error as? URLError, urlError.code == .cancelled { return CancellationError() }
        return CoachClientError.offline
    }
}
