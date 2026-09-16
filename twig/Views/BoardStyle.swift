import SwiftUI

enum BoardStyle {
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.10, green: 0.10, blue: 0.12) : .white
    }
    static func wash(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.035) : Color(red: 0.978, green: 0.978, blue: 0.985)
    }
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.91, green: 0.91, blue: 0.93) : Color(red: 0.15, green: 0.15, blue: 0.17)
    }
    static func rule(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.18) : Color(red: 0.82, green: 0.81, blue: 0.85)
    }
}

struct BoardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).frame(minHeight: 40)
            .foregroundStyle(BoardStyle.paper(scheme))
            .background(BoardStyle.ink(scheme), in: RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
