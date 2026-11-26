// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacCleaner", targets: ["MacCleaner"]),
        .library(name: "MacCleanerCore", targets: ["MacCleanerCore"]),
    ],
    targets: [
        // Logika inti tanpa UI: aturan, pemindai, rekomendasi, buang ke Sampah.
        .target(name: "MacCleanerCore"),
        // Aplikasi SwiftUI.
        .executableTarget(name: "MacCleaner", dependencies: ["MacCleanerCore"]),
        .testTarget(name: "MacCleanerCoreTests", dependencies: ["MacCleanerCore"]),
    ]
)
