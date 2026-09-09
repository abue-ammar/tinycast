import SwiftUI

private struct LocalizationEnvironment: ViewModifier {
    @State private var locale = AppLocalization.locale

    func body(content: Content) -> some View {
        content
            .environment(\.locale, locale)
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                locale = AppLocalization.locale
            }
    }
}

extension View {
    func localizationEnvironment() -> some View {
        modifier(LocalizationEnvironment())
    }
}
