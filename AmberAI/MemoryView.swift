//
//  MemoryView.swift
//  AmberAI
//
//  What Amber knows, where it came from, and the ability to forget any of it. Forgetting
//  a fact doesn't hide it — it sinks to a "Recently Deleted" group at the bottom of the
//  list, struck through, where you can watch it sit, restore it, or erase it for good.
//  Either way it stops reaching the model everywhere else the moment it's forgotten.
//
//  The list is filterable by category — with Recently Deleted as its own chip alongside
//  the categories — and searchable by content, so a long memory stays easy to navigate.
//

import SwiftUI

/// The filter-bar selection: a category, the recently-deleted pile, or nil for "All".
private enum MemorySelection: Hashable {
    case type(FactType)
    case deleted
}

struct MemoryView: View {
    @EnvironmentObject var app: AppState

    @State private var selection: MemorySelection? = nil
    @State private var searchText = ""

    private let order: [FactType] = [.medication, .clinicalInstruction, .symptom, .struggle, .personal]

    /// Live facts (tombstones removed) after the search filter.
    private var searchedActive: [MemoryFact] {
        app.displayedFacts.filter { $0.forgotten != true }.filter(matchesSearch)
    }

    /// Forgotten facts after the search filter — the Recently Deleted pile.
    private var searchedDeleted: [MemoryFact] {
        app.recentlyDeletedFacts.filter(matchesSearch)
    }

    private func matchesSearch(_ fact: MemoryFact) -> Bool {
        searchText.isEmpty || fact.content.localizedCaseInsensitiveContains(searchText)
    }

    /// Categories present in the live facts, in display order. Kept independent of the
    /// search so the filter bar doesn't jump around as you type.
    private var availableTypes: [FactType] {
        let active = app.displayedFacts.filter { $0.forgotten != true }
        return order.filter { type in active.contains { $0.type == type } }
    }

    /// Whether a given category section should render under the current selection.
    private func showsType(_ type: FactType) -> Bool {
        selection == nil || selection == .type(type)
    }

    private var showsDeleted: Bool {
        selection == nil || selection == .deleted
    }

