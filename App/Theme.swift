import SwiftUI

enum Theme {
    static let indigo = Color(red: 0.16, green: 0.14, blue: 0.48)
    static let blue = Color(red: 0.22, green: 0.36, blue: 0.92)
    static let amber = Color(red: 0.98, green: 0.66, blue: 0.24)
    static let gradient = LinearGradient(colors: [indigo, blue], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func swatch(_ name: String) -> Color {
        switch name {
        case "siyah": .black
        case "beyaz": .white
        case "gri": .gray
        case "kırmızı": Color(red: 0.85, green: 0.18, blue: 0.13)
        case "turuncu": .orange
        case "sarı": Color(red: 0.99, green: 0.86, blue: 0.2)
        case "yeşil": Color(red: 0.09, green: 0.64, blue: 0.29)
        case "turkuaz": .cyan
        case "mavi": Color(red: 0.15, green: 0.39, blue: 0.92)
        case "lacivert": Color(red: 0.12, green: 0.16, blue: 0.47)
        case "mor": .purple
        case "pembe": .pink
        default: Color(red: 0.5, green: 0.11, blue: 0.11)
        }
    }
}

/// Yumuşak köşeli, ince kenarlıklı içerik kartı.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle").font(.headline).labelStyle(.titleAndIcon)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

struct Chip: View {
    var text: String
    var color: Color?
    var selected = false

    var body: some View {
        HStack(spacing: 6) {
            if let color { Circle().fill(color).overlay(Circle().strokeBorder(.primary.opacity(0.25))).frame(width: 11, height: 11) }
            Text(text).font(.callout)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(selected ? AnyShapeStyle(Theme.blue.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? Theme.blue : .clear, lineWidth: 1.5))
        .contentShape(Capsule())
    }
}

struct FieldLabel: View {
    var text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(.secondary) }
}
