import Foundation
import XCTest

final class InstallerIntegrationTests: XCTestCase {
    func testFailedRestartRestoresPreviousAppAndLaunchAgent() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("NetStatBarInstallerTests-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: testRoot) }

        let applicationsDirectory = testRoot.appendingPathComponent("Applications")
        let launchAgentsDirectory = testRoot.appendingPathComponent("LaunchAgents")
        try fileManager.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let installedApp = applicationsDirectory.appendingPathComponent("NetStatBar.app")
        try fileManager.createDirectory(
            at: installedApp.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        let appMarker = installedApp.appendingPathComponent("Contents/version.txt")
        try "previous-app".write(to: appMarker, atomically: true, encoding: .utf8)

        let label = "com.local.netstatbar.tests.\(UUID().uuidString)"
        let launchAgent = launchAgentsDirectory.appendingPathComponent("\(label).plist")
        try "previous-launch-agent".write(to: launchAgent, atomically: true, encoding: .utf8)

        let launchLog = testRoot.appendingPathComponent("launchctl.log")
        let failedMarker = testRoot.appendingPathComponent("bootstrap-failed")
        let launchctlStub = testRoot.appendingPathComponent("launchctl-stub")
        try """
        #!/usr/bin/env bash
        set -eu
        echo "$*" >> "$NETSTAT_TEST_LAUNCH_LOG"
        if [ "$1" = "bootstrap" ] && [ ! -f "$NETSTAT_TEST_BOOTSTRAP_FAILED" ]; then
            touch "$NETSTAT_TEST_BOOTSTRAP_FAILED"
            exit 75
        fi
        """.write(to: launchctlStub, atomically: true, encoding: .utf8)
        try makeExecutable(launchctlStub)

        let killallStub = testRoot.appendingPathComponent("killall-stub")
        try "#!/usr/bin/env bash\nexit 0\n".write(
            to: killallStub,
            atomically: true,
            encoding: .utf8
        )
        try makeExecutable(killallStub)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", repositoryRoot.appendingPathComponent("install.sh").path]

        var environment = ProcessInfo.processInfo.environment
        environment["CONFIGURATION"] = "debug"
        environment["NETSTAT_SKIP_BUILD"] = "1"
        environment["NETSTAT_APPLICATIONS_DIR"] = applicationsDirectory.path
        environment["NETSTAT_LAUNCH_AGENT_DIR"] = launchAgentsDirectory.path
        environment["NETSTAT_LAUNCH_AGENT_LABEL"] = label
        environment["NETSTAT_LAUNCHCTL"] = launchctlStub.path
        environment["NETSTAT_KILLALL"] = killallStub.path
        environment["NETSTAT_LSREGISTER"] = testRoot.appendingPathComponent("missing-lsregister").path
        environment["NETSTAT_TEST_LAUNCH_LOG"] = launchLog.path
        environment["NETSTAT_TEST_BOOTSTRAP_FAILED"] = failedMarker.path
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let processOutput = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        XCTAssertNotEqual(process.terminationStatus, 0, processOutput)
        XCTAssertEqual(try String(contentsOf: appMarker, encoding: .utf8), "previous-app")
        XCTAssertEqual(
            try String(contentsOf: launchAgent, encoding: .utf8),
            "previous-launch-agent"
        )

        let launchCommands = try String(contentsOf: launchLog, encoding: .utf8)
        XCTAssertEqual(
            launchCommands.components(separatedBy: "bootstrap").count - 1,
            2,
            launchCommands
        )

        let leftovers = try fileManager.contentsOfDirectory(atPath: applicationsDirectory.path)
            .filter { $0.contains(".installing.") || $0.contains(".backup.") }
        XCTAssertTrue(leftovers.isEmpty, "Leftover transaction paths: \(leftovers)")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
