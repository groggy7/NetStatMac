import AppKit
import Darwin
import Foundation

struct ProcessBandwidthRecord: Equatable, Sendable {
    let processName: String
    let processID: pid_t
    let downloadedBytesPerSecond: UInt64
    let uploadedBytesPerSecond: UInt64

    var totalBytesPerSecond: UInt64 {
        let (total, overflow) = downloadedBytesPerSecond.addingReportingOverflow(
            uploadedBytesPerSecond
        )
        return overflow ? UInt64.max : total
    }
}

struct ProcessActivity: Equatable {
    let name: String
    let downloadedBytesPerSecond: UInt64
    let uploadedBytesPerSecond: UInt64
    let icon: NSImage?

    init(
        name: String,
        downloadedBytesPerSecond: UInt64,
        uploadedBytesPerSecond: UInt64,
        icon: NSImage? = nil
    ) {
        self.name = name
        self.downloadedBytesPerSecond = downloadedBytesPerSecond
        self.uploadedBytesPerSecond = uploadedBytesPerSecond
        self.icon = icon
    }

    var totalBytesPerSecond: UInt64 {
        let (total, overflow) = downloadedBytesPerSecond.addingReportingOverflow(
            uploadedBytesPerSecond
        )
        return overflow ? UInt64.max : total
    }

    static func == (lhs: ProcessActivity, rhs: ProcessActivity) -> Bool {
        lhs.name == rhs.name
            && lhs.downloadedBytesPerSecond == rhs.downloadedBytesPerSecond
            && lhs.uploadedBytesPerSecond == rhs.uploadedBytesPerSecond
    }
}

actor ProcessSamplingWorker {
    func sampleTopProcesses() -> [ProcessBandwidthRecord] {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = [
            "-P", "-L", "2", "-d", "-x", "-n",
            "-t", "external",
            "-J", "bytes_in,bytes_out",
            "-s", "1"
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return [] }
            return NettopOutputParser.latestDelta(from: String(decoding: data, as: UTF8.self))
        } catch {
            return []
        }
    }
}

enum NettopOutputParser {
    static func latestDelta(from output: String) -> [ProcessBandwidthRecord] {
        var samples: [[ProcessBandwidthRecord]] = []

        for line in output.split(whereSeparator: \Character.isNewline) {
            let row = String(line)
            if row.hasPrefix(",bytes_in,bytes_out") {
                samples.append([])
                continue
            }

            guard !samples.isEmpty, let record = parseRow(row) else { continue }
            samples[samples.count - 1].append(record)
        }

        guard samples.count >= 2 else { return [] }

        return (samples.last ?? [])
            .filter { $0.totalBytesPerSecond > 0 }
            .sorted { lhs, rhs in
                if lhs.totalBytesPerSecond == rhs.totalBytesPerSecond {
                    return lhs.processName.localizedCaseInsensitiveCompare(rhs.processName) == .orderedAscending
                }
                return lhs.totalBytesPerSecond > rhs.totalBytesPerSecond
            }
    }

    private static func parseRow(_ row: String) -> ProcessBandwidthRecord? {
        var fields = row.split(separator: ",", omittingEmptySubsequences: false)
        if fields.last?.isEmpty == true {
            fields.removeLast()
        }

        guard fields.count >= 3,
              let uploaded = UInt64(fields[fields.count - 1]),
              let downloaded = UInt64(fields[fields.count - 2]) else {
            return nil
        }

        let identity = fields.dropLast(2).joined(separator: ",")
        guard let separator = identity.lastIndex(of: "."),
              let processID = pid_t(identity[identity.index(after: separator)...]) else {
            return nil
        }

        let name = String(identity[..<separator]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        return ProcessBandwidthRecord(
            processName: name,
            processID: processID,
            downloadedBytesPerSecond: downloaded,
            uploadedBytesPerSecond: uploaded
        )
    }
}

@MainActor
enum ProcessActivityPresenter {
    private struct ApplicationPresentation {
        let name: String
        let bundleIdentifier: String?
        let applicationURL: URL
        let icon: NSImage
    }

