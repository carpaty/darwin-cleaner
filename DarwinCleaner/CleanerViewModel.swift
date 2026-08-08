import AppKit
import Combine
import Foundation

@MainActor
final class CleanerViewModel: ObservableObject {
    enum SelectionState: Equatable {
        case none
        case partial
        case all

        var symbol: String {
            switch self {
            case .none: "square"
            case .partial: "minus.square.fill"
            case .all: "checkmark.square.fill"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case cleaning
    }

    @Published var phase: Phase = .idle
    @Published var items: [CleanupItem] = []
    @Published var inaccessiblePaths: [String] = []
    @Published var lastCleanup: CleanupResult?
    @Published var alertMessage: String?
    @Published var failureDetails: String?
    @Published var selectedCategory: CleanupCategory?

    private let engine: CleanerEngine

    init(engine: CleanerEngine = CleanerEngine()) {
        self.engine = engine
    }

    var isBusy: Bool { phase == .scanning || phase == .cleaning }
    var visibleItems: [CleanupItem] {
        guard let selectedCategory else { return items }
        return items.filter { $0.category == selectedCategory }
    }
    var selectedItems: [CleanupItem] { items.filter(\.isSelected) }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var selectionContainsIrreversibleItems: Bool {
        selectedItems.contains { $0.risk == .irreversible }
    }

    func scan() {
        guard !isBusy else { return }
        phase = .scanning
        lastCleanup = nil
        failureDetails = nil
        Task {
            let summary = await engine.scan()
            items = summary.items
            inaccessiblePaths = summary.inaccessiblePaths
            phase = .ready
        }
    }

    func cleanSelected() {
        let selection = selectedItems
        guard !selection.isEmpty, !isBusy else { return }
        phase = .cleaning
        Task {
            let result = await engine.clean(selection)
            lastCleanup = result
            items.removeAll { result.removedIDs.contains($0.id) }
            phase = .ready
            if !result.failures.isEmpty {
                failureDetails = result.failures.joined(separator: "\n")
                let preview = result.failures.prefix(3).joined(separator: "\n")
                let remaining = result.failures.count - min(result.failures.count, 3)
                alertMessage = remaining > 0
                    ? "\(preview)\n…and \(remaining) more. Use Copy Details for the complete report."
                    : preview
            }
        }
    }

    func setSelection(_ selected: Bool, category: CleanupCategory? = nil) {
        for index in items.indices where category == nil || items[index].category == category {
            items[index].isSelected = selected
        }
    }

    func selectionState(for category: CleanupCategory? = nil) -> SelectionState {
        let candidates = items.filter { category == nil || $0.category == category }
        guard !candidates.isEmpty else { return .none }
        let selectedCount = candidates.filter(\.isSelected).count
        if selectedCount == 0 { return .none }
        if selectedCount == candidates.count { return .all }
        return .partial
    }

    func toggleSelection(for category: CleanupCategory? = nil) {
        let shouldSelect = selectionState(for: category) != .all
        setSelection(shouldSelect, category: category)
    }

    func toggle(_ id: CleanupItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isSelected.toggle()
    }

    func reveal(_ item: CleanupItem) {
        guard item.canRevealInFinder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyFailureDetails() {
        guard let failureDetails else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(failureDetails, forType: .string)
    }
}
