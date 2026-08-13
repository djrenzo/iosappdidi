import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
                .frame(width: 84, height: 84)
                .background(Theme.accentSoft, in: Circle())
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 60)
        // Without this, the VStack only claims its own narrow intrinsic width inside the
        // enclosing ScrollView (unlike the populated LazyVGrid case, which claims full width
        // to lay out columns) — leaving the margins on either side uncovered by the screen's
        // intended background color.
        .frame(maxWidth: .infinity)
    }
}
