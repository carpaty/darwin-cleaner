import SwiftUI

struct ContentView: View {
    private enum ItemSort: String, CaseIterable, Identifiable {
        case nameAscending
        case nameDescending
        case sizeDescending

        var id: String { rawValue }
        var title: String {
            switch self {
            case .nameAscending: "Name: A–Z"
            case .nameDescending: "Name: Z–A"
            case .sizeDescending: "Largest First"
            }
        }
    }

    @EnvironmentObject private var cleaner: CleanerViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var showingCleanupConfirmation = false
    @State private var searchText = ""
    @State private var itemSort: ItemSort = .nameAscending

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                content
                Divider()
                footer
            }
            .navigationTitle(cleaner.selectedCategory?.title ?? "Smart Scan")
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search by name")
        .alert("Cleanup Incomplete", isPresented: Binding(
            get: { cleaner.alertMessage != nil },
            set: { if !$0 { cleaner.alertMessage = nil } }
        )) {
            if cleaner.failureDetails != nil {
                Button("Copy Details") { cleaner.copyFailureDetails() }
            }
            Button("OK", role: .cancel) { cleaner.alertMessage = nil }
        } message: {
            Text(cleaner.alertMessage ?? "")
        }
        .confirmationDialog(
            cleaner.selectionContainsIrreversibleItems ? "Clean selected items?" : "Move selected items to Trash?",
            isPresented: $showingCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean \(cleaner.selectedSize.formattedBytes)", role: .destructive) {
                cleaner.cleanSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cleaner.selectionContainsIrreversibleItems
                 ? "This selection contains permanent or tool-managed cleanup actions that cannot be restored from Trash."
                 : "Selected items are moved to Trash and can be restored.")
        }
        .task {
            AppController.shared.install(openWindowAction: openWindow)
            if cleaner.phase == .idle { cleaner.scan() }
        }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { cleaner.selectedCategory },
            set: { cleaner.selectedCategory = $0 }
        )) {
            sidebarRow(
                title: "Smart Scan",
                symbol: "sparkles",
                size: cleaner.items.reduce(0) { $0 + $1.size },
                category: nil
            )
                .tag(nil as CleanupCategory?)
            Section("Categories") {
                ForEach(CleanupCategory.allCases) { category in
                    sidebarRow(
                        title: category.title,
                        symbol: category.symbol,
                        size: categorySize(category),
                        category: category
                    )
                    .tag(category as CleanupCategory?)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }

    private func sidebarRow(
        title: String,
        symbol: String,
        size: Int64,
        category: CleanupCategory?
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                cleaner.toggleSelection(for: category)
            } label: {
                Image(systemName: cleaner.selectionState(for: category).symbol)
                    .foregroundStyle(categorySelectionColor(category))
            }
            .buttonStyle(.plain)
            .disabled(itemsCount(category) == 0)
            .help("Select or deselect all items in \(title)")

            Label(title, systemImage: symbol)
            Spacer()
            Text(size.formattedBytes)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(cleaner.selectedCategory?.explanation ?? "Review safe-to-clean files before removing anything.")
                    .foregroundStyle(.secondary)
                if !cleaner.inaccessiblePaths.isEmpty {
                    Label("Some folders require additional privacy permissions.", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Picker("Sort", selection: $itemSort) {
                ForEach(ItemSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 145)
            Button {
                cleaner.scan()
            } label: {
                Label("Scan", systemImage: "arrow.clockwise")
            }
            .disabled(cleaner.isBusy)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if cleaner.phase == .scanning {
            ContentUnavailableView {
                Label("Scanning…", systemImage: "magnifyingglass")
            } description: {
                ProgressView().controlSize(.small)
            }
        } else if cleaner.visibleItems.isEmpty {
            ContentUnavailableView(
                "Nothing to Clean",
                systemImage: "checkmark.circle",
                description: Text("No eligible files were found in this category.")
            )
        } else if displayedItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(displayedItems) { item in
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { cleaner.items.first(where: { $0.id == item.id })?.isSelected ?? false },
                        set: { _ in cleaner.toggle(item.id) }
                    ))
                    .labelsHidden()
                    Image(systemName: item.category.symbol)
                        .frame(width: 24)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName).lineLimit(1)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(item.size.formattedBytes)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Label(item.risk.title, systemImage: item.risk.symbol)
                            .font(.caption2)
                            .foregroundStyle(riskColor(item.risk))
                    }
                }
                .contextMenu {
                    if item.canRevealInFinder {
                        Button("Show in Finder") { cleaner.reveal(item) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Select All") { cleaner.setSelection(true, category: cleaner.selectedCategory) }
            Button("Select None") { cleaner.setSelection(false, category: cleaner.selectedCategory) }
            Spacer()
            Text("\(cleaner.selectedItems.count) selected · \(cleaner.selectedSize.formattedBytes)")
                .foregroundStyle(.secondary)
            Button {
                showingCleanupConfirmation = true
            } label: {
                if cleaner.phase == .cleaning {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Clean")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(cleaner.selectedItems.isEmpty || cleaner.isBusy)
        }
        .padding()
    }

    private func categorySize(_ category: CleanupCategory) -> Int64 {
        cleaner.items.filter { $0.category == category }.reduce(0) { $0 + $1.size }
    }

    private var displayedItems: [CleanupItem] {
        let filtered = searchText.isEmpty
            ? cleaner.visibleItems
            : cleaner.visibleItems.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        return filtered.sorted { lhs, rhs in
            switch itemSort {
            case .nameAscending:
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            case .nameDescending:
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedDescending
            case .sizeDescending:
                lhs.size == rhs.size
                    ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                    : lhs.size > rhs.size
            }
        }
    }

    private func itemsCount(_ category: CleanupCategory?) -> Int {
        guard let category else { return cleaner.items.count }
        return cleaner.items.filter { $0.category == category }.count
    }

    private func categorySelectionColor(_ category: CleanupCategory?) -> Color {
        cleaner.selectionState(for: category) == .none ? .secondary : .accentColor
    }

    private func riskColor(_ risk: CleanupRisk) -> Color {
        switch risk {
        case .recommended: .green
        case .review: .orange
        case .irreversible: .red
        }
    }
}
