import Foundation

/// One open live connection to a game. `receive()` returns the next text message and throws once the
/// connection drops (`OnlineLiveGameClosed` when the server ended it for good, `CancellationError` after
/// `close()`).
protocol OnlineLiveSocket: AnyObject, Sendable {
    func receive() async throws -> String
    /// Sends the keep-alive text "ping" (the server answers "pong" without waking the game).
    func sendPing() async throws
    func close()
}

extension OnlineLiveSocket {
    func sendPing() async throws {}
}

/// The server ended the live connection for good: it closed it with code 4004 (the game was deleted), or
/// refused to open it (401, 403 or 404: the session, the seat or the game is gone). Reconnecting can't
/// help, so the table fetches the game at once to find out which.
struct OnlineLiveGameClosed: Error, Equatable {
    static let closeCode = 4004
    static let refusedStatuses: Set<Int> = [401, 403, 404]
}

/// Opens live connections (URLSession WebSockets in the app, fakes in checks).
protocol OnlineLiveConnector: Sendable {
    func connect(to url: URL) -> OnlineLiveSocket
}

/// Keeps an open table up to date: a WebSocket while it works (with a keep-alive ping every 30 seconds,
/// so idle connections are not dropped, and a fresh connection when a ping goes unanswered); until it
/// works and while it is down, polls the game every 15 seconds and reconnects with growing pauses (1, 2,
/// 4, 8, 15, then every 30 seconds). When the server ends the connection for good (the game was deleted,
/// or the session expired), the game is fetched at once (the table then closes).
/// SwiftUI-free. Every update goes to `onState`; the model keeps only versions newer than its own.
@MainActor
final class OnlineLiveUpdates {
    enum Status: Equatable, Sendable {
        case stopped
        /// Opening the connection (nothing received yet).
        case connecting
        /// Updates arrive as they happen.
        case live
        /// The connection dropped; trying again (the table is polled meanwhile).
        case reconnecting(attempt: Int)
    }

    nonisolated static let backoff: [Double] = [1, 2, 4, 8, 15, 30]

    private(set) var status: Status = .stopped {
        didSet {
            if status != oldValue { onStatus?(status) }
        }
    }

    var onState: (@MainActor (OnlineGameState) -> Void)?
    var onStatus: (@MainActor (Status) -> Void)?
    /// Fetches the game (polling while the connection is down).
    var onPoll: (@MainActor () async -> Void)?

    private let connector: OnlineLiveConnector
    /// Seconds between polls while disconnected.
    let pollInterval: Double
    /// Multiplies every reconnect pause (0 in checks).
    let backoffScale: Double
    /// Seconds between keep-alive pings while connected (0: none).
    let pingInterval: Double

    private var url: URL?
    private var socket: OnlineLiveSocket?
    private var socketTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    /// When the open connection last brought a message (an update, or "pong" after a ping).
    private var lastHeard = Date()
    /// Bumped by start/stop; a loop from an older generation stops quietly.
    private var generation = 0

    init(connector: OnlineLiveConnector, pollInterval: Double = 15, backoffScale: Double = 1,
         pingInterval: Double = 30) {
        self.connector = connector
        self.pollInterval = pollInterval
        self.backoffScale = backoffScale
        self.pingInterval = pingInterval
    }

    var isRunning: Bool { socketTask != nil }

    /// Connects (or reconnects from scratch) to `url`.
    func start(url: URL) {
        stop()
        self.url = url
        generation += 1
        let current = generation
        status = .connecting
        // Poll until the first update arrives: a connection can hang before it opens.
        startPolling()
        socketTask = Task { [weak self] in
            await self?.run(url: url, generation: current)
        }
    }

    /// Closes the connection and stops polling.
    func stop() {
        generation += 1
        socketTask?.cancel()
        socketTask = nil
        pollTask?.cancel()
        pollTask = nil
        socket?.close()
        socket = nil
        status = .stopped
    }

    /// Back in the foreground: reconnect now unless updates are already flowing.
    func resume() {
        guard let url else { return }
        if status != .live || socketTask == nil { start(url: url) }
    }

    /// Decodes a server message; nil for messages that are not table updates.
    nonisolated static func decode(_ text: String) -> OnlineGameState? {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(OnlineLiveMessage.self, from: data) else { return nil }
        return message.state
    }

    nonisolated static func pause(forAttempt attempt: Int) -> Double {
        let index = min(max(attempt, 1), backoff.count) - 1
        return backoff[index]
    }

    // MARK: Private

    private func run(url: URL, generation current: Int) async {
        var attempt = 0
        while !Task.isCancelled && current == generation {
            let socket = connector.connect(to: url)
            self.socket = socket
            lastHeard = Date()
            let pinger = startPinging(socket)
            var gameClosed = false
            do {
                while !Task.isCancelled && current == generation {
                    let text = try await socket.receive()
                    guard current == generation else { break }
                    lastHeard = Date()
                    if status != .live {
                        attempt = 0
                        status = .live
                        stopPolling()
                    }
                    if let state = OnlineLiveUpdates.decode(text) {
                        onState?(state)
                    }
                }
            } catch is OnlineLiveGameClosed {
                gameClosed = true
            } catch {
                // Dropped (or closed by stop()); handled below.
            }
            pinger?.cancel()
            socket.close()
            if self.socket === socket { self.socket = nil }
            guard !Task.isCancelled, current == generation else { return }
            attempt += 1
            status = .reconnecting(attempt: attempt)
            if gameClosed {
                // Fetch now instead of reconnecting to a game that is gone (the fetch closes the table,
                // or signs you out when the session expired).
                await onPoll?()
                guard !Task.isCancelled, current == generation else { return }
            }
            startPolling()
            let pause = OnlineLiveUpdates.pause(forAttempt: attempt) * backoffScale
            if pause > 0 {
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            } else {
                await Task.yield()
            }
        }
    }

    /// Pings `socket` every `pingInterval` seconds until cancelled or the send fails. Nothing heard for two
    /// intervals (not even the "pong"): the connection is dead without knowing it (a phone that changed
    /// networks), so it is closed and the loop reconnects.
    private func startPinging(_ socket: OnlineLiveSocket) -> Task<Void, Never>? {
        guard pingInterval > 0 else { return nil }
        let interval = pingInterval
        return Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                if Date().timeIntervalSince(self.lastHeard) > interval * 2 {
                    socket.close()
                    return
                }
                do {
                    try await socket.sendPing()
                } catch {
                    return
                }
            }
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        let current = generation
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 0.01) * 1_000_000_000))
                guard !Task.isCancelled, let self, current == self.generation else { return }
                await self.onPoll?()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
