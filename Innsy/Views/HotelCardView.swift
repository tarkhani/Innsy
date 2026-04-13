//
//  HotelCardView.swift
//  Innsy
//

import SwiftUI

struct HotelCardView: View {
    let card: HotelOfferCard
    var onBook: () -> Void
    var ctaTitle: String = "Continue to booking"
    private let maxPreviewTags = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.orange.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 190)
                    .overlay {
                        if let url = card.imageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Color.gray.opacity(0.12)
                                        .overlay {
                                            Image(systemName: "photo")
                                                .foregroundStyle(.tertiary)
                                        }
                                default:
                                    Color.gray.opacity(0.12)
                                        .overlay { ProgressView() }
                                }
                            }
                            .id(url.absoluteString)
                            .clipped()
                        }
                    }
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.22)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let cat = card.categoryLabel {
                    Text(cat)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(card.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                Text(card.destinationLine)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    if let price = card.fromPrice, let cur = card.currency {
                        Text("\(cur) \(price)")
                            .font(.headline.weight(.semibold))
                    }
                    if let board = card.boardName {
                        Label(board, systemImage: "fork.knife")
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if card.displayMatchesOrdered.isEmpty == false {
                    TagSection(
                        title: "Matches",
                        tags: card.displayMatchesOrdered,
                        maxTags: maxPreviewTags,
                        highlightAllTags: true
                    )
                }

                if card.mergedAmenitiesDisplayOrdered.isEmpty == false {
                    TagSection(
                        title: "Amenities",
                        tags: card.mergedAmenitiesDisplayOrdered,
                        maxTags: maxPreviewTags
                    )
                }

                if card.wantedFacilityLabelsMissing.isEmpty == false {
                    TagSection(
                        title: "Not available (you might be interested in)",
                        tags: card.wantedFacilityLabelsMissing,
                        maxTags: 12,
                        forceRed: true
                    )
                }

                if let rt = card.rateType {
                    Text(rt == "RECHECK" ? "Rate requires re-check before booking" : "Ready to book")
                        .font(.caption)
                        .foregroundStyle(rt == "RECHECK" ? .orange : .green)
                }

                Button(action: onBook) {
                    Text(ctaTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.36))
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
    }
}

private struct TagSection: View {
    let title: String
    let tags: [String]
    let maxTags: Int
    /// When non-empty, facility tags whose lowercase label is in this set render as yellow match chips.
    var goldLabelsLowercased: Set<String> = []
    /// When true, every chip uses yellow match styling (e.g. preference “Matches” section).
    var highlightAllTags: Bool = false
    /// When true, every chip uses red emphasis (missing requested facilities).
    var forceRed: Bool = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(sectionTitleColor)
            ChipFlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(visibleTags, id: \.self) { tag in
                    AmenityChip(
                        title: tag,
                        style: chipStyle(for: tag)
                    )
                }
                if tags.count > maxTags, isExpanded == false {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = true
                        }
                    } label: {
                        AmenityChip(title: "+\(tags.count - maxTags) more", style: .neutral)
                    }
                    .buttonStyle(.plain)
                }
                if tags.count > maxTags, isExpanded {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = false
                        }
                    } label: {
                        AmenityChip(title: "Show less", style: .neutral)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var visibleTags: [String] {
        isExpanded ? tags : Array(tags.prefix(maxTags))
    }

    private var sectionTitleColor: Color {
        if forceRed { return Color(red: 0.95, green: 0.45, blue: 0.42) }
        // Amber/brown so “Matches” reads as the same family as yellow chips.
        if highlightAllTags { return Color(red: 0.58, green: 0.45, blue: 0.05) }
        return .secondary
    }

    private func chipStyle(for tag: String) -> AmenityChip.Style {
        if forceRed { return .red }
        if highlightAllTags { return .matchHighlight }
        if goldLabelsLowercased.contains(tag.lowercased()) { return .matchHighlight }
        return .neutral
    }
}

private struct AmenityChip: View {
    enum Style {
        case neutral
        /// Requested facility present on this hotel — high-contrast yellow (distinct from neutral chips).
        case matchHighlight
        case red
    }

    let title: String
    var style: Style = .neutral

    private static let redAccent = Color(red: 0.92, green: 0.38, blue: 0.38)
    /// Fill behind chip (readable on light and dark materials).
    private static let matchYellowFill = Color(red: 1.0, green: 0.88, blue: 0.2)
    private static let matchYellowBorder = Color(red: 0.95, green: 0.72, blue: 0.05)
    private static let matchYellowText = Color(red: 0.22, green: 0.16, blue: 0.02)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: title))
                .font(.caption)
                .foregroundStyle(iconColor)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: style == .neutral ? 0.8 : (style == .matchHighlight ? 1.5 : 1.25))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconColor: Color {
        switch style {
        case .neutral: return .secondary
        case .matchHighlight: return Self.matchYellowBorder
        case .red: return Self.redAccent
        }
    }

    private var textColor: Color {
        switch style {
        case .neutral: return .primary
        case .matchHighlight: return Self.matchYellowText
        case .red: return Color(red: 1, green: 0.88, blue: 0.88)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .neutral: return Color.white.opacity(0.07)
        case .matchHighlight: return Self.matchYellowFill.opacity(0.42)
        case .red: return Self.redAccent.opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch style {
        case .neutral: return Color.white.opacity(0.15)
        case .matchHighlight: return Self.matchYellowBorder
        case .red: return Self.redAccent.opacity(0.95)
        }
    }

    private func iconName(for value: String) -> String {
        let v = value.lowercased()
        if v.contains("wifi") || v.contains("wi-fi") || v.contains("internet") { return "wifi" }
        if v.contains("breakfast") { return "cup.and.saucer" }
        if v.contains("restaurant") || v.contains("dining") { return "fork.knife" }
        if v.contains("parking") { return "parkingsign.circle" }
        if v.contains("gym") || v.contains("fitness") { return "dumbbell" }
        if v.contains("pool") || v.contains("swimming") { return "figure.pool.swim" }
        if v.contains("pet") { return "pawprint" }
        if v.contains("bath") || v.contains("shower") { return "shower" }
        if v.contains("accessible") || v.contains("disabled") { return "figure.roll" }
        return "checkmark.seal"
    }
}

private struct ChipFlowLayout<Content: View>: View {
    let spacing: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: spacing, rowSpacing: rowSpacing) {
            content()
        }
    }
}

/// Stable wrapping layout that avoids GeometryReader height glitches in scroll views.
private struct FlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    init(spacing: CGFloat = 8, rowSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0, x + size.width > maxWidth {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        maxLineWidth = max(maxLineWidth, max(0, x - spacing))
        let totalHeight = subviews.isEmpty ? 0 : (y + rowHeight)
        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