    /// Total rows on screen, for the empty state.
    private var renderedCount: Int {
        let active = searchedActive.filter { showsType($0.type) }.count
        return active + (showsDeleted ? searchedDeleted.count : 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if !app.activeConsolidations.isEmpty {
                        consolidationBanner
                    }

                    if !availableTypes.isEmpty || !app.recentlyDeletedFacts.isEmpty {
                        filterBar
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(order, id: \.self) { type in
                            let facts = showsType(type) ? searchedActive.filter { $0.type == type } : []
                            if !facts.isEmpty {
                                section(type: type, facts: facts)
                            }
                        }

                        if showsDeleted && !searchedDeleted.isEmpty {
                            deletedSection(searchedDeleted)
                        }
                    }

                    emptyState
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Memory")
            .searchable(text: $searchText, prompt: "Search what Amber knows")
            .animation(.easeInOut(duration: 0.2), value: selection)
            .animation(.easeInOut(duration: 0.2), value: searchText)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("As of week \(app.week), Amber knows \(app.knownCount) things about \(Patient.firstName).")
                .font(.subheadline.weight(.medium))
            if app.consentCost > 0 {
                Label("\(app.consentCost) withheld from the model by his consent choices.",
                      systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(Theme.support)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Consolidation banner

    /// Shows what Amber has folded into shorthand for her own working memory. The detailed
    /// entries below are untouched — this is the gist she carries, not a deletion.
    private var consolidationBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Earlier weeks, in Amber's shorthand", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.amber)
            ForEach(app.activeConsolidations) { c in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: c.type.icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(c.type.tint)
                        .frame(width: 16)
                    Text(c.content)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("The detailed entries are still below — it just doesn't carry every one into each chat.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amberSoft.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amberSoft.opacity(0.5)))
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "All",
                    icon: "square.grid.2x2",
                    count: searchedActive.count,
                    color: Theme.ink,
                    isSelected: selection == nil
                ) { selection = nil }

                ForEach(availableTypes, id: \.self) { type in
                    FilterChip(
                        label: type.display,
                        icon: type.icon,
                        count: searchedActive.filter { $0.type == type }.count,
                        color: type.tint,
                        isSelected: selection == .type(type)
                    ) { selection = selection == .type(type) ? nil : .type(type) }
                }

                if !app.recentlyDeletedFacts.isEmpty {
                    FilterChip(
                        label: "Recently Deleted",
                        icon: "trash",
                        count: searchedDeleted.count,
                        color: Theme.support,
                        isSelected: selection == .deleted
                    ) { selection = selection == .deleted ? nil : .deleted }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Sections

    private func section(type: FactType, facts: [MemoryFact]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.caption2.weight(.bold))
                Text(type.display.uppercased())
                    .font(.caption.weight(.bold))
                Spacer()
                Text("\(facts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(type.tint.opacity(0.7))
            }
            .foregroundStyle(type.tint)

            ForEach(facts) { fact in
                factRow(fact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The Recently Deleted group, pinned below every category. Every fact here is
    /// tombstoned, so it's already out of Amber's context — this is where you restore it
    /// or erase it for good.
    private func deletedSection(_ facts: [MemoryFact]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.caption2.weight(.bold))
                Text("RECENTLY DELETED")
                    .font(.caption.weight(.bold))
                Spacer()
                Text("\(facts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.support.opacity(0.7))
            }
            .foregroundStyle(Theme.support)

            Text("Not used for context. Restore to bring it back, or delete permanently to erase it.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(facts) { fact in
                factRow(fact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func factRow(_ fact: MemoryFact) -> some View {
        let forgotten = fact.forgotten == true
        let isNew = app.lastAddedFactIds.contains(fact.id)
        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(fact.type.tint.opacity(forgotten ? 0.08 : 0.15))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: fact.type.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(fact.type.tint.opacity(forgotten ? 0.5 : 1))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(fact.content)
                    .font(.subheadline)
                    .strikethrough(forgotten, color: .secondary)
                    .foregroundStyle(forgotten ? .secondary : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Tag(text: "week \(fact.weekLearned)", color: fact.type.tint)
                    Tag(text: fact.source.display, color: .gray)
                    if isNew { Tag(text: "just now", color: Theme.amber) }
                }
            }

            rowActions(fact, forgotten: forgotten)
        }
        .padding(12)
        .background(isNew ? Theme.amberSoft.opacity(0.25) : Color.white,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amberSoft.opacity(0.4)))
    }

    /// Forget (a live fact) versus restore-or-erase (a recently-deleted one).
    @ViewBuilder
    private func rowActions(_ fact: MemoryFact, forgotten: Bool) -> some View {
        if forgotten {
            VStack(spacing: 14) {
                Button {
                    withAnimation { app.unforget(fact.id) }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.steady)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restore")

                Button {
                    withAnimation { app.permanentlyDelete(fact.id) }
                } label: {
                    Image(systemName: "trash.slash")
                        .font(.subheadline)
                        .foregroundStyle(Theme.support)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete permanently")
            }
        } else {
            Button {
                withAnimation { app.forget(fact.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(Theme.support)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forget")
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        if app.displayedFacts.isEmpty {
            emptyMessage(
                icon: "clock.arrow.circlepath",
                text: "Amber has never spoken to him before. Scrub forward to week 1 or later.")
        } else if renderedCount == 0 {
            emptyMessage(
                icon: "magnifyingglass",
                text: searchText.isEmpty
                    ? "Nothing in this filter yet."
                    : "No memories match “\(searchText)”.")
        }
    }

    private func emptyMessage(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Theme.amberSoft)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// A selectable pill for the memory category filter bar.
private struct FilterChip: View {
    let label: String
    let icon: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.medium))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        (isSelected ? Color.white.opacity(0.35) : color.opacity(0.15)),
                        in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : color)
            .background(
                isSelected ? color : color.opacity(0.10),
                in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
