import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> Data
}
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct LocalHTTP: HTTPTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw ArkError("The monitor did not accept the HTTP request.") }
        var data = Data()
        for try await byte in bytes { guard data.count < 262144 else { throw ArkError("The monitor response exceeded its size limit.") }; data.append(byte) }
        return data
    }
}
public struct AudioState: Sendable {
    public let volume: Int?
    public let muted: Bool?
    public init(volume: Int?, muted: Bool?) { self.volume = volume; self.muted = muted }
}
public struct ArkClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = LocalHTTP()) { self.transport = transport }
    public func info(_ endpoint: Endpoint, expectedID: String? = nil) async throws -> DeviceInfo {
        let data = try await transport.send(URLRequest(url: endpoint.url(port: 8001, path: "/api/v2/")))
        let value = try JSONDecoder().decode(DeviceInfo.self, from: data); try value.verify(expectedID: expectedID); return value
    }
    public func service(_ endpoint: Endpoint) async throws -> RenderingService {
        // Samsung advertises this descriptor on the discovered Ark. Only same-host relative service paths are accepted.
        let data = try await transport.send(URLRequest(url: endpoint.url(port: 9197, path: "/dmr")))
        let service = try SOAP.renderingService(data, host: endpoint.host, port: 9197)
        let scpd = try await transport.send(URLRequest(url: endpoint.url(port: service.port, path: service.descriptionPath)))
        return service.withActions(try SOAP.actions(scpd))
    }
    private func soap(_ endpoint: Endpoint, _ service: RenderingService, action: String, value: Int? = nil) async throws -> Data {
        guard service.actions.contains(action) else { throw ArkError("This monitor does not advertise that control.") }
        var request = URLRequest(url: try endpoint.url(port: service.port, path: service.controlPath))
        request.httpMethod = "POST"; request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(SOAP.service)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = try SOAP.body(action, value: value)
        return try await transport.send(request)
    }
    public func audio(_ endpoint: Endpoint, service: RenderingService) async throws -> AudioState {
        var volume: Int?, muted: Bool?
        if service.actions.contains("GetVolume") { volume = try SOAP.reading(await soap(endpoint, service, action: "GetVolume"), action: "GetVolume") }
        if service.actions.contains("GetMute") { muted = try SOAP.reading(await soap(endpoint, service, action: "GetMute"), action: "GetMute") == 1 }
        return .init(volume: volume, muted: muted)
    }
    public func set(_ endpoint: Endpoint, id: String, service: RenderingService, volume: Int? = nil, muted: Bool? = nil) async throws -> AudioState {
        guard (volume != nil) != (muted != nil), volume.map({ (0...100).contains($0) }) ?? true else { throw ArkError("Choose one valid audio setting.") }
        _ = try await info(endpoint, expectedID: id)
        let action = volume != nil ? "SetVolume" : "SetMute"
        let readAction = volume != nil ? "GetVolume" : "GetMute"
        guard service.actions.contains(action), service.actions.contains(readAction) else { throw ArkError("This control cannot be verified on the monitor.") }
        _ = try await audio(endpoint, service: service)
        do {
            let response = try await soap(endpoint, service, action: action, value: volume ?? (muted! ? 1 : 0))
            guard try XMLTree(response).nodes(named: "Fault").isEmpty else { throw ArkError("The monitor rejected the setting.") }
            let after = try await audio(endpoint, service: service)
            guard volume == nil || after.volume == volume, muted == nil || after.muted == muted else { throw ArkError("The setting did not match its read-back.") }
            return after
        } catch { throw ArkError("Could not confirm the change. It may have applied; refresh before trying again. No retry was sent.") }
    }
}
