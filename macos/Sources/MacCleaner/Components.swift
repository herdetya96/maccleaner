import MacCleanerCore
import SwiftUI

extension Safety {
    var color: Color {
        switch self {
        case .aman: return .green
        case .hati: return .orange
        case .periksa: return .blue
        case .jangan: return .red
        case .unknown: return .gray
        }
    }
}

extension DiskInfo.Level {
    var color: Color {
        switch self {
        case .aman: return .green
        case .sedang: return .yellow
        case .tinggi: return .orange
        case .kritis: return .red
        }
    }
}

extension Insight.Level {
    var color: Color {
        switch self {
        case .aman: return .green
        case .hati, .sedang, .tinggi: return .orange
        case .kritis: return .red
        case .info: return .accentColor
        }
    }
}

enum CategoryColor {
    static let map: [String: Color] = [
        "cache": .green, "log": Color(red: 0.52, green: 0.8, blue: 0.09), "dev": .purple,
        "trash": .teal, "downloads": .cyan, "installer": Color(red: 0.05, green: 0.65, blue: 0.91),
        "backup": .yellow, "vm": .orange, "apps": .blue, "appdata": .indigo, "media": .pink,
        "docs": Color(red: 0.66, green: 0.33, blue: 0.97), "mail": Color(red: 0.92, green: 0.7, blue: 0.03),
        "cloud": Color(red: 0.22, green: 0.74, blue: 0.97), "system": .gray, "other": Color.gray.opacity(0.6),
        "unscanned": Color.gray.opacity(0.35),
    ]
    static func of(_ id: String) -> Color { map[id] ?? .gray }
}

struct SafetyBadge: View {
    let safety: Safety
    var body: some View {
        Text(safety.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(safety.color)
            .background(safety.color.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

/// Batang pemakaian sederhana.
struct UsageBar: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
    }
}

struct DonutSlice: Identifiable {
    let id: String
    let label: String
    let size: Int64
}

/// Diagram donat tanpa framework Charts (agar jalan di macOS 13).
struct Donut: View {
    let slices: [DonutSlice]
    var body: some View {
        let total = max(1, slices.reduce(0) { $0 + $1.size })
        let starts = slices.indices.map { i in
            Double(slices[..<i].reduce(0) { $0 + $1.size }) / Double(total)
        }
        ZStack {
            Circle().stroke(Color.primary.opacity(0.06), lineWidth: 28)
            ForEach(Array(slices.enumerated()), id: \.element.id) { i, s in
                let frac = Double(s.size) / Double(total)
                Circle()
                    .trim(from: starts[i], to: starts[i] + max(0, frac - 0.003))
                    .stroke(CategoryColor.of(s.id), style: StrokeStyle(lineWidth: 28, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .help("\(s.label): \(Format.bytes(s.size))")
            }
            VStack(spacing: 0) {
                Text(Format.bytes(Int64(total))).font(.title2.bold())
                Text("total").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }
}

struct Note: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(color == .secondary ? Color.primary : color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CommandBox: View {
    @EnvironmentObject var model: AppModel
    let command: String
    var body: some View {
        HStack {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer()
            Button("Salin") { model.copy(command) }.controlSize(.small)
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Penjelasan sebuah item: kenapa besar, kalau dihapus, cara yang benar.
struct ExplanationView: View {
    let info: RuleInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Labeled(title: info.rule == nil ? "Apa ini?" : info.title + (info.inherited ? " (bagian dari)" : ""),
                    text: info.why)
            if !info.effect.isEmpty { Labeled(title: "Kalau dihapus", text: info.effect) }
            if !info.how.isEmpty { Labeled(title: "Cara membersihkan yang benar", text: info.how) }
            if !info.command.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PERINTAH TERMINAL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    CommandBox(command: info.command)
                }
            }
        }
    }
}

struct Labeled: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}
