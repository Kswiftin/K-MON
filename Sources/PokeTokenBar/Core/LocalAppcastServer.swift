import Foundation
import Network

/// Sparkle은 보안상 file:// appcast를 거부하므로, 메모리의 appcast를 loopback HTTP로만 제공한다.
/// 리스너가 127.0.0.1에만 bind되어 같은 네트워크의 다른 기기에는 노출되지 않는다.
@MainActor
final class LocalAppcastServer {
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var appcastData = Data()
    private var waiters: [CheckedContinuation<URL, Error>] = []
    private let queue = DispatchQueue(label: "io.github.chattymin.poketokenbar.appcast")

    func serve(_ data: Data) async throws -> URL {
        appcastData = data
        if let port { return Self.url(port: port) }
        if listener == nil { try start() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    private func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener?.port else {
                        self.fail(ServerError.noPort); return
                    }
                    self.port = port
                    let url = Self.url(port: port)
                    self.waiters.forEach { $0.resume(returning: url) }
                    self.waiters.removeAll()
                case let .failed(error): self.fail(error)
                case .cancelled: self.fail(ServerError.cancelled)
                default: break
                }
            }
        }
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        let data = appcastData
        let queue = queue
        connection.start(queue: queue)
        Self.receiveRequest(connection, buffer: Data(), appcast: data, queue: queue)
    }

    nonisolated private static func receiveRequest(_ connection: NWConnection, buffer: Data,
                                                    appcast: Data, queue: DispatchQueue) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            chunk, _, isComplete, error in
            var request = buffer
            if let chunk { request.append(chunk) }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete || error != nil {
                respond(connection, request: request, appcast: appcast)
            } else {
                receiveRequest(connection, buffer: request, appcast: appcast, queue: queue)
            }
        }
    }

    nonisolated private static func respond(_ connection: NWConnection, request: Data, appcast: Data) {
        let requestLine = String(data: request.prefix(512), encoding: .utf8) ?? ""
        let target = requestLine.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init)
        let isAppcastRequest = target == "/appcast.xml" || target?.hasPrefix("/appcast.xml?") == true
        let body = isAppcastRequest ? appcast : Data("Not Found".utf8)
        let status = isAppcastRequest ? "200 OK" : "404 Not Found"
        let type = isAppcastRequest ? "application/rss+xml; charset=utf-8" : "text/plain"
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    private func fail(_ error: Error) {
        listener?.cancel()
        listener = nil
        port = nil
        waiters.forEach { $0.resume(throwing: error) }
        waiters.removeAll()
    }

    nonisolated private static func url(port: NWEndpoint.Port) -> URL {
        URL(string: "http://127.0.0.1:\(port.rawValue)/appcast.xml")!
    }

    private enum ServerError: Error { case noPort, cancelled }
}
