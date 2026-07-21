import Darwin
import Foundation
import SystemConfiguration

public enum InterfaceMode: String, CaseIterable, Sendable {
    // Preserve the old raw values so existing saved preferences migrate automatically.
    case automatic = "builtIn"
    case allHardware = "allActive"

    public var title: String {
        switch self {
        case .automatic:
            return "Automatic (Primary Route)"
        case .allHardware:
            return "All Active Hardware"
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
        let primaryNames = primaryInterfaceNames()
        let hardwareNames = hardwareInterfaceNames()
        let selectedNames = selectedInterfaceNames(
            interfaceMode: interfaceMode,
            primaryInterfaceNames: primaryNames,
            hardwareInterfaceNames: hardwareNames
        )

        guard getifaddrs(&interfaces) == 0 else {
            return nil
        }

        if let interfaces {
            defer { freeifaddrs(interfaces) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces

            while let current = cursor {
                guard shouldCount(current.pointee, selectedNames: selectedNames) else {
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

    static func selectedInterfaceNames(
        interfaceMode: InterfaceMode,
        primaryInterfaceNames: Set<String>,
        hardwareInterfaceNames: Set<String>
    ) -> Set<String> {
        switch interfaceMode {
        case .automatic:
            let layeredPrimaryNames = primaryInterfaceNames.subtracting(hardwareInterfaceNames)
            return layeredPrimaryNames.isEmpty ? primaryInterfaceNames : layeredPrimaryNames
        case .allHardware:
            return hardwareInterfaceNames
        }
    }

    private static func primaryInterfaceNames() -> Set<String> {
        let entities = [kSCEntNetIPv4, kSCEntNetIPv6]
        let primaryInterfaceKey = kSCDynamicStorePropNetPrimaryInterface as String

        return Set(entities.compactMap { entity in
            let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
                nil,
                kSCDynamicStoreDomainState,
                entity
            )
            guard let state = SCDynamicStoreCopyValue(nil, key) as? [String: Any] else {
                return nil
            }

            return state[primaryInterfaceKey] as? String
        })
    }

    private static func hardwareInterfaceNames() -> Set<String> {
        let hardwareTypes = Set([
            kSCNetworkInterfaceTypeBluetooth as String,
            kSCNetworkInterfaceTypeEthernet as String,
            kSCNetworkInterfaceTypeFireWire as String,
            kSCNetworkInterfaceTypeIEEE80211 as String,
            kSCNetworkInterfaceTypeWWAN as String
        ])

        return Set((SCNetworkInterfaceCopyAll() as NSArray).compactMap { value in
            let interface = value as! SCNetworkInterface
            guard let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  hardwareTypes.contains(type),
                  let name = SCNetworkInterfaceGetBSDName(interface) as String? else {
                return nil
            }

            return name
        })
    }

    private static func shouldCount(_ interface: ifaddrs, selectedNames: Set<String>) -> Bool {
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

        return selectedNames.contains(name)
    }
}
