import Foundation


public struct ArkError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct DeviceInfo: Decodable, Sendable {
    public let device: Device
    public let id: String
    public struct Device: Decodable, Sendable {
        public let name: String
        public let modelName: String
        public let resolution: String?
        public let PowerState: String?
    }
    public var name: String { device.name.replacingOccurrences(of: "&quot;", with: "\"") }
    public func verify(expectedID: String? = nil) throws {
        guard device.modelName.uppercased().hasPrefix("LS55"), device.modelName.uppercased().contains("G97"), !id.isEmpty else { throw ArkError("This address did not identify a supported Odyssey Ark monitor.") }
        if let expectedID, id != expectedID { throw ArkError("The monitor at this address has changed. Connect and review it again.") }
    }
}
public struct Endpoint: Equatable, Sendable {
    public let host: String
    public init(_ raw: String) throws {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0).map { (0...255).contains($0) } == true }) else { throw ArkError("Enter the monitor's local IPv4 address, such as 192.168.1.153.") }
        let b = parts.map { Int($0)! }
        guard b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168), b[3] != 0, b[3] != 255 else { throw ArkError("Use a private local-network address for the monitor.") }
        host = b.map(String.init).joined(separator: ".")
    }
    public func url(port: Int, path: String) throws -> URL {
        guard (1...65535).contains(port), path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("#"), !path.contains("?") else { throw ArkError("Invalid monitor endpoint.") }
        var c = URLComponents(); c.scheme = "http"; c.host = host; c.port = port; c.path = path
        guard let url = c.url else { throw ArkError("Invalid monitor endpoint.") }; return url
    }
}
public struct RenderingService: Sendable {
    public let port: Int
    public let controlPath: String
    public let descriptionPath: String
    public let actions: Set<String>
    public init(port: Int, controlPath: String, descriptionPath: String, actions: Set<String> = []) { self.port = port; self.controlPath = controlPath; self.descriptionPath = descriptionPath; self.actions = actions }
    public func withActions(_ actions: Set<String>) -> Self { .init(port: port, controlPath: controlPath, descriptionPath: descriptionPath, actions: actions) }
}
public enum SOAP {
    public static let service = "urn:schemas-upnp-org:service:RenderingControl:1"
    public static func body(_ action: String, value: Int? = nil) throws -> Data {
        guard ["GetVolume", "GetMute", "SetVolume", "SetMute"].contains(action) else { throw ArkError("Unsupported monitor command.") }
        var args = "<InstanceID>0</InstanceID><Channel>Master</Channel>"
        if action.hasPrefix("Set") {
            guard let value, (action == "SetVolume" ? (0...100).contains(value) : (0...1).contains(value)) else { throw ArkError("Invalid monitor setting.") }
            args += "<Desired\(action == "SetVolume" ? "Volume" : "Mute")>\(value)</Desired\(action == "SetVolume" ? "Volume" : "Mute")>"
        } else if value != nil { throw ArkError("Read requests cannot include a setting.") }
        return Data("<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:\(action) xmlns:u=\"\(service)\">\(args)</u:\(action)></s:Body></s:Envelope>".utf8)
    }
    public static func reading(_ data: Data, action: String) throws -> Int {
        let xml = try XMLTree(data)
        guard xml.nodes(named: "Fault").isEmpty else { throw ArkError("The monitor rejected this command.") }
        let field: String
        let range: ClosedRange<Int>
        switch action { case "GetVolume": field = "CurrentVolume"; range = 0...100
        case "GetMute": field = "CurrentMute"; range = 0...1
        default: throw ArkError("Unsupported reading.") }
        let nodes = xml.nodes(named: field)
        guard nodes.count == 1, let value = Int(nodes[0].text), range.contains(value) else { throw ArkError("The monitor returned an invalid reading.") }
        return value
    }
    public static func actions(_ data: Data) throws -> Set<String> {
        Set(try XMLTree(data).nodes(named: "action").compactMap { $0.children.first(where: { $0.name == "name" })?.text })
    }
    public static func renderingService(_ data: Data, host: String, port: Int) throws -> RenderingService {
        let xml = try XMLTree(data)
        guard xml.nodes(named: "manufacturer").contains(where: { $0.text.contains("Samsung") }) else { throw ArkError("The service is not a Samsung monitor.") }
        guard let node = xml.nodes(named: "service").first(where: { $0.children.contains { $0.name == "serviceType" && $0.text == service } }),
              let control = node.children.first(where: { $0.name == "controlURL" })?.text,
              let description = node.children.first(where: { $0.name == "SCPDURL" })?.text else { throw ArkError("The monitor does not advertise audio control.") }
        let endpoint = try Endpoint(host)
        _ = try endpoint.url(port: port, path: control); _ = try endpoint.url(port: port, path: description)
        return .init(port: port, controlPath: control, descriptionPath: description)
    }
}
public final class XMLNode {
    public let name: String
    public var text = ""
    public var children: [XMLNode] = []
    init(_ name: String) { self.name = name }
}
public final class XMLTree: NSObject, XMLParserDelegate {
    private var roots: [XMLNode] = [], stack: [XMLNode] = []
    public init(_ data: Data) throws {
        super.init()
        guard data.count <= 262144, !String(decoding: data, as: UTF8.self).uppercased().contains("<!DOCTYPE") else { throw ArkError("Invalid monitor XML.") }
        let parser = XMLParser(data: data); parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = self
        guard parser.parse() else { throw ArkError("The monitor returned malformed XML.") }
    }
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String : String]) {
        guard stack.count < 32 else { parser.abortParsing(); return }
        let node = XMLNode(elementName); if let parent = stack.last { parent.children.append(node) } else { roots.append(node) }; stack.append(node)
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { stack.last?.text = stack.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; _ = stack.popLast() }
    public func nodes(named name: String) -> [XMLNode] {
        func walk(_ node: XMLNode) -> [XMLNode] { (node.name == name ? [node] : []) + node.children.flatMap(walk) }
        return roots.flatMap(walk)
    }
}
