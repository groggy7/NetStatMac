import Darwin
import Foundation

public enum InterfaceMode: String, CaseIterable, Sendable {
    case builtIn = "builtIn"
    case allActive = "allActive"

    public var title: String {
        switch self {
        case .builtIn:
            return "Built-in Wi-Fi/Ethernet"
        case .allActive:
            return "All Active Interfaces"
        }
    }
}

public struct NetworkRate: Equatable, Sendable {
    public let downBytesPerSecond: Double
    public let upBytesPerSecond: Double

    public static let zero = NetworkRate(downBytesPerSecond: 0, upBytesPerSecond: 0)

    public init(downBytesPerSecond: Double, upBytesPerSecond: Double) {
        self.downBytesPerSecond = downBytesPerSecond
        self.upBytesPerSecond = upBytesPerSecond
    }
}

struct NetworkSnapshot: Sendable {
    let countersByInterface: [String: NetworkInterfaceCounters]
    let timestamp: TimeInterval
}

struct NetworkInterfaceCounters: Sendable {
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

public final class NetworkSampler {
    typealias SnapshotProvider = (InterfaceMode) -> NetworkSnapshot?

    private let snapshotProvider: SnapshotProvider
    private var previousSnapshot: NetworkSnapshot?

    public init() {
        snapshotProvider = Self.systemSnapshot(interfaceMode:)
    }

    init(snapshotProvider: @escaping SnapshotProvider) {
        self.snapshotProvider = snapshotProvider
    }

    public func sampleRate(interfaceMode: InterfaceMode) -> NetworkRate {
        guard let current = snapshotProvider(interfaceMode) else {
            previousSnapshot = nil
            return .zero
        }

        defer { previousSnapshot = current }

        guard let previousSnapshot,
              current.timestamp > previousSnapshot.timestamp,
              current.countersByInterface.count == previousSnapshot.countersByInterface.count else {
            return .zero
        }

        var downDelta: UInt64 = 0
        var upDelta: UInt64 = 0

        for (name, currentCounters) in current.countersByInterface {
            guard let previousCounters = previousSnapshot.countersByInterface[name],
                  currentCounters.receivedBytes >= previousCounters.receivedBytes,
                  currentCounters.sentBytes >= previousCounters.sentBytes else {
                return .zero
            }

            let (nextDownDelta, downOverflow) = downDelta.addingReportingOverflow(
                currentCounters.receivedBytes - previousCounters.receivedBytes
            )
            let (nextUpDelta, upOverflow) = upDelta.addingReportingOverflow(
                currentCounters.sentBytes - previousCounters.sentBytes
            )

            guard !downOverflow, !upOverflow else {
                return .zero
            }

            downDelta = nextDownDelta
            upDelta = nextUpDelta
        }

        let elapsed = current.timestamp - previousSnapshot.timestamp

        return NetworkRate(
            downBytesPerSecond: Double(downDelta) / elapsed,
            upBytesPerSecond: Double(upDelta) / elapsed
        )
    }

    public func reset() {
        previousSnapshot = nil
    }

    private static func systemSnapshot(interfaceMode: InterfaceMode) -> NetworkSnapshot? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        var countersByInterface: [String: NetworkInterfaceCounters] = [:]

        guard getifaddrs(&interfaces) == 0 else {
            return nil
        }

        if let interfaces {
            defer { freeifaddrs(interfaces) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces

            while let current = cursor {
                guard shouldCount(current.pointee, interfaceMode: interfaceMode) else {
                    cursor = current.pointee.ifa_next
                    continue
                }

                let name = String(cString: current.pointee.ifa_name)
                let data = current.pointee.ifa_data.assumingMemoryBound(to: if_data.self).pointee
                countersByInterface[name] = NetworkInterfaceCounters(
                    receivedBytes: UInt64(data.ifi_ibytes),
                    sentBytes: UInt64(data.ifi_obytes)
                )
                cursor = current.pointee.ifa_next
            }
        }

        return NetworkSnapshot(
            countersByInterface: countersByInterface,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    private static func shouldCount(_ interface: ifaddrs, interfaceMode: InterfaceMode) -> Bool {
        guard let address = interface.ifa_addr,
              interface.ifa_data != nil,
              address.pointee.sa_family == UInt8(AF_LINK) else {
            return false
        }

        let name = String(cString: interface.ifa_name)
        let flags = Int32(interface.ifa_flags)
        let isActive = (flags & IFF_UP) != 0
            && (flags & IFF_RUNNING) != 0
            && (flags & IFF_LOOPBACK) == 0

        guard isActive else {
            return false
        }

        switch interfaceMode {
        case .builtIn:
            return name.hasPrefix("en")
        case .allActive:
            return true
        }
    }
}
