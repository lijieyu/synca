import Foundation

struct SyncServerState: Codable, Equatable, Sendable {
    let messages: String
    let categories: String
    let access: String
    let latestMessage: String?
    let count: Int

    static func overlap(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) else { return value }
        return formatter.string(from: date.addingTimeInterval(-1))
    }
}

private final class SyncStreamDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil) // Authenticated streams never follow redirects.
    }
}

@MainActor
final class SyncNotifications {
    private let request: URLRequest
    private let onChange: @MainActor () async -> Bool
    private let connectEnabled: Bool
    private let retrySeconds: Double
    private var streamTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var session: URLSession?
    private var active = false
    private var dirty = false

    init(request: URLRequest, connect: Bool = true, retrySeconds: Double = 1,
         onChange: @escaping @MainActor () async -> Bool) {
        self.request = request; self.connectEnabled = connect
        self.retrySeconds = retrySeconds; self.onChange = onChange
    }
    func start() {
        guard !active else { return }
        active = true; hint()
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                self?.hint()
            }
        }
        if connectEnabled { streamTask = Task { [weak self] in await self?.listen() } }
    }
    func stop() {
        active = false; dirty = false
        streamTask?.cancel(); checkTask?.cancel(); workTask?.cancel()
        streamTask = nil; checkTask = nil; workTask = nil
        session?.invalidateAndCancel(); session = nil
    }
    func hint() {
        guard active else { return }
        dirty = true
        guard workTask == nil else { return }
        workTask = Task { [weak self] in
            guard let self else { return }
            var delay = retrySeconds
            while active && !Task.isCancelled && dirty {
                dirty = false
                let ok = await onChange()
                guard active && !Task.isCancelled else { return }
                if !ok {
                    dirty = true
                    do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
                    delay = min(delay * 2, 60)
                } else { delay = retrySeconds }
            }
            workTask = nil
        }
    }
    private func listen() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 65
        configuration.timeoutIntervalForResource = 3600
        let connection = URLSession(configuration: configuration, delegate: SyncStreamDelegate(), delegateQueue: nil)
        session = connection
        var delay = retrySeconds
        while active && !Task.isCancelled {
            do {
                let (bytes, response) = try await connection.bytes(for: request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if response.statusCode == 401 || response.statusCode == 403 { hint(); return }
                guard response.statusCode == 200,
                      response.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else { throw URLError(.badServerResponse) }
                for try await line in bytes.lines {
                    guard active && !Task.isCancelled else { return }
                    if line == "event: change" { hint() }
                    if line == ": heartbeat" { delay = retrySeconds }
                    if line.utf8.count > 16384 { throw URLError(.badServerResponse) }
                }
            } catch { if Task.isCancelled || !active { return } }
            do { try await Task.sleep(nanoseconds: UInt64((delay + Double.random(in: 0...min(delay / 4, 1))) * 1_000_000_000)) } catch { return }
            delay = min(delay * 2, 60)
        }
    }
}
