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

final class HardwareInterfaceCache {
    private let refreshInterval: TimeInterval
    private var cachedNames: Set<String>?
    private var expiration: TimeInterval = 0

    init(refreshInterval: TimeInterval) {
        self.refreshInterval = refreshInterval
    }

    func names(at timestamp: TimeInterval, load: () -> Set<String>) -> Set<String> {
        if let cachedNames, timestamp < expiration {
            return cachedNames
        }

        let names = load()
        cachedNames = names
        expiration = timestamp + refreshInterval
        return names
    }
}

public final class NetworkSampler {
    typealias SnapshotProvider = (InterfaceMode) -> NetworkSnapshot?

    private let snapshotProvider: SnapshotProvider
    private var previousSnapshot: NetworkSnapshot?

    public init() {
        let hardwareCache = HardwareInterfaceCache(refreshInterval: 30)
        snapshotProvider = { interfaceMode in
            let hardwareNames = hardwareCache.names(
                at: ProcessInfo.processInfo.systemUptime,
                load: Self.hardwareInterfaceNames
            )
            return Self.systemSnapshot(
                interfaceMode: interfaceMode,
                hardwareInterfaceNames: hardwareNames
            )
        }
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

    private static func systemSnapshot(
        interfaceMode: InterfaceMode,
        hardwareInterfaceNames: Set<String>
    ) -> NetworkSnapshot? {
        let primaryNames = primaryInterfaceNames()
        let linkActiveByName: [String: Bool] = Dictionary(
            uniqueKeysWithValues: hardwareInterfaceNames.compactMap { name in
                interfaceLinkActive(name).map { (name, $0) }
            }
        )
        let hardwareNames = activeHardwareInterfaceNames(
            hardwareInterfaceNames: hardwareInterfaceNames,
            linkActiveByName: linkActiveByName
        )
        let selectedNames = selectedInterfaceNames(
            interfaceMode: interfaceMode,
            primaryInterfaceNames: primaryNames,
            hardwareInterfaceNames: hardwareNames
        )

        guard let countersByInterface = interfaceCounters(selectedNames: selectedNames) else {
            return nil
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
            guard !layeredPrimaryNames.isEmpty else {
                return primaryInterfaceNames
            }

            return hardwareInterfaceNames.isEmpty
                ? primaryInterfaceNames
                : hardwareInterfaceNames
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

    static func activeHardwareInterfaceNames(
        hardwareInterfaceNames: Set<String>,
        linkActiveByName: [String: Bool]
    ) -> Set<String> {
        hardwareInterfaceNames.filter { linkActiveByName[$0] ?? true }
    }

    private static func interfaceLinkActive(_ name: String) -> Bool? {
        let key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(
            nil,
            kSCDynamicStoreDomainState,
            name as CFString,
            kSCEntNetLink
        )
        guard let state = SCDynamicStoreCopyValue(nil, key) as? [String: Any] else {
            return nil
        }

        return state[kSCPropNetLinkActive as String] as? Bool
    }

    private static func interfaceCounters(
        selectedNames: Set<String>
    ) -> [String: NetworkInterfaceCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var bufferSize = 0

        let sizeResult = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(pointer.baseAddress, UInt32(pointer.count), nil, &bufferSize, nil, 0)
        }
        guard sizeResult == 0 else { return nil }
        guard bufferSize > 0 else { return [:] }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<if_msghdr2>.alignment
        )
        defer { buffer.deallocate() }

        var actualSize = bufferSize
        let dataResult = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(pointer.baseAddress, UInt32(pointer.count), buffer, &actualSize, nil, 0)
        }
        guard dataResult == 0 else { return nil }

        var countersByInterface: [String: NetworkInterfaceCounters] = [:]
        var offset = 0

        while offset < actualSize {
            guard actualSize - offset >= MemoryLayout<if_msghdr>.size else {
                return nil
            }

            let messagePointer = buffer.advanced(by: offset)
            let header = messagePointer.assumingMemoryBound(to: if_msghdr.self).pointee
            let messageLength = Int(header.ifm_msglen)

            guard messageLength > 0, offset + messageLength <= actualSize else {
                return nil
            }

            if header.ifm_type == UInt8(RTM_IFINFO2) {
                guard messageLength >= MemoryLayout<if_msghdr2>.size else {
                    return nil
                }

                let message = messagePointer.assumingMemoryBound(to: if_msghdr2.self).pointee
                var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                let resolvedName = nameBuffer.withUnsafeMutableBufferPointer { pointer in
                    if_indextoname(UInt32(message.ifm_index), pointer.baseAddress)
                }

                if let resolvedName {
                    let name = String(cString: resolvedName)
                    let flags = Int32(message.ifm_flags)
                    let isActive = (flags & IFF_UP) != 0
                        && (flags & IFF_RUNNING) != 0
                        && (flags & IFF_LOOPBACK) == 0

                    if isActive && selectedNames.contains(name) {
                        countersByInterface[name] = NetworkInterfaceCounters(
                            receivedBytes: message.ifm_data.ifi_ibytes,
                            sentBytes: message.ifm_data.ifi_obytes
                        )
                    }
                }
            }

            offset += messageLength
        }

        return countersByInterface
    }
}
