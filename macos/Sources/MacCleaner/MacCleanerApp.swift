import AppKit
import SwiftUI

/// MacCleaner versi desktop: jendela Mac asli yang menampilkan antarmuka
/// coss ui (React, folder ui/), dengan semua logika di MacCleanerCore (Swift).
@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("MacCleaner") {
            WebContainer()
                .frame(minWidth: 1000, minHeight: 660)
                .ignoresSafeArea()
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Pindai Folder Rumah") { WebViewStore.shared.run("scan", NSHomeDirectory()) }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Pindai Seluruh Disk") { WebViewStore.shared.run("scan", "/") }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Pindai Folder Lain…") { WebViewStore.shared.run("choose") }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            CommandMenu("Tampilan") {
                Button("Ringkasan") { WebViewStore.shared.run("show", "overview") }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Analisis Folder") { WebViewStore.shared.run("show", "explore") }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Rekomendasi") { WebViewStore.shared.run("show", "recs") }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("File Besar") { WebViewStore.shared.run("show", "large") }
                    .keyboardShortcut("4", modifiers: [.command])
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
