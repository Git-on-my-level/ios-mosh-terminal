import Foundation
import Darwin

enum HostAddressResolver {
    private enum IPAddressFamily {
        case ipv4
        case ipv6
        case unknown
    }

    static func fallbackAddress(hostname: String, preferredHostname: String?) -> String? {
        let currentFamily = addressFamily(for: hostname)
        let sourceHostname: String? = {
            if let preferredHostname, !preferredHostname.isEmpty, preferredHostname != hostname {
                return preferredHostname
            }
            if currentFamily == .unknown {
                return hostname
            }
            return nil
        }()

        guard let sourceHostname else { return nil }
        let addresses = resolve(hostname: sourceHostname)
        guard !addresses.isEmpty else { return nil }

        if currentFamily == .unknown {
            guard let primary = addresses.first else { return nil }
            let targetFamily: IPAddressFamily = (primary.family == .ipv6) ? .ipv4 : .ipv6
            return addresses.first { $0.family == targetFamily }?.address
        }

        return addresses.first { $0.family != currentFamily }?.address
    }

    private struct ResolvedAddress {
        let address: String
        let family: IPAddressFamily
    }

    private static func addressFamily(for address: String) -> IPAddressFamily {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 {
            return .ipv4
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, address, &ipv6) == 1 {
            return .ipv6
        }
        return .unknown
    }

    private static func resolve(hostname: String) -> [ResolvedAddress] {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP
        hints.ai_family = AF_UNSPEC
        hints.ai_flags = 0

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &result) == 0, let head = result else {
            return []
        }
        defer { freeaddrinfo(head) }

        var addresses: [ResolvedAddress] = []
        var current: UnsafeMutablePointer<addrinfo>? = head
        while let node = current {
            let ai = node.pointee
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let infoResult = getnameinfo(
                ai.ai_addr,
                ai.ai_addrlen,
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if infoResult == 0 {
                let address = String(cString: hostBuffer)
                let family: IPAddressFamily = (ai.ai_family == AF_INET) ? .ipv4 : .ipv6
                addresses.append(ResolvedAddress(address: address, family: family))
            }
            current = ai.ai_next
        }

        return addresses
    }
}
