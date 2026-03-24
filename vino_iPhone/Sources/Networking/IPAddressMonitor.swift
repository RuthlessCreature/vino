import Foundation
import Combine

#if canImport(Darwin)
import Darwin
#endif

public struct IPAddressDescriptor: Identifiable, Hashable {
    public var interface: String
    public var address: String

    public var id: String { "\(interface):\(address)" }
    public var displayValue: String { "\(interface):\(address)" }

    public init(interface: String, address: String) {
        self.interface = interface
        self.address = address
    }
}

public final class IPAddressMonitor: ObservableObject {
    @Published public private(set) var addresses: [IPAddressDescriptor] = []

    private var timer: Timer?

    public init() {}

    public func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        let refreshed = Self.readAddresses()
        DispatchQueue.main.async {
            self.addresses = refreshed
        }
    }

    private static func readAddresses() -> [IPAddressDescriptor] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return []
        }

        defer {
            freeifaddrs(first)
        }

        var results: [IPAddressDescriptor] = []
        var current = first

        while true {
            let interface = current.pointee
            guard let addressPointer = interface.ifa_addr else {
                guard let next = interface.ifa_next else {
                    break
                }

                current = next
                continue
            }

            let family = addressPointer.pointee.sa_family

            if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                let flags = Int32(interface.ifa_flags)
                let isUp = (flags & IFF_UP) == IFF_UP
                let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

                if isUp, !isLoopback {
                    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let addressLength = socklen_t(interface.ifa_addr.pointee.sa_len)

                    getnameinfo(
                        addressPointer,
                        addressLength,
                        &hostBuffer,
                        socklen_t(hostBuffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )

                    let address = String(cString: hostBuffer)
                    if !address.isEmpty, !address.hasPrefix("fe80::") {
                        results.append(IPAddressDescriptor(interface: name, address: address))
                    }
                }
            }

            guard let next = interface.ifa_next else {
                break
            }

            current = next
        }

        return results.sorted { lhs, rhs in
            lhs.displayValue < rhs.displayValue
        }
    }
}
