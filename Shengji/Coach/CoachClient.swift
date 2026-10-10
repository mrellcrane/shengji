import Foundation

// The coach server's wire protocol (see proxy/src/protocol.ts and proxy/src/handler.ts) and a client
// that streams one reply. SwiftUI-free and free of URLSession types, so it can be checked on Linux;
// the network call itself lives in `CoachURLSessionTransport.swift`.

/// Limits the server enforces (`LIMITS` in proxy/src/protocol.ts). Lengths are UTF-16 code units,
/// like JavaScript's `String.length`.
enum CoachLimits {
    static let maxBodyBytes = 64_000
    static let maxTurns = 24
    static let maxUserChars = 1_500
    static let maxAssistantChars = 4_000
    static let maxContextChars = 6_000
    static let maxTotalChars = 48_000
    /// What the app aims for, leaving room for JSON quoting and escapes.
    static let targetBodyBytes = 56_000
    static let targetTotalChars = 44_000
}

/// One turn of a request: `{"role", "text", "context"?}`.
struct CoachTurn: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant
    }

    var role: Role
    var text: String
    /// The table state the user turn was asked with (user turns only).
    var context: String?

    init(role: Role, text: String, context: String? = nil) {
        self.role = role
        self.text = text
        self.context = context
    }

    /// Characters the server counts for this turn (text plus context).
    var countedChars: Int { text.utf16.count + (context?.utf16.count ?? 0) }
}

/// The request body for `POST /coach`.
struct CoachRequestBody: Encodable, Sendable {
    var deviceId: String
    var turns: [CoachTurn]
}

/// One server-sent event (one JSON object per `data:` line).
enum CoachStreamEvent: Equatable, Sendable {
    case text(String)
    case done(stopReason: String)
    case error(code: String, message: String)
}

/// Learner-facing failures. `message` is ready to show.
enum CoachClientError: Error, Equatable, Sendable {
    /// No connection, a timeout, or a dropped stream.
    case offline
    /// The server said no (rate limit, bad request, upstream trouble) with this message.
    case server(status: Int, code: String, message: String)

    static let offlineMessage = "The coach can't be reached right now. Check your connection and try again."
    static let rateLimitedMessage = "You're asking faster than the coach can keep up. Wait a minute and try again."
    static let unavailableMessage = "The coach is unavailable right now. Try again in a minute."

    var message: String {
        switch self {
        case .offline: return CoachClientError.offlineMessage
        case let .server(_, _, message): return message
        }
    }
}

/// Reads the server's SSE lines. Only `data:` lines carry events; comments (`: coach`) and blank
/// lines are ignored, as are events of unknown types.
enum CoachSSEParser {
    private struct Payload: Decodable {
        var type: String
        var text: String?
        var stopReason: String?
        var code: String?
        var message: String?
    }

    static func event(fromLine rawLine: String) -> CoachStreamEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        guard line.hasPrefix("data:") else { return nil }
        var payload = line.dropFirst("data:".count)
        if payload.first == " " { payload = payload.dropFirst() }
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        switch decoded.type {
        case "text":
            guard let text = decoded.text else { return nil }
            return .text(text)
        case "done":
            return .done(stopReason: decoded.stopReason ?? "end_turn")
        case "error":
            return .error(code: decoded.code ?? "error",
                          message: decoded.message ?? CoachClientError.unavailableMessage)
        default:
            return nil
        }
    }

    /// The learner-facing message for a non-200 reply (`{"error", "message"}` JSON, if readable).
    static func errorMessage(status: Int, body: String) -> CoachClientError {
        struct ErrorBody: Decodable {
            var error: String?
            var message: String?
        }
        let decoded = body.data(using: .utf8).flatMap { try? JSONDecoder().decode(ErrorBody.self, from: $0) }
        let code = decoded?.error ?? (status == 429 ? "rate_limited" : "http_\(status)")
        let serverMessage = decoded?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = status == 429 ? CoachClientError.rateLimitedMessage : CoachClientError.unavailableMessage
        let message = (serverMessage?.isEmpty == false ? serverMessage : nil) ?? fallback
        return .server(status: status, code: code, message: message)
    }
}

/// A request in plain values (the transport turns it into a `URLRequest`).
struct CoachHTTPRequest: Equatable, Sendable {
    var url: URL
    var body: Data
    var headers: [String: String]
    /// Seconds to wait for the next bytes before giving up.
    var timeout: TimeInterval
}

/// The status code and the body as lines (SSE for 200, JSON otherwise).
struct CoachHTTPResponse: Sendable {
    var statusCode: Int
    var lines: AsyncThrowingStream<String, Error>
}

/// Sends a request and streams the reply's lines. Throws `CoachClientError.offline` for network
/// failures and `CancellationError` when cancelled.
protocol CoachTransport: Sendable {
    func send(_ request: CoachHTTPRequest) async throws -> CoachHTTPResponse
}

/// A random install id used only for rate limiting, kept in UserDefaults ("coach.deviceID").
enum CoachDeviceID {
    static let key = "coach.deviceID"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: key), isValid(saved) { return saved }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }

    /// The server accepts 8 to 64 letters, digits or dashes.
    static func isValid(_ id: String) -> Bool {
        (8...64).contains(id.count) && id.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }
    }
}

/// Streams one coach reply for a conversation.
struct CoachClient: Sendable {
    static let endpointString = "https://shengji-coach.ellcrane.workers.dev/coach"

    var endpoint: URL
    var deviceID: String
    var transport: CoachTransport

    init(endpoint: URL, deviceID: String, transport: CoachTransport) {
        self.endpoint = endpoint
        self.deviceID = deviceID
        self.transport = transport
    }

    /// The live coach (nil only if the endpoint string were malformed).
    static func standard() -> CoachClient? {
        guard let url = URL(string: endpointString) else { return nil }
        return CoachClient(endpoint: url, deviceID: CoachDeviceID.current(), transport: URLSessionCoachTransport())
    }

    func makeRequest(turns: [CoachTurn]) throws -> CoachHTTPRequest {
        let body = try JSONEncoder().encode(CoachRequestBody(deviceId: deviceID, turns: turns))
        return CoachHTTPRequest(url: endpoint, body: body,
                                headers: ["Content-Type": "application/json", "Accept": "text/event-stream"],
                                timeout: 30)
    }

    /// The reply as events, ending after `done` or `error`. Throws `CoachClientError` (with a
    /// learner-facing message) or `CancellationError`. Cancelling the consuming task cancels the request.
    func stream(turns: [CoachTurn]) -> AsyncThrowingStream<CoachStreamEvent, Error> {
        let transport = self.transport
        let request: CoachHTTPRequest
        do {
            request = try makeRequest(turns: turns)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: CoachClientError.server(status: 0, code: "encoding",
                                                                                       message: CoachClientError.unavailableMessage)) }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await transport.send(request)
                    guard response.statusCode == 200 else {
                        var body = ""
                        for try await line in response.lines {
                            body += line
                            if body.utf8.count > 16_000 { break }
                        }
                        throw CoachSSEParser.errorMessage(status: response.statusCode, body: body)
                    }
                    for try await line in response.lines {
                        guard let event = CoachSSEParser.event(fromLine: line) else { continue }
                        continuation.yield(event)
                        switch event {
                        case .text: continue
                        case .done, .error:
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CoachClient.normalize(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Keeps cancellation and learner-facing errors; anything else counts as "can't be reached".
    static func normalize(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let coachError = error as? CoachClientError { return coachError }
        return CoachClientError.offline
    }
}
