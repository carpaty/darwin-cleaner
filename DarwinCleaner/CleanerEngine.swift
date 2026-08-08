import Foundation

enum CandidateRule: Hashable, Sendable {
    case any
    case fileExtensions(Set<String>)
    case namePrefix(String)
    case orphanBundleIdentifier(removingSuffix: String?)
}

struct ScanLocation: Sendable {
    let url: URL
    let category: CleanupCategory
    let minimumAge: TimeInterval
    let risk: CleanupRisk
    let action: CleanupAction
    let rule: CandidateRule
    let excludedNames: Set<String>
    let excludedNamePrefixes: Set<String>

    init(
        url: URL,
        category: CleanupCategory,
        minimumAge: TimeInterval,
        risk: CleanupRisk = .recommended,
        action: CleanupAction = .moveToTrash,
        rule: CandidateRule = .any,
        excludedNames: Set<String> = [],
        excludedNamePrefixes: Set<String> = []
    ) {
        self.url = url
        self.category = category
        self.minimumAge = minimumAge
        self.risk = risk
        self.action = action
        self.rule = rule
        self.excludedNames = excludedNames
        self.excludedNamePrefixes = excludedNamePrefixes
    }
}

actor CleanerEngine {
    private struct FileInspection {
        var size: Int64 = 0
        var newestModificationDate: Date?
    }

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let locations: [ScanLocation]
    private let includeManagedTools: Bool
    private let installedBundleIDsOverride: Set<String>?

    init(
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        locations: [ScanLocation]? = nil,
        includeManagedTools: Bool? = nil,
        installedBundleIDs: Set<String>? = nil
    ) {
        let usesDefaultLocations = locations == nil
        self.fileManager = fileManager
        self.now = now
        self.locations = locations ?? Self.defaultLocations(fileManager: fileManager)
        self.includeManagedTools = includeManagedTools ?? usesDefaultLocations
        self.installedBundleIDsOverride = installedBundleIDs
    }

    static func defaultLocations(fileManager: FileManager) -> [ScanLocation] {
        let home = fileManager.homeDirectoryForCurrentUser
        let day: TimeInterval = 86_400
        let excludedCaches: Set<String> = [
            "CloudKit", "familycircled", "Homebrew", "CocoaPods", "Yarn", "org.swift.swiftpm"
        ]
        return [
            ScanLocation(
                url: home.appending(path: "Library/Caches"),
                category: .caches,
                minimumAge: 7 * day,
                excludedNames: excludedCaches,
                excludedNamePrefixes: ["com.apple."]
            ),
            ScanLocation(url: home.appending(path: "Library/Logs"), category: .logs, minimumAge: 14 * day),
            ScanLocation(
                url: home.appending(path: ".Trash"),
                category: .trash,
                minimumAge: 30 * day,
                risk: .irreversible,
                action: .permanentDelete
            ),

            ScanLocation(url: home.appending(path: "Library/Developer/Xcode/DerivedData"), category: .developer, minimumAge: 7 * day),
            ScanLocation(url: home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport"), category: .developer, minimumAge: 30 * day, risk: .review),
            ScanLocation(url: home.appending(path: "Library/Developer/Xcode/Archives"), category: .developer, minimumAge: 90 * day, risk: .review),
            ScanLocation(url: home.appending(path: "Library/Developer/Xcode/DocumentationCache"), category: .developer, minimumAge: 30 * day, risk: .review),
            ScanLocation(url: home.appending(path: "Library/Developer/Xcode/Products"), category: .developer, minimumAge: 30 * day, risk: .review),
            ScanLocation(url: home.appending(path: "Library/Developer/Packages"), category: .developer, minimumAge: 30 * day, risk: .review),
            ScanLocation(url: home.appending(path: "Library/Developer/CoreSimulator/Caches"), category: .developer, minimumAge: 14 * day, risk: .review),

            ScanLocation(
                url: home.appending(path: "Downloads"),
                category: .installers,
                minimumAge: 30 * day,
                risk: .review,
                rule: .fileExtensions(["dmg", "pkg", "zip", "xip"])
            ),
            ScanLocation(
                url: URL(fileURLWithPath: "/Applications", isDirectory: true),
                category: .installers,
                minimumAge: 30 * day,
                risk: .review,
                rule: .namePrefix("Install macOS")
            ),
            ScanLocation(
                url: home.appending(path: "Library/Application Support/MobileSync/Backup"),
                category: .backups,
                minimumAge: 0,
                risk: .review
            ),

            ScanLocation(url: home.appending(path: ".gradle/caches"), category: .packageManagers, minimumAge: 30 * day, risk: .review),
            ScanLocation(url: home.appending(path: ".gradle/wrapper/dists"), category: .packageManagers, minimumAge: 30 * day, risk: .review),

            ScanLocation(
                url: home.appending(path: "Library/Preferences"),
                category: .leftovers,
                minimumAge: 90 * day,
                risk: .review,
                rule: .orphanBundleIdentifier(removingSuffix: ".plist")
            ),
            ScanLocation(
                url: home.appending(path: "Library/Saved Application State"),
                category: .leftovers,
                minimumAge: 90 * day,
                risk: .review,
                rule: .orphanBundleIdentifier(removingSuffix: ".savedState")
            ),
            ScanLocation(
                url: home.appending(path: "Library/HTTPStorages"),
                category: .leftovers,
                minimumAge: 90 * day,
                risk: .review,
                rule: .orphanBundleIdentifier(removingSuffix: nil)
            ),
            ScanLocation(
                url: home.appending(path: "Library/WebKit"),
                category: .leftovers,
                minimumAge: 90 * day,
                risk: .review,
                rule: .orphanBundleIdentifier(removingSuffix: nil)
            ),
            ScanLocation(
                url: home.appending(path: "Library/Application Support"),
                category: .leftovers,
                minimumAge: 90 * day,
                risk: .review,
                rule: .orphanBundleIdentifier(removingSuffix: nil)
            ),
            ScanLocation(
                url: home.appending(path: "Library/Cookies"),
                category: .leftovers,
                minimumAge: 90 * day,
                risk: .review,
                rule: .orphanBundleIdentifier(removingSuffix: ".binarycookies")
            )
        ]
    }

    func scan() -> ScanSummary {
        var summary = ScanSummary()
        let scanDate = now()
        let installedBundleIDs = locations.contains(where: { location in
            if case .orphanBundleIdentifier = location.rule { return true }
            return false
        }) ? (installedBundleIDsOverride ?? discoverInstalledBundleIDs()) : []

        for location in locations {
            guard isKnownRoot(location.url, category: location.category) else { continue }
            do {
                let children = try fileManager.contentsOfDirectory(
                    at: location.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey],
                    options: []
                )
                for child in children {
                    guard matches(child, location: location, installedBundleIDs: installedBundleIDs),
                          let item = makeItem(child, location: location, scanDate: scanDate) else { continue }
                    summary.items.append(item)
                }
            } catch {
                if fileManager.fileExists(atPath: location.url.path) {
                    summary.inaccessiblePaths.append(location.url.path)
                }
            }
        }

        if includeManagedTools {
            summary.items.append(contentsOf: scanManagedTools())
        }
        summary.items.sort { $0.size > $1.size }
        return summary
    }

    func clean(_ items: [CleanupItem]) -> CleanupResult {
        var result = CleanupResult()
        let installedBundleIDs = items.contains(where: { $0.category == .leftovers })
            ? (installedBundleIDsOverride ?? discoverInstalledBundleIDs())
            : []
        for item in items where item.isSelected {
            do {
                switch item.action {
                case .moveToTrash, .permanentDelete:
                    guard isAllowedFileItem(item, installedBundleIDs: installedBundleIDs), !isSymlink(item.url) else {
                        result.failures.append("Safety check rejected \(item.url.path)")
                        continue
                    }
                    if item.action == .permanentDelete {
                        try fileManager.removeItem(at: item.url)
                    } else {
                        _ = try fileManager.trashItem(at: item.url, resultingItemURL: nil)
                    }
                case let .runTool(tool):
                    guard item.id == "tool:\(tool.rawValue)", item.category == tool.category else {
                        result.failures.append("Safety check rejected managed action \(item.displayName)")
                        continue
                    }
                    let execution = run(tool: tool, arguments: tool.cleanupArguments)
                    guard execution.status == 0 else {
                        throw CleanerError.commandFailed(execution.output)
                    }
                }
                result.removedCount += 1
                result.reclaimedBytes += item.size
                result.removedIDs.insert(item.id)
            } catch {
                result.failures.append("\(item.displayName): \(error.localizedDescription)")
            }
        }
        return result
    }

    private func makeItem(_ url: URL, location: ScanLocation, scanDate: Date) -> CleanupItem? {
        guard !isSymlink(url) else { return nil }
        if (location.action == .moveToTrash || location.action == .permanentDelete),
           !fileManager.isDeletableFile(atPath: url.path) {
            return nil
        }
        let inspection = inspect(url)
        guard location.minimumAge == 0 || inspection.newestModificationDate.map({
            scanDate.timeIntervalSince($0) >= location.minimumAge
        }) == true else { return nil }

        return CleanupItem(
            url: url,
            category: location.category,
            size: inspection.size,
            modifiedAt: inspection.newestModificationDate,
            risk: location.risk,
            action: location.action
        )
    }

    private func matches(_ url: URL, location: ScanLocation, installedBundleIDs: Set<String>) -> Bool {
        guard url.lastPathComponent != ".DS_Store" else { return false }
        guard !location.excludedNames.contains(url.lastPathComponent) else { return false }
        guard !location.excludedNamePrefixes.contains(where: url.lastPathComponent.hasPrefix) else { return false }
        switch location.rule {
        case .any:
            return true
        case let .fileExtensions(extensions):
            return extensions.contains(url.pathExtension.lowercased())
        case let .namePrefix(prefix):
            return url.lastPathComponent.hasPrefix(prefix) && url.pathExtension.lowercased() == "app"
        case let .orphanBundleIdentifier(suffix):
            var identifier = url.lastPathComponent
            if let suffix, identifier.hasSuffix(suffix) {
                identifier.removeLast(suffix.count)
            }
            guard isPlausibleThirdPartyBundleIdentifier(identifier) else { return false }
            return !installedBundleIDs.contains { installed in
                installed == identifier || installed.hasPrefix(identifier + ".") || identifier.hasPrefix(installed + ".")
            }
        }
    }

    private func isPlausibleThirdPartyBundleIdentifier(_ identifier: String) -> Bool {
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        return components.count >= 2
            && components.allSatisfy { !$0.isEmpty }
            && !identifier.contains(" ")
            && !identifier.hasPrefix("com.apple.")
            && !identifier.hasPrefix("group.")
            && !identifier.hasPrefix("systemgroup.")
            && identifier.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_" )).contains($0)
            }
    }

    private func discoverInstalledBundleIDs() -> Set<String> {
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appending(path: "Applications")
        ]
        var identifiers: Set<String> = []
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                if let identifier = Bundle(url: url)?.bundleIdentifier {
                    identifiers.insert(identifier)
                }
            }
        }
        return identifiers
    }

    private func inspect(_ url: URL) -> FileInspection {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        var inspection = FileInspection()
        add(url, keys: keys, to: &inspection)

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return inspection }

        for case let child as URL in enumerator {
            if isSymlink(child) {
                enumerator.skipDescendants()
                continue
            }
            add(child, keys: keys, to: &inspection)
        }
        return inspection
    }

    private func add(_ url: URL, keys: Set<URLResourceKey>, to inspection: inout FileInspection) {
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        if values.isRegularFile == true {
            inspection.size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        if let modified = values.contentModificationDate,
           inspection.newestModificationDate == nil || modified > inspection.newestModificationDate! {
            inspection.newestModificationDate = modified
        }
    }

    private func scanManagedTools() -> [CleanupItem] {
        ManagedCleanupTool.allCases.compactMap { tool in
            guard executableURL(for: tool) != nil else { return nil }
            if tool == .docker {
                let usage = run(tool: tool, arguments: ["system", "df", "--format", "{{json .}}"])
                let reclaimable = usage.status == 0 ? dockerReclaimableBytes(from: usage.output) : 0
                guard reclaimable > 0 else { return nil }
                return managedItem(tool: tool, size: reclaimable, detail: "Runs \(tool.commandDescription); Docker volumes are preserved.")
            }
            if tool == .unavailableSimulators {
                let devices = run(tool: tool, arguments: ["simctl", "list", "devices", "unavailable", "--json"])
                let reclaimable = devices.status == 0 ? unavailableSimulatorBytes(from: devices.output) : 0
                guard reclaimable > 0 else { return nil }
                return managedItem(tool: tool, size: reclaimable, detail: "Runs \(tool.commandDescription); installed runtimes are preserved.")
            }

            let cacheURLs = managedCacheURLs(for: tool)
            let size = cacheURLs.reduce(Int64(0)) { $0 + inspect($1).size }
            guard size > 0 else { return nil }
            let locations = cacheURLs.map(\.path).joined(separator: ", ")
            return managedItem(tool: tool, size: size, detail: "\(locations) · runs \(tool.commandDescription)")
        }
    }

    private func managedItem(tool: ManagedCleanupTool, size: Int64, detail: String) -> CleanupItem {
        CleanupItem(
            id: "tool:\(tool.rawValue)",
            url: fileManager.homeDirectoryForCurrentUser,
            category: tool.category,
            name: tool.title,
            detail: detail,
            size: size,
            modifiedAt: nil,
            risk: .irreversible,
            action: .runTool(tool),
            isSelected: false
        )
    }

    private func managedCacheURLs(for tool: ManagedCleanupTool) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates: [URL]
        switch tool {
        case .homebrew:
            candidates = [home.appending(path: "Library/Caches/Homebrew")]
        case .swiftPackageManager:
            candidates = [home.appending(path: "Library/Caches/org.swift.swiftpm"), home.appending(path: ".cache/org.swift.swiftpm")]
        case .cocoaPods:
            candidates = [home.appending(path: "Library/Caches/CocoaPods")]
        case .npm:
            let result = run(tool: tool, arguments: ["config", "get", "cache"])
            candidates = result.status == 0 ? validatedHomePaths(from: result.output) : [home.appending(path: ".npm")]
        case .yarn:
            let result = run(tool: tool, arguments: ["cache", "dir"])
            candidates = result.status == 0 ? validatedHomePaths(from: result.output) : [home.appending(path: "Library/Caches/Yarn")]
        case .docker, .unavailableSimulators:
            candidates = []
        }
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func validatedHomePaths(from output: String) -> [URL] {
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        return output
            .split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)).standardizedFileURL }
            .filter { $0.path == homePath || $0.path.hasPrefix(homePath + "/") }
    }

    private func executableURL(for tool: ManagedCleanupTool) -> URL? {
        tool.executableCandidates
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func run(tool: ManagedCleanupTool, arguments: [String]) -> (status: Int32, output: String) {
        guard let executable = executableURL(for: tool) else { return (127, "Executable not found") }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = fileManager.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data.prefix(32_768), as: UTF8.self)
            return (process.terminationStatus, output)
        } catch {
            return (126, error.localizedDescription)
        }
    }

    private func dockerReclaimableBytes(from output: String) -> Int64 {
        output.split(whereSeparator: \.isNewline).reduce(Int64(0)) { total, line in
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = json["Reclaimable"] as? String else { return total }
            return total + parseByteCount(value)
        }
    }

    private func unavailableSimulatorBytes(from output: String) -> Int64 {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else { return 0 }
        let devicesRoot = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Developer/CoreSimulator/Devices")
            .standardizedFileURL.path

        return runtimes.values.flatMap { $0 }.reduce(Int64(0)) { total, device in
            if let reportedSize = device["dataPathSize"] as? NSNumber {
                return total + reportedSize.int64Value
            }
            guard let dataPath = device["dataPath"] as? String else { return total }
            let url = URL(fileURLWithPath: dataPath).standardizedFileURL
            guard url.path.hasPrefix(devicesRoot + "/") else { return total }
            return total + inspect(url).size
        }
    }

    private func parseByteCount(_ value: String) -> Int64 {
        let token = value.split(separator: " ").first.map(String.init) ?? value
        let number = token.prefix { $0.isNumber || $0 == "." }
        let unit = token.dropFirst(number.count).lowercased()
        guard let amount = Double(number) else { return 0 }
        let multiplier: Double
        switch unit {
        case "kb", "kib": multiplier = 1_000
        case "mb", "mib": multiplier = 1_000_000
        case "gb", "gib": multiplier = 1_000_000_000
        case "tb", "tib": multiplier = 1_000_000_000_000
        default: multiplier = 1
        }
        return Int64(amount * multiplier)
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func isKnownRoot(_ url: URL, category: CleanupCategory) -> Bool {
        let candidate = url.standardizedFileURL.path
        return locations.contains {
            $0.category == category && $0.url.standardizedFileURL.path == candidate
        }
    }

    private func isAllowedFileItem(_ item: CleanupItem, installedBundleIDs: Set<String>) -> Bool {
        let candidate = item.url.standardizedFileURL.path
        return locations.contains { location in
            let root = location.url.standardizedFileURL.path
            return location.category == item.category
                && location.action == item.action
                && candidate.hasPrefix(root + "/")
                && matches(item.url, location: location, installedBundleIDs: installedBundleIDs)
                && makeItem(item.url, location: location, scanDate: now()) != nil
        }
    }
}

private enum CleanerError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(output):
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "The cleanup command failed." : message
        }
    }
}
