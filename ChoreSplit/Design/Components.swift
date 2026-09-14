import SwiftUI

// MARK: - Avatar

struct AvatarView: View {
    let roommate: Roommate
    var size: CGFloat = 40
    var showsRing: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(roommate.color.gradient)
            Text(roommate.emoji)
                .font(.system(size: size * 0.5))
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(showsRing ? Color.accentColor : .clear, lineWidth: 2.5)
                .padding(-3)
        )
        .accessibilityLabel(roommate.name)
    }
}

// MARK: - Points

struct PointsBadge: View {
    let points: Double
    var provisional: Bool = false
    var size: Size = .regular
    var tint: Color = Theme.indigo

    enum Size { case small, regular, large }

    private var fontStyle: Font {
        switch size {
        case .small:   return .caption.weight(.semibold)
        case .regular: return .subheadline.weight(.semibold)
        case .large:   return .title3.weight(.bold)
        }
    }

    private var text: String {
        let rounded = (points * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
            Text("pts").font(.caption2.weight(.medium)).opacity(0.75)
        }
        .font(fontStyle)
        .foregroundStyle(tint)
        .padding(.horizontal, size == .small ? 7 : 9)
        .padding(.vertical, size == .small ? 3 : 5)
        .background(
            Capsule().fill(tint.opacity(0.13))
        )
        .overlay(
            // A dashed edge marks points that peer ratings could still move.
            Capsule()
                .strokeBorder(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .opacity(provisional ? 1 : 0)
        )
        .accessibilityLabel("\(text) points\(provisional ? ", not final yet" : "")")
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    let category: ChoreCategory

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbol).font(.caption2)
            Text(category.label).font(.caption.weight(.medium))
        }
        .foregroundStyle(category.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(category.tint.opacity(0.13)))
    }
}

// MARK: - Rating input

/// A 1–5 scale with the ends named, because "3 out of 5" means nothing on its own.
struct ScaleSlider: View {
    let title: String
    let lowLabel: String
    let highLabel: String
    var symbol: String
    var tint: Color = Theme.indigo
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(value)/5")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { step in
                    Button {
                        value = step
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(step <= value ? tint : tint.opacity(0.15))
                            .frame(height: 30)
                            .overlay(
                                Text("\(step)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(step <= value ? .white : Color.secondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(step) of 5")
                }
            }

            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Balance bar

/// Load against fair share. The marker is the target, so "past the line" reads instantly.
struct BalanceBar: View {
    let percentOfTarget: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let capped = min(1.4, max(0, percentOfTarget))
            let targetX = geo.size.width / 1.4
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(Theme.balanceColor(percentOfTarget: percentOfTarget).gradient)
                    .frame(width: max(height, geo.size.width * (capped / 1.4)))
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1.5)
                    .offset(x: targetX)
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(Int(percentOfTarget * 100)) percent of fair share")
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.indigo.opacity(0.55))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 28)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
