import SwiftUI

extension Color {
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.32)
    static let ocean = Color(red: 0.24, green: 0.43, blue: 0.67)
    static let mutedInk = Color(red: 0.33, green: 0.40, blue: 0.51)
}

struct Wallpaper: View {
    @Environment(\.colorScheme) var scheme
    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: scheme == .dark ? [Color(red: 0.13, green: 0.20, blue: 0.32), .black, Color.ocean.opacity(0.8)] : [Color(red: 0.97, green: 0.86, blue: 0.77), Color(red: 0.77, green: 0.84, blue: 0.92), Color(red: 0.41, green: 0.57, blue: 0.76)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.65), Color.ocean.opacity(0.45), .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Ellipse().stroke(.white.opacity(0.45), lineWidth: 2))
                    .frame(width: g.size.width * 1.4, height: g.size.height * 0.85)
                    .rotationEffect(.degrees(-32)).offset(x: -g.size.width * 0.35, y: g.size.height * 0.23)
                    .shadow(color: .ocean.opacity(0.2), radius: 35, y: 20)
                Ellipse().fill(LinearGradient(colors: [Color.ocean.opacity(0.7), Color(red: 0.7, green: 0.84, blue: 0.9), .white.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                    .overlay(Ellipse().stroke(.white.opacity(0.3), lineWidth: 2))
                    .frame(width: g.size.width * 1.15, height: g.size.height * 0.85)
                    .rotationEffect(.degrees(-32)).offset(x: g.size.width * 0.45, y: g.size.height * 0.54)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct Glass: ViewModifier {
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    var radius: CGFloat = 24
    var solid = false
    func body(content: Content) -> some View {
        content
            .background {
                if solid || reduceTransparency {
                    RoundedRectangle(cornerRadius: radius).fill(scheme == .dark ? Color(red: 0.13, green: 0.19, blue: 0.29) : Color(red: 0.94, green: 0.96, blue: 0.99))
                } else {
                    RoundedRectangle(cornerRadius: radius).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: radius).fill(.white.opacity(scheme == .dark ? 0.025 : 0.14)))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: Color.ink.opacity(0.09), radius: 20, y: 10)
    }
}

extension View {
    func glass(_ radius: CGFloat = 24, solid: Bool = false) -> some View { modifier(Glass(radius: radius, solid: solid)) }
}

struct ActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 17).padding(.vertical, 11)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.ocean : Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(prominent ? 0.16 : 0.5)))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.38)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2.1).foregroundStyle(.secondary) }
}

struct MorseMarks: View {
    let code: String
    var active: Int = -1
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: size * 0.55) {
            ForEach(Array(code.enumerated()), id: \.offset) { i, char in
                Capsule().fill(i == active ? Color.orange : Color.ocean)
                    .frame(width: char == "." ? size : size * 2.8, height: size)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(code.map { $0 == "." ? "dot" : "dash" }.joined(separator: " "))
    }
}

struct DockButton: View {
    var icon: String
    var title: String
    var selected: Bool
    var action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium))
                Text(title).font(.system(size: 10, weight: .medium))
            }.frame(width: 83, height: 56)
                .background(.white.opacity(selected ? 0.4 : hover ? 0.22 : 0), in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .scaleEffect(hover && !reduceMotion ? 1.07 : 1)
            .offset(y: hover && !reduceMotion ? -3 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: hover)
            .onHover { hover = $0 }
    }
}
