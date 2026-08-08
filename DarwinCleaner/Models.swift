import Foundation

enum CleanupCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case caches
    case logs
    case trash
    case developer
    case installers
    case backups
    case packageManagers
    case containers
    case leftovers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: "Caches"
        case .logs: "Logs"
        case .trash: "Trash"
        case .developer: "Developer Files"
        case .installers: "Installers"
        case .backups: "Device Backups"
        case .packageManagers: "Package Managers"
        case .containers: "Docker"
        case .leftovers: "App Leftovers"
        }
    }

    var explanation: String {
        switch self {
        case .caches: "Regenerable app caches that have not changed recently."
        case .logs: "Diagnostic logs older than the retention period."
        case .trash: "Items that have already been in Trash for at least 30 days."
        case .developer: "Xcode build data, archives, documentation and simulator caches."
        case .installers: "Old DMG, PKG, ZIP, XIP and macOS installer applications."
        case .backups: "Local iPhone and iPad backups. Review carefully before removal."
        case .packageManagers: "Caches owned by developer package managers."
        case .containers: "Unused Docker data, cleaned through the Docker CLI."
        case .leftovers: "Possible data left by uninstalled apps. These are never preselected."
        }
    }

    var symbol: String {
        switch self {
        case .caches: "shippingbox"
        case .logs: "doc.text.magnifyingglass"
        case .trash: "trash"
        case .developer: "hammer"
        case .installers: "externaldrive.badge.xmark"
        case .backups: "iphone.and.arrow.forward.outward"
        case .packageManagers: "shippingbox.and.arrow.backward"
        case .containers: "cube.transparent"
        case .leftovers: "app.dashed"
        }
    }
}

enum CleanupRisk: String, Hashable, Sendable {
    case recommended
    case review
    case irreversible

    var title: String {
        switch self {
        case .recommended: "Recommended"
        case .review: "Review"
        case .irreversible: "Not recoverable"
        }
    }

    var symbol: String {
        switch self {
        case .recommended: "checkmark.shield"
        case .review: "eye"
        case .irreversible: "exclamationmark.triangle"
        }
    }
}

enum ManagedCleanupTool: String, CaseIterable, Hashable, Sendable {
    case homebrew
    case swiftPackageManager
    case cocoaPods
    case npm
    case yarn
    case docker
    case unavailableSimulators

    var title: String {
        switch self {
        case .homebrew: "Homebrew cleanup"
        case .swiftPackageManager: "SwiftPM repository cache"
        case .cocoaPods: "CocoaPods cache"
        case .npm: "npm cache"
        case .yarn: "Yarn cache"
        case .docker: "Unused Docker data"
        case .unavailableSimulators: "Unavailable Xcode simulators"
        }
    }

    var category: CleanupCategory {
        switch self {
        case .docker: .containers
        case .unavailableSimulators: .developer
        default: .packageManagers
        }
    }

    var executableCandidates: [String] {
        switch self {
        case .homebrew: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        case .swiftPackageManager: ["/usr/bin/swift"]
        case .cocoaPods: ["/opt/homebrew/bin/pod", "/usr/local/bin/pod"]
        case .npm: ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", "/usr/bin/npm"]
        case .yarn: ["/opt/homebrew/bin/yarn", "/usr/local/bin/yarn"]
        case .docker: ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"]
        case .unavailableSimulators: ["/usr/bin/xcrun"]
        }
    }

    var cleanupArguments: [String] {
        switch self {
        case .homebrew: ["cleanup", "--prune=30"]
        case .swiftPackageManager: ["package", "purge-cache"]
        case .cocoaPods: ["cache", "clean", "--all"]
        case .npm: ["cache", "clean", "--force"]
        case .yarn: ["cache", "clean"]
        case .docker: ["system", "prune", "--force"]
        case .unavailableSimulators: ["simctl", "delete", "unavailable"]
        }
    }

    var commandDescription: String {
        ([executableCandidates.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? rawValue] + cleanupArguments)
            .joined(separator: " ")
    }
}

enum CleanupAction: Hashable, Sendable {
    case moveToTrash
    case permanentDelete
    case runTool(ManagedCleanupTool)
}

struct CleanupItem: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let category: CleanupCategory
    let name: String
    let detail: String
    let size: Int64
    let modifiedAt: Date?
    let risk: CleanupRisk
    let action: CleanupAction
    var isSelected: Bool

    init(
        id: String? = nil,
        url: URL,
        category: CleanupCategory,
        name: String? = nil,
        detail: String? = nil,
        size: Int64,
        modifiedAt: Date?,
        risk: CleanupRisk = .recommended,
        action: CleanupAction = .moveToTrash,
        isSelected: Bool? = nil
    ) {
        self.id = id ?? url.standardizedFileURL.path
        self.url = url
        self.category = category
        self.name = name ?? url.lastPathComponent
        self.detail = detail ?? url.deletingLastPathComponent().path
        self.size = size
        self.modifiedAt = modifiedAt
        self.risk = risk
        self.action = action
        self.isSelected = isSelected ?? (risk == .recommended)
    }

    var displayName: String { name }
    var canRevealInFinder: Bool {
        if case .runTool = action { return false }
        return true
    }
}

struct ScanSummary: Sendable {
    var items: [CleanupItem] = []
    var inaccessiblePaths: [String] = []
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct CleanupResult: Sendable {
    var removedCount = 0
    var reclaimedBytes: Int64 = 0
    var removedIDs: Set<String> = []
    var failures: [String] = []
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
