import Foundation
import Security
import CryptoKit

public enum RemoteKey: String, CaseIterable, Sendable {
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT", enter = "KEY_ENTER", back = "KEY_RETURN", menu = "KEY_MENU", home = "KEY_HOME", source = "KEY_SOURCE"
    case hdmi1 = "KEY_HDMI1", hdmi2 = "KEY_HDMI2", displayPort = "KEY_DP"
    public var title: String {
        switch self { case .up: "Up"; case .down: "Down"; case .left: "Left"; case .right: "Right"; case .enter: "OK"; case .back: "Back"; case .menu: "Settings"; case .home: "Home"; case .source: "Sources"; case .hdmi1: "HDMI 1 request"; case .hdmi2: "HDMI 2 request"; case .displayPort: "DisplayPort request" }
    }
    public var payload: Data { try! JSONSerialization.data(withJSONObject: ["method": "ms.remote.control", "params": ["Cmd": "Click", "DataOfCmd": rawValue, "Option": "false", "TypeOfRemote": "SendRemoteKey"]]) }
}
public struct PairingReply {
    public let connected: Bool
    public let token: String?
    public init(_ data: Data) throws {
        guard data.count < 262144, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ArkError("Invalid monitor pairing response.") }
        let event = json["event"] as? String ?? ""
        if event == "ms.channel.unauthorized" || event == "ms.channel.timeOut" { throw ArkError("The monitor did not approve the connection. Select Allow on its screen, then try Pair again.") }
        connected = event == "ms.channel.connect"
        let value = (json["data"] as? [String: Any])?["token"]
        token = (value as? String) ?? (value as? NSNumber)?.stringValue
    }
}
public enum CertificatePin {
    public static func fingerprint(_ certificate: Data) -> String { SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined() }
    public static func matches(_ actual: String, _ approved: String?) -> Bool {
        guard let approved, approved.count == 64, approved.allSatisfy({ $0.isHexDigit }) else { return false }
        return actual == approved.lowercased()
    }
}
private final class MonitorTLS: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    let pin: String?
    let inspect: @Sendable (String) -> Void
    init(host: String, pin: String?, inspect: @escaping @Sendable (String) -> Void) { self.host = host; self.pin = pin; self.inspect = inspect }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust,
              let cert = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = cert.first else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let fingerprint = CertificatePin.fingerprint(SecCertificateCopyData(leaf) as Data)
        guard CertificatePin.matches(fingerprint, pin) else { inspect(fingerprint); completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
@MainActor public final class ArkRemote {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var watchdog: Task<Void, Never>?
    public private(set) var connected = false
    public private(set) var connecting = false
    public var onCertificate: ((String) -> Void)?
    private var generation = UUID()
    public var onChange: ((String, String?) -> Void)?
    public init() {}
    public func disconnect() {
        generation = UUID()
        watchdog?.cancel(); watchdog = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        session?.invalidateAndCancel(); session = nil; connected = false; connecting = false
    }
    public func connect(_ endpoint: Endpoint, token: String?, certificate: String?) {
        disconnect()
        var url = URLComponents(); url.scheme = "wss"; url.host = endpoint.host; url.port = 8002; url.path = "/api/v2/channels/samsung.remote.control"
        url.queryItems = [.init(name: "name", value: Data("NeroNook Ark".utf8).base64EncodedString())]
        if let token, !token.isEmpty { url.queryItems?.append(.init(name: "token", value: token)) }
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 40
        let attempt = generation
        let delegate = MonitorTLS(host: endpoint.host, pin: certificate) { [weak self] fingerprint in
            Task { @MainActor in guard let self, self.generation == attempt else { return }; self.onCertificate?(fingerprint) }
        }
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil); self.session = session
        let socket = session.webSocketTask(with: url.url!); socket.maximumMessageSize = 262144; task = socket; socket.resume(); connecting = true
        onChange?("Approve NeroNook Ark on the monitor…", nil)
        watchdog = Task { [weak self, weak socket] in
            try? await Task.sleep(for: .seconds(35))
            guard !Task.isCancelled, let self, let socket, self.task === socket, !self.connected else { return }
            self.disconnect(); self.onChange?("Pairing timed out. Try Pair again and select Allow on the monitor.", nil)
        }
        Task { [weak self, weak socket] in
            guard let socket else { return }
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.task === socket else { return }
                    let data: Data
                    switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                    let reply = try PairingReply(data)
                    if reply.connected { self.connected = true; self.connecting = false; self.watchdog?.cancel(); self.onChange?("Remote connected", reply.token) }
                }
            } catch {
                guard let self, self.task === socket else { return }
                self.task?.cancel(with: .goingAway, reason: nil); self.task = nil; self.connected = false; self.connecting = false; self.watchdog?.cancel(); self.session?.invalidateAndCancel(); self.session = nil; self.onChange?(error is ArkError ? error.localizedDescription : "Remote disconnected. Pair or reconnect to continue.", nil)
            }
        }
    }
    public func send(_ key: RemoteKey) async throws {
        guard connected, let task else { throw ArkError("Connect the monitor remote first.") }
        try await task.send(.string(String(decoding: key.payload, as: UTF8.self)))
        // The Samsung remote protocol has no per-key application acknowledgement.
    }
}
