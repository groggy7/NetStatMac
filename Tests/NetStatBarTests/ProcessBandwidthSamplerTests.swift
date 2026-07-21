import AppKit
import Darwin
import Foundation
import XCTest
@testable import NetStatBar

final class ProcessBandwidthSamplerTests: XCTestCase {
    func testNettopParserUsesLatestDeltaAndSortsActiveProcesses() {
        let output = """
        ,bytes_in,bytes_out,
        Browser.100,9000,1000,
        ,bytes_in,bytes_out,
        com.example.agent.300,200,400,
        Browser.100,1000,500,
        Idle.200,0,0,
        """

        XCTAssertEqual(
            NettopOutputParser.latestDelta(from: output),
            [
                ProcessBandwidthRecord(
                    processName: "Browser",
                    processID: 100,
                    downloadedBytesPerSecond: 1_000,
                    uploadedBytesPerSecond: 500
                ),
                ProcessBandwidthRecord(
                    processName: "com.example.agent",
                    processID: 300,
                    downloadedBytesPerSecond: 200,
                    uploadedBytesPerSecond: 400
                )
            ]
        )
    }

    func testNettopParserRequiresACompletedDeltaSample() {
        XCTAssertTrue(
            NettopOutputParser.latestDelta(
                from: ",bytes_in,bytes_out,\nBrowser.100,9000,1000,\n"
            ).isEmpty
        )
    }

    @MainActor
    func testProcessPresenterAggregatesMatchingProcessNames() {
        let records = [
            ProcessBandwidthRecord(
                processName: "Browser",
                processID: 900_001,
                downloadedBytesPerSecond: 1_000,
                uploadedBytesPerSecond: 200
            ),
            ProcessBandwidthRecord(
                processName: "Browser",
                processID: 900_002,
                downloadedBytesPerSecond: 500,
                uploadedBytesPerSecond: 300
            ),
            ProcessBandwidthRecord(
                processName: "Editor",
                processID: 900_003,
                downloadedBytesPerSecond: 100,
                uploadedBytesPerSecond: 100
            )
        ]

        XCTAssertEqual(
            ProcessActivityPresenter.topActivities(from: records),
            [
                ProcessActivity(
                    name: "Browser",
                    downloadedBytesPerSecond: 1_500,
                    uploadedBytesPerSecond: 500
                ),
                ProcessActivity(
                    name: "Editor",
                    downloadedBytesPerSecond: 100,
                    uploadedBytesPerSecond: 100
                )
            ]
        )
    }

    @MainActor
    func testProcessPresenterKeepsOnlyTopThreeActivities() {
        let records = [
            ("First", 4_000 as UInt64),
            ("Second", 3_000),
            ("Third", 2_000),
            ("Fourth", 1_000)
        ].enumerated().map { index, process in
            ProcessBandwidthRecord(
                processName: process.0,
                processID: pid_t(910_000 + index),
                downloadedBytesPerSecond: process.1,
                uploadedBytesPerSecond: 0
            )
        }

        XCTAssertEqual(
            ProcessActivityPresenter.topActivities(from: records).map(\.name),
            ["First", "Second", "Third"]
        )
    }

    func testProcessApplicationMatcherFindsOuterApplicationForBundledHelper() {
        XCTAssertEqual(
            ProcessApplicationMatcher.outerApplicationURL(
                containing: URL(
                    fileURLWithPath: "/Applications/Example.app/Contents/Frameworks/Example Helper.app/Contents/MacOS/Example Helper"
                )
            )?.path,
            "/Applications/Example.app"
        )
    }

    func testProcessOwnerLookupIncludesCurrentProcessAndParent() {
        let ancestry = ProcessOwnerLookup.ancestry(startingAt: getpid())

        XCTAssertEqual(ancestry.first, getpid())
        XCTAssertTrue(ancestry.contains(getppid()))
        XCTAssertEqual(ProcessOwnerLookup.parentProcessID(of: getpid()), getppid())
        XCTAssertNotNil(ProcessOwnerLookup.executableURL(for: getpid()))
    }

    func testProcessApplicationMatcherFindsRunningApplicationPrefix() {
        XCTAssertEqual(
            ProcessApplicationMatcher.bestMatch(
                for: "Example Browser Helper (Network)",
                among: ["Example", "Example Browser", "Unrelated App"]
            ),
            "Example Browser"
        )
        XCTAssertNil(
            ProcessApplicationMatcher.bestMatch(
                for: "system-network-daemon",
                among: ["Example Browser"]
            )
        )
    }

    @MainActor
    func testInstalledChromeHelperResolvesFullColorApplicationIcon() throws {
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.google.Chrome"
        ) != nil else {
            throw XCTSkip("Google Chrome is not installed on this test host")
        }

        let activity = try XCTUnwrap(
            ProcessActivityPresenter.topActivities(
                from: [
                    ProcessBandwidthRecord(
                        processName: "Google Chrome Helper (Renderer)",
                        processID: 999_999,
                        downloadedBytesPerSecond: 1_000,
                        uploadedBytesPerSecond: 0
                    )
                ]
            ).first
        )

        XCTAssertEqual(activity.name, "Google Chrome")
        let icon = try XCTUnwrap(activity.icon)
        XCTAssertFalse(icon.isTemplate)
        XCTAssertNotNil(icon.tiffRepresentation)
    }

    @MainActor
    func testBundledChatGPTSubprocessResolvesApplicationIconGenerically() throws {
        let applicationURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let executableURL = applicationURL
            .appendingPathComponent("Contents/Resources/cua_node/bin/node")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw XCTSkip("ChatGPT's bundled Node executable is not installed on this test host")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-e", "setTimeout(() => {}, 10000)"]
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        let activity = try XCTUnwrap(
            ProcessActivityPresenter.topActivities(
                from: [
                    ProcessBandwidthRecord(
                        processName: "node",
                        processID: process.processIdentifier,
                        downloadedBytesPerSecond: 1_000,
                        uploadedBytesPerSecond: 0
                    )
                ]
            ).first
        )

        XCTAssertEqual(activity.name, "ChatGPT")
        let icon = try XCTUnwrap(activity.icon)
        XCTAssertFalse(icon.isTemplate)
        XCTAssertNotNil(icon.tiffRepresentation)
    }
}
