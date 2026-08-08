import Foundation
import XCTest
@testable import DarwinCleaner

final class CleanerEngineTests: XCTestCase {
    @MainActor
    func testCategorySelectionCyclesThroughAllAndNone() {
        let viewModel = CleanerViewModel(engine: CleanerEngine(locations: []))
        viewModel.items = [
            CleanupItem(
                url: URL(fileURLWithPath: "/tmp/cache-a"),
                category: .caches,
                size: 1,
                modifiedAt: nil,
                isSelected: false
            ),
            CleanupItem(
                url: URL(fileURLWithPath: "/tmp/cache-b"),
                category: .caches,
                size: 1,
                modifiedAt: nil,
                isSelected: false
            ),
            CleanupItem(
                url: URL(fileURLWithPath: "/tmp/log"),
                category: .logs,
                size: 1,
                modifiedAt: nil,
                isSelected: false
            )
        ]

        viewModel.toggleSelection(for: .caches)
        XCTAssertEqual(viewModel.selectionState(for: .caches), .all)
        XCTAssertEqual(viewModel.selectionState(for: nil), .partial)

        viewModel.toggleSelection(for: .caches)
        XCTAssertEqual(viewModel.selectionState(for: .caches), .none)
    }

    func testScanIncludesOldFilesAndSkipsRecentFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let old = root.appending(path: "old.cache")
        let recent = root.appending(path: "recent.cache")
        try Data(repeating: 1, count: 1_024).write(to: old)
        try Data(repeating: 2, count: 512).write(to: recent)
        let reference = Date(timeIntervalSince1970: 2_000_000)
        try FileManager.default.setAttributes([.modificationDate: reference.addingTimeInterval(-200)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: reference.addingTimeInterval(-10)], ofItemAtPath: recent.path)

        let engine = CleanerEngine(
            now: { reference },
            locations: [ScanLocation(url: root, category: .caches, minimumAge: 100)]
        )
        let result = await engine.scan()

        XCTAssertEqual(result.items.map(\.displayName), ["old.cache"])
        XCTAssertGreaterThan(result.totalSize, 0)
    }

    func testScanDoesNotFollowSymbolicLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("protected".utf8).write(to: outside)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: outside)

        let engine = CleanerEngine(locations: [ScanLocation(url: root, category: .caches, minimumAge: 0)])
        let result = await engine.scan()

        XCTAssertTrue(result.items.isEmpty)
    }

    func testCleanupRejectsTheAllowlistRootItself() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = CleanerEngine(locations: [ScanLocation(url: root, category: .caches, minimumAge: 0)])
        let rootItem = CleanupItem(url: root, category: .caches, size: 0, modifiedAt: nil)
        let result = await engine.clean([rootItem])

        XCTAssertEqual(result.removedCount, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testDirectoryWithRecentNestedContentIsSkipped() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let directory = root.appending(path: "old-container")
        let nestedFile = directory.appending(path: "recent.cache")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("recent".utf8).write(to: nestedFile)
        defer { try? FileManager.default.removeItem(at: root) }

        let reference = Date(timeIntervalSince1970: 3_000_000)
        try FileManager.default.setAttributes([.modificationDate: reference.addingTimeInterval(-1_000)], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.modificationDate: reference.addingTimeInterval(-10)], ofItemAtPath: nestedFile.path)
        let engine = CleanerEngine(
            now: { reference },
            locations: [ScanLocation(url: root, category: .caches, minimumAge: 100)]
        )

        let result = await engine.scan()

        XCTAssertTrue(result.items.isEmpty)
    }

    func testInstallerFilteringAndReviewDefault() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = root.appending(path: "Example.dmg")
        let document = root.appending(path: "Notes.txt")
        try Data(repeating: 1, count: 64).write(to: installer)
        try Data(repeating: 1, count: 64).write(to: document)

        let engine = CleanerEngine(locations: [ScanLocation(
            url: root,
            category: .installers,
            minimumAge: 0,
            risk: .review,
            rule: .fileExtensions(["dmg", "pkg"])
        )])
        let result = await engine.scan()

        XCTAssertEqual(result.items.map(\.displayName), ["Example.dmg"])
        XCTAssertEqual(result.items.first?.risk, .review)
        XCTAssertEqual(result.items.first?.isSelected, false)
    }

    func testExcludedCacheNamesAndPrefixesAreNotSuggested() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in [".DS_Store", "com.apple.Safari", "CloudKit", "com.example.safe"] {
            try Data("cache".utf8).write(to: root.appending(path: name))
        }

        let engine = CleanerEngine(locations: [ScanLocation(
            url: root,
            category: .caches,
            minimumAge: 0,
            excludedNames: ["CloudKit"],
            excludedNamePrefixes: ["com.apple."]
        )])
        let result = await engine.scan()

        XCTAssertEqual(result.items.map(\.displayName), ["com.example.safe"])
    }

    func testLeftoversExcludeAppleAndInstalledBundleIdentifiers() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in [".DS_Store", "com.example.installed.plist", "com.example.orphan.plist", "com.apple.system.plist"] {
            try Data("value".utf8).write(to: root.appending(path: name))
        }

        let engine = CleanerEngine(
            locations: [ScanLocation(
                url: root,
                category: .leftovers,
                minimumAge: 0,
                risk: .review,
                rule: .orphanBundleIdentifier(removingSuffix: ".plist")
            )],
            installedBundleIDs: ["com.example.installed"]
        )
        let result = await engine.scan()

        XCTAssertEqual(result.items.map(\.displayName), ["com.example.orphan.plist"])
    }

    func testForgedManagedToolActionIsRejected() async {
        let engine = CleanerEngine(locations: [], includeManagedTools: false)
        var item = CleanupItem(
            id: "not-a-valid-tool-id",
            url: URL(fileURLWithPath: "/"),
            category: .packageManagers,
            size: 1,
            modifiedAt: nil,
            risk: .irreversible,
            action: .runTool(.homebrew)
        )
        item.isSelected = true

        let result = await engine.clean([item])

        XCTAssertEqual(result.removedCount, 0)
        XCTAssertEqual(result.failures.count, 1)
    }
}
