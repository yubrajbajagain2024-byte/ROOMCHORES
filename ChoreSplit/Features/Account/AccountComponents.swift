import SwiftUI

/// The lowercase wordmark used on every signed-out screen.
struct Wordmark: View {
    var size: CGFloat = 30

    var body: some View {
        Text("choresplit")
            .font(.system(size: size, weight: .heavy))
            .tracking(-size * 0.04)
            .foregroundStyle(Theme.brand)
            .accessibilityLabel("ChoreSplit")
    }
}

/// Full-width filled button in the brand colour.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isWorking = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.brand.opacity(isEnabled ? 1 : 0.35))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isWorking)
    }
}

/// Full-width outlined button.
struct SecondaryButton<Icon: View>: View {
    let title: String
    let icon: Icon
    var isEnabled = true
    let action: () -> Void

    init(title: String, isEnabled: Bool = true, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.feedCard))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

extension SecondaryButton where Icon == EmptyView {
    init(title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.init(title: title, isEnabled: isEnabled, action: action) { EmptyView() }
    }
}

/// A multicolour "G" for the Google button. Drawn rather than bundled, so no brand asset ships
/// with the app.
struct GoogleGlyph: View {
    var body: some View {
        Text("G")
            .font(.system(size: 21, weight: .bold, design: .rounded))
            .foregroundStyle(
                AngularGradient(
                    colors: [Color(red: 0.92, green: 0.26, blue: 0.21), Color(red: 0.98, green: 0.74, blue: 0.02),
                             Color(red: 0.20, green: 0.66, blue: 0.33), Color(red: 0.26, green: 0.52, blue: 0.96),
                             Color(red: 0.92, green: 0.26, blue: 0.21)],
                    center: .center
                )
            )
            .accessibilityHidden(true)
    }
}

/// A text field styled for the signed-out screens.
struct PillField<Field: View>: View {
    let field: Field

    init(@ViewBuilder field: () -> Field) {
        self.field = field()
    }

    var body: some View {
        field
            .font(.system(size: 18))
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chipFill))
    }
}

struct ErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.rose)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
    }
}
