import Foundation
import NetStatCore

struct RateHistoryPoint: Equatable {
    let timestamp: TimeInterval
    let rate: NetworkRate
}

final class RateHistory {
    private let duration: TimeInterval
    private(set) var points: [RateHistoryPoint] = []

    init(duration: TimeInterval = 60) {
        self.duration = duration
    }

    func append(_ rate: NetworkRate, at timestamp: TimeInterval) {
        guard timestamp.isFinite else { return }

        if let lastTimestamp = points.last?.timestamp, timestamp <= lastTimestamp {
            points.removeAll()
        }

        points.append(RateHistoryPoint(timestamp: timestamp, rate: rate))
        let cutoff = timestamp - duration
        points.removeAll { $0.timestamp < cutoff }
    }

    func reset() {
        points.removeAll()
    }
}
