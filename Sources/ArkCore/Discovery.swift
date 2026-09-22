import Foundation
import Darwin

public enum Discovery {
    public static func samsungHosts() async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard socketFD >= 0 else { continuation.resume(returning: []); return }
                defer { close(socketFD) }
                var timeout = timeval(tv_sec: 0, tv_usec: 500000)
                setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
                var dest = sockaddr_in(); dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); dest.sin_family = sa_family_t(AF_INET); dest.sin_port = UInt16(1900).bigEndian
                inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr)
                let query = Array("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n".utf8)
                query.withUnsafeBytes { bytes in withUnsafePointer(to: &dest) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = sendto(socketFD, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } }
                let end = Date().addingTimeInterval(4); var hosts = Set<String>(); var buffer = [UInt8](repeating: 0, count: 8192)
                while Date() < end && hosts.count < 16 {
                    var from = sockaddr_in(), length = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let count = withUnsafeMutablePointer(to: &from) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(socketFD, &buffer, buffer.count, 0, $0, &length) } }
                    guard count > 0, String(decoding: buffer.prefix(count), as: UTF8.self).localizedCaseInsensitiveContains("samsung") else { continue }
                    var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN)); inet_ntop(AF_INET, &from.sin_addr, &text, socklen_t(text.count))
                    if let host = try? Endpoint(String(cString: text)).host { hosts.insert(host) }
                }
                continuation.resume(returning: hosts.sorted())
            }
        }
    }
}
