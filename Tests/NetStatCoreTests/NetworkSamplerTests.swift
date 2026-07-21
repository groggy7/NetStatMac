import XCTest
@testable import NetStatCore

final class NetworkSamplerTests: XCTestCase {
    func testFirstSampleEstablishesBaseline() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 1_000, sent: 2_000)], at: 1)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
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

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)

        let rate = sampler.sampleRate(interfaceMode: .builtIn)
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

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)

        let rate = sampler.sampleRate(interfaceMode: .builtIn)
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

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .allActive), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .allActive), .zero)

        let rate = sampler.sampleRate(interfaceMode: .allActive)
        XCTAssertEqual(rate.downBytesPerSecond, 400, accuracy: 0.000_001)
        XCTAssertEqual(rate.upBytesPerSecond, 600, accuracy: 0.000_001)
    }

    func testReplacedInterfaceProducesNeutralSample() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 100, sent: 200)], at: 1),
            snapshot(["en1": (received: 50_000, sent: 60_000)], at: 2)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
    }

    func testCounterResetProducesNeutralSampleAndNewBaseline() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 1_000, sent: 2_000)], at: 1),
            snapshot(["en0": (received: 10, sent: 20)], at: 2),
            snapshot(["en0": (received: 110, sent: 220)], at: 3)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)

        let rate = sampler.sampleRate(interfaceMode: .builtIn)
        XCTAssertEqual(rate.downBytesPerSecond, 100, accuracy: 0.000_001)
        XCTAssertEqual(rate.upBytesPerSecond, 200, accuracy: 0.000_001)
    }

    func testInvalidElapsedTimeProducesNeutralSample() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 100, sent: 200)], at: 1),
            snapshot(["en0": (received: 200, sent: 400)], at: 1)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
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

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
    }

    func testResetDiscardsPreviousSnapshot() {
        let sampler = makeSampler([
            snapshot(["en0": (received: 100, sent: 200)], at: 1),
            snapshot(["en0": (received: 200, sent: 400)], at: 2)
        ])

        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
        sampler.reset()
        XCTAssertEqual(sampler.sampleRate(interfaceMode: .builtIn), .zero)
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
