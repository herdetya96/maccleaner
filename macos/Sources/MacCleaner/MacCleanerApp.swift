import AppKit
import MacCleanerCore
import SwiftUI

@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MacCleaner") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Pindai Folder Rumah") { model.startScan(NSHomeDirectory()) }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Pindai Seluruh Disk") { model.startScan("/") }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Pindai Folder Lain…") { model.chooseFolderAndScan() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Diperlukan saat dijalankan sebagai executable SwiftPM (tanpa bundle .app).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch model.section {
                case .overview: OverviewView()
                case .explore: ExploreView()
                case .recs: RecommendationsView()
                case .large: LargeFilesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) { ToastView() }
        .sheet(isPresented: $model.scanning) { ScanProgressView().environmentObject(model) }
        .sheet(item: Binding(
            get: { model.pendingTrash.map { TrashBatch(items: $0) } },
            set: { if $0 == nil { model.pendingTrash = nil } }
        )) { batch in
            ConfirmTrashView(items: batch.items).environmentObject(model)
        }
        .alert("Kosongkan Sampah?", isPresented: $model.confirmEmptyTrash) {
            Button("Batal", role: .cancel) {}
            Button("Kosongkan", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Semua file di Sampah (\(Format.bytes(model.trashSize))) akan dihapus permanen dan tidak bisa dikembalikan.")
        }
    }
}

struct TrashBatch: Identifiable {
    let items: [TrashItem]
    var id: String { items.map(\.path).joined(separator: "|") }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) {
            ForEach(Page.allCases) { page in
                HStack {
                    Label(page.title, systemImage: page.icon)
                    Spacer()
                    if page == .recs, let s = model.summary, s.safeTotal > 0 {
                        Text(Format.bytes(s.safeTotal))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.green.opacity(0.18), in: Capsule())
                    }
                }
                .tag(page)
                .disabled(page != .overview && !model.hasResults)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ARTI LABEL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach([Safety.aman, .hati, .periksa, .jangan], id: \.self) { s in
                    VStack(alignment: .leading, spacing: 1) {
                        SafetyBadge(safety: s)
                        Text(s.hint).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ToastView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let t = model.toast {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(t.isError ? Color.red : Color.green)
                Text(t.text).fixedSize(horizontal: false, vertical: true)
                Button { model.toast = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 8)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct ScanProgressView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Memindai \(model.scanRootDisplay)").font(.headline)
            Text("\(Format.count(model.progress.files)) file · \(Format.bytes(model.progress.bytes)) · \(Int(model.scanElapsed)) dtk")
                .monospacedDigit()
            Text(model.matcher.display(model.progress.current))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(width: 420)
            Button("Batalkan") { model.cancelScan() }.keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .interactiveDismissDisabled()
    }
}

struct ConfirmTrashView: View {
    @EnvironmentObject var model: AppModel
    let items: [TrashItem]

    var body: some View {
        let total = items.reduce(0) { $0 + $1.size }
        let risky = items.filter { $0.safety != .aman }
        VStack(alignment: .leading, spacing: 12) {
            Text("Buang \(items.count) item (\(Format.bytes(total))) ke Sampah?").font(.title3.bold())
            if risky.isEmpty {
                Note(text: "Semua item berlabel aman dihapus.", color: .green)
            } else {
                Note(text: "\(risky.count) item bukan berlabel \"Aman dihapus\". Pastikan Anda memang tidak membutuhkannya.",
                     color: .orange)
            }
            List(items) { it in
                HStack {
                    Text(it.display + (it.contents ? "  (isinya saja)" : ""))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if it.safety != .aman { SafetyBadge(safety: it.safety) }
                    Text(Format.bytes(it.size)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 160, maxHeight: 300)
            Text("Item dipindah ke Sampah dan masih bisa dikembalikan lewat Finder. Ruang baru benar-benar kosong setelah Sampah dikosongkan.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Batal") { model.pendingTrash = nil }.keyboardShortcut(.cancelAction)
                Button("Ya, buang ke Sampah") { model.performTrash(items) }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
