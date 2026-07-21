import XCTest
@testable import NetStatCore

final class NetworkSamplerTests: XCTestCase {
    func testFirstSampleEstablishesBaseline() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 1_000, sent: 2_000)], at: 1)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
    }

    func testRateUsesCounterDeltasAndElapsedTime() {
        let sampler = makeSampler([
            snapshot(
                [
                    "en0": (received: 100, sent: 200),
                    "en1": (received: 1_000, sent: 2_000)
                ],
                at: 1
            ),
            snapshot(
                [
                    "en0": (received: 300, sent: 600),
                    "en1": (received: 1_600, sent: 2_800)
                ],
                at: 3
            )
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)

        let rate = sampler.sampleRate(interfaceMode: .automatic)
        XCTAssertEqual(rate.downBytesPerSecond, 400, accuracy: 0.000_001)
        XCTAssertEqual(rate.upBytesPerSecond, 600, accuracy: 0.000_001)
    }

    func testFailedReadClearsBaseline() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 100, sent: 200)], at: 1),
            nil,
            snapshot(["en0": (received: 10_000, sent: 20_000)], at: 3),
            snapshot(["en0": (received: 10_100, sent: 20_200)], at: 4)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)

        let rate = sampler.sampleRate(interfaceMode: .automatic)
        XCTAssertEqual(rate.downBytesPerSecond, 100, accuracy: 0.000_001)
        XCTAssertEqual(rate.upBytesPerSecond, 200, accuracy: 0.000_001)
    }

    func testAddedInterfaceProducesNeutralSampleAndNewBaseline() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 100, sent: 200)], at: 1),
            snapshot(
                [
                    "en0": (received: 200, sent: 300),
                    "utun0": (received: 50_000, sent: 60_000)
                ],
                at: 2
            ),
            snapshot(
                [
                    "en0": (received: 300, sent: 500),
                    "utun0": (received: 50_300, sent: 60_400)
                ],
                at: 3
            )
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .allHardware), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .allHardware), .zero)

        let rate = sampler.sampleRate(interfaceMode: .allHardware)
        XCTAssertEqual(rate.downBytesPerSecond, 400, accuracy: 0.000_001)
        XCTAssertEqual(rate.upBytesPerSecond, 600, accuracy: 0.000_001)
    }

    func testReplacedInterfaceProducesNeutralSample() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 100, sent: 200)], at: 1),
            snapshot(["en1": (received: 50_000, sent: 60_000)], at: 2)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
    }

    func testCounterResetProducesNeutralSampleAndNewBaseline() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 1_000, sent: 2_000)], at: 1),
            snapshot(["en0": (received: 10, sent: 20)], at: 2),
            snapshot(["en0": (received: 110, sent: 220)], at: 3)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)

        let rate = sampler.sampleRate(interfaceMode: .automatic)
        XCTAssertEqual(rate.downBytesPerSecond, 100, accuracy: 0.000_001)
        XCTAssertEqual(rate.upBytesPerSecond, 200, accuracy: 0.000_001)
    }

    func testCountersContinueAcrossLegacy32BitBoundary() {
        let legacyMaximum = UInt64(UInt32.max)
        let sampler = makeSampler([
            snapshot(
                ["en0": (received: legacyMaximum - 50, sent: legacyMaximum - 100)],
                at: 1
            ),
            snapshot(
                ["en0": (received: legacyMaximum + 150, sent: legacyMaximum + 300)],
                at: 2
            )
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
        let rate = sampler.sampleRate(interfaceMode: .automatic)
        XCTAssertEqual(rate.downBytesPerSecond, 200, accuracy: 0.000_001)
        XCTAssertEqual(rate.upBytesPerSecond, 400, accuracy: 0.000_001)
    }

    func testInvalidElapsedTimeProducesNeutralSample() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 100, sent: 200)], at: 1),
            snapshot(["en0": (received: 200, sent: 400)], at: 1)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
    }

    func testDeltaOverflowProducesNeutralSample() {
        let sampler = makeSampler([
            snapshot(
                [
                    "en0": (received: 0, sent: 0),
                    "en1": (received: 0, sent: 0)
                ],
                at: 1
            ),
            snapshot(
                [
                    "en0": (received: UInt64.max, sent: UInt64.max),
                    "en1": (received: UInt64.max, sent: UInt64.max)
                ],
                at: 2
            )
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
    }

    func testResetDiscardsPreviousSnapshot() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 100, sent: 200)], at: 1),
            snapshot(["en0": (received: 200, sent: 400)], at: 2)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
        sampler.reset()
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .automatic), .zero)
    }

    func testAutomaticModeIncludesUnusuallyNamedPrimaryHardware() {
        XCTAssertEqual(
            NetworkSampler.selectedInterfaceNames(
                interfaceMode: .automatic,
                primaryInterfaceNames: ["usb42"],
                hardwareInterfaceNames: ["en0", "usb42"]
            ),
            ["usb42"]
        )
    }

    func testAutomaticModeUsesHardwareTransportWhenVPNIsPrimary() {
        XCTAssertEqual(
            NetworkSampler.selectedInterfaceNames(
                interfaceMode: .automatic,
                primaryInterfaceNames: ["en0", "utun7"],
                hardwareInterfaceNames: ["en0", "usb42"]
            ),
            ["en0", "usb42"]
        )
    }

    func testAutomaticModeFallsBackToLayeredPrimaryWithoutHardware() {
        XCTAssertEqual(
            NetworkSampler.selectedInterfaceNames(
                interfaceMode: .automatic,
                primaryInterfaceNames: ["ppp0"],
                hardwareInterfaceNames: []
            ),
            ["ppp0"]
        )
    }

    func testAutomaticModeKeepsDistinctHardwarePrimaries() {
        XCTAssertEqual(
            NetworkSampler.selectedInterfaceNames(
                interfaceMode: .automatic,
                primaryInterfaceNames: ["en8", "wifi42"],
                hardwareInterfaceNames: ["en8", "wifi42"]
            ),
            ["en8", "wifi42"]
        )
    }

    func testAllHardwareModeExcludesVirtualInterfaces() {
        XCTAssertEqual(
            NetworkSampler.selectedInterfaceNames(
                interfaceMode: .allHardware,
                primaryInterfaceNames: ["utun7"],
                hardwareInterfaceNames: ["en0", "usb42"]
            ),
            ["en0", "usb42"]
        )
    }

    func testInactiveHardwareInterfacesAreExcluded() {
        XCTAssertEqual(
            NetworkSampler.activeHardwareInterfaceNames(
                hardwareInterfaceNames: ["en0", "en1", "usb42"],
                linkActiveByName: ["en0": true, "en1": false]
            ),
            ["en0", "usb42"]
        )
    }

    func testLegacyInterfaceModePreferencesMapToNewModes() {
        XCTAssertEqual(InterfaceMode(rawValue: "builtIn"), .automatic)
        XCTAssertEqual(InterfaceMode(rawValue: "allActive"), .allHardware)
    }

    private func makeSampler(_ snapshots: [NetworkSnapshot?]) -> NetworkSampler {
        var remainingSnapshots = snapshots
        return NetworkSampler { _ in
            remainingSnapshots.removeFirst()
        }
    }

    private func snapshot(
        _ interfaces: [String: (received: UInt64, sent: UInt64)],
        at timestamp: TimeInterval
    ) -> NetworkSnapshot {
        NetworkSnapshot(
            countersByInterface: interfaces.mapValues {
                NetworkInterfaceCounters(receivedBytes: $0.received, sentBytes: $0.sent)
            },
            timestamp: timestamp
        )
    }
}