    private static var runningApplicationCache: [ApplicationPresentation] = []
    private static var runningApplicationCacheExpiration: TimeInterval = 0
    private static var processPresentationCache: [pid_t: ProcessPresentationCacheEntry] = [:]
    private static var iconCache: [String: NSImage] = [:]

    private struct ProcessPresentationCacheEntry {
        let presentation: ApplicationPresentation?
        let expiration: TimeInterval
    }

    static func topActivities(
        from records: [ProcessBandwidthRecord],
        limit: Int = 3
    ) -> [ProcessActivity] {
        var totals: [String: (downloaded: UInt64, uploaded: UInt64, icon: NSImage?)] = [:]

        for record in records {
            let display = displayInfo(for: record)
            let name = display.name
            guard name != "NetStatBar", name != "nettop" else { continue }

            let current = totals[name, default: (0, 0, nil)]
            totals[name] = (
                addingClamped(current.downloaded, record.downloadedBytesPerSecond),
                addingClamped(current.uploaded, record.uploadedBytesPerSecond),
                current.icon ?? display.icon
            )
        }

        return totals.map { name, totals in
            ProcessActivity(
                name: name,
                downloadedBytesPerSecond: totals.downloaded,
                uploadedBytesPerSecond: totals.uploaded,
                icon: totals.icon
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalBytesPerSecond == rhs.totalBytesPerSecond {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.totalBytesPerSecond > rhs.totalBytesPerSecond
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func displayInfo(for record: ProcessBandwidthRecord) -> (name: String, icon: NSImage?) {
        if let presentation = applicationPresentation(forProcessID: record.processID) {
            return (presentation.name, presentation.icon)
        }

        let runningApplications = cachedRunningApplications()
        if let matchedName = ProcessApplicationMatcher.bestMatch(
            for: record.processName,
            among: runningApplications.map(\.name)
        ), let presentation = runningApplications.first(where: { $0.name == matchedName }) {
            return (presentation.name, presentation.icon)
        }

        return (record.processName, nil)
    }

    private static func applicationPresentation(
        forProcessID processID: pid_t
    ) -> ApplicationPresentation? {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = processPresentationCache[processID], now < cached.expiration {
            return cached.presentation
        }

        let presentation = ProcessOwnerLookup.ancestry(startingAt: processID).lazy.compactMap {
            candidateProcessID -> ApplicationPresentation? in
            if let executableURL = ProcessOwnerLookup.executableURL(for: candidateProcessID),
               let applicationURL = ProcessApplicationMatcher.outerApplicationURL(
                   containing: executableURL
               ),
               let presentation = applicationPresentation(
                   at: applicationURL,
                   bundleIdentifier: nil
               ) {
                return presentation
            }

            guard let application = NSRunningApplication(
                processIdentifier: candidateProcessID
            ) else {
                return nil
            }

            if let presentation = applicationPresentation(for: application) {
                return presentation
            }

            guard let localizedName = application.localizedName,
                  !localizedName.isEmpty,
                  let icon = application.icon else {
                return nil
            }
            icon.isTemplate = false
            return ApplicationPresentation(
                name: localizedName,
                bundleIdentifier: application.bundleIdentifier,
                applicationURL: application.bundleURL ?? URL(fileURLWithPath: "/"),
                icon: icon
            )
        }.first

        if processPresentationCache.count > 256 {
            processPresentationCache = processPresentationCache.filter {
                now < $0.value.expiration
            }
        }
        processPresentationCache[processID] = ProcessPresentationCacheEntry(
            presentation: presentation,
            expiration: now + 5
        )
        return presentation
    }

    private static func cachedRunningApplications() -> [ApplicationPresentation] {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= runningApplicationCacheExpiration else {
            return runningApplicationCache
        }

        var applicationsByPath: [String: ApplicationPresentation] = [:]
        for application in NSWorkspace.shared.runningApplications {
            guard let presentation = applicationPresentation(for: application) else { continue }
            applicationsByPath[presentation.applicationURL.standardizedFileURL.path] = presentation
        }

        runningApplicationCache = Array(applicationsByPath.values)
        runningApplicationCacheExpiration = now + 5
        return runningApplicationCache
    }

    private static func applicationPresentation(
        for application: NSRunningApplication
    ) -> ApplicationPresentation? {
        guard let bundleURL = application.bundleURL,
              let applicationURL = ProcessApplicationMatcher.outerApplicationURL(
                  containing: bundleURL
              ) else {
            return nil
        }

        return applicationPresentation(
            at: applicationURL,
            bundleIdentifier: application.bundleIdentifier
        )
    }

    private static func applicationPresentation(
        at applicationURL: URL,
        bundleIdentifier: String?,
        nameOverride: String? = nil
    ) -> ApplicationPresentation? {
        guard let bundle = Bundle(url: applicationURL) else { return nil }
        let displayName = nameOverride
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? applicationURL.deletingPathExtension().lastPathComponent
        guard !displayName.isEmpty else { return nil }

        let path = applicationURL.standardizedFileURL.path
        let icon: NSImage
        if let cachedIcon = iconCache[path] {
            icon = cachedIcon
        } else {
            icon = NSWorkspace.shared.icon(forFile: path)
            icon.isTemplate = false
            iconCache[path] = icon
        }

        return ApplicationPresentation(
            name: displayName,
            bundleIdentifier: bundleIdentifier ?? bundle.bundleIdentifier,
            applicationURL: applicationURL,
            icon: icon
        )
    }

    private static func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}

enum ProcessApplicationMatcher {
    static func bestMatch(for processName: String, among applicationNames: [String]) -> String? {
        let normalizedProcessName = processName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        return applicationNames
            .filter { applicationName in
                let normalizedApplicationName = applicationName.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                return normalizedProcessName == normalizedApplicationName
                    || normalizedProcessName.hasPrefix(normalizedApplicationName + " ")
                    || normalizedProcessName.hasPrefix(normalizedApplicationName + "(")
            }
            .max { $0.count < $1.count }
    }

    static func outerApplicationURL(containing fileURL: URL) -> URL? {
        var currentURL = URL(fileURLWithPath: "/")

        for component in fileURL.standardizedFileURL.pathComponents.dropFirst() {
            currentURL.appendPathComponent(component)
            if currentURL.pathExtension.lowercased() == "app" {
                return currentURL
            }
        }

        return nil
    }
}

enum ProcessOwnerLookup {
    private static let executablePathBufferSize = 4_096

    static func ancestry(startingAt processID: pid_t, maximumDepth: Int = 12) -> [pid_t] {
        guard processID > 1, maximumDepth > 0 else { return [] }

        var ancestry: [pid_t] = []
        var visited: Set<pid_t> = []
        var candidate = processID

        while candidate > 1,
              ancestry.count < maximumDepth,
              visited.insert(candidate).inserted {
            ancestry.append(candidate)
            guard let parent = parentProcessID(of: candidate), parent > 1 else { break }
            candidate = parent
        }

        return ancestry
    }

    static func executableURL(for processID: pid_t) -> URL? {
        guard processID > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: executablePathBufferSize)
        let length = proc_pidpath(processID, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
    }

    static func parentProcessID(of processID: pid_t) -> pid_t? {
        guard processID > 1 else { return nil }

        var info = proc_bsdinfo()
        let actualSize = proc_pidinfo(
            processID,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard actualSize == MemoryLayout<proc_bsdinfo>.size else { return nil }

        let parentProcessID = pid_t(info.pbi_ppid)
        return parentProcessID > 0 ? parentProcessID : nil
    }
}
