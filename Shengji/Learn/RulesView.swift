import SwiftUI
import ShengjiCore

/// The Rules tab: a searchable quick reference with card examples and a glossary (中文 + pinyin).
@MainActor
struct RulesView: View {
    @State private var query = ""

    private var sections: [RuleSection] {
        RulesContent.filtered(RulesContent.sections, query: query)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if query.isEmpty {
                            jumpBar(proxy)
                        }
                        ForEach(sections) { section in
                            RuleSectionView(section: section)
                                .id(section.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .overlay {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Rules")
            .searchable(text: $query, prompt: "Search rules and terms")
        }
    }

    private func jumpBar(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(RulesContent.sections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(section.id, anchor: .top)
                        }
                    } label: {
                        Label(section.shortTitle, systemImage: section.symbol)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}

/// One rules section as a card.
@MainActor
private struct RuleSectionView: View {
    let section: RuleSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(section.title, systemImage: section.symbol)
                .font(.title3.weight(.bold))
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                RuleBlockView(block: block)
            }
        }
        .learnCard()
    }
}

@MainActor
private struct RuleBlockView: View {
    let block: RuleBlock

    var body: some View {
        switch block {
        case let .text(text):
            RichText(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullets(items):
            LearnBulletList(items: items)
                .font(.subheadline)
        case let .cards(caption, cards, trump):
            RuleCardsView(caption: caption, cards: cards, trump: trump)
        case let .trick(caption, plays, trump, winner):
            VStack(alignment: .leading, spacing: 8) {
                TrumpBadge(trump: trump, compact: true)
                TrickDiagram(plays: plays, trump: trump, winner: winner, markTrumps: true, cardWidth: 30)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .table(header, rows):
            RuleTableView(header: header, rows: rows)
        case let .glossary(entries):
            GlossaryList(entries: entries)
        }
    }
}

/// A mini card example with its caption.
@MainActor
private struct RuleCardsView: View {
    let caption: String
    let cards: [Card]
    let trump: Trump?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let trump {
                TrumpBadge(trump: trump, compact: true)
            }
            CardRow(cards: cards, cardWidth: 38, spacing: cards.count > 5 ? -14 : -6,
                    trump: trump, markTrumps: trump != nil)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// Two-column table, e.g. the scoring table.
@MainActor
private struct RuleTableView: View {
    let header: RuleTableRow
    let rows: [RuleTableRow]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text(header.left)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(header.right)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Divider()
            ForEach(rows, id: \.self) { row in
                GridRow {
                    Text(row.left)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(row.right)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Chinese terms with pinyin and meaning.
@MainActor
private struct GlossaryList: View {
    let entries: [GlossaryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Text(entry.chinese)
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(entry.english)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.pinyin)
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.meaning)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
