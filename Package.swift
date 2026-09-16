// swift-tools-version: 6.0
import PackageDescription

// The app is built with twig.xcodeproj. This package exercises its actual data/logic files.
let package = Package(
    name: "TwigCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "TwigCore", targets: ["TwigCore"])],
    targets: [
        .target(
            name: "TwigCore",
            path: "twig",
            exclude: ["Assets.xcassets", "ContentView.swift", "MyApp.swift", "Views",
                      "Models/FolderTheme.swift", "Services/MarkdownDocument.swift", "Services/StorageConfiguration.swift"],
            sources: ["Models/InspirationFolder.swift", "Models/InspirationNote.swift", "Services/NoteStore.swift", "Logic"]
        ),
        .testTarget(name: "TwigCoreTests", dependencies: ["TwigCore"], path: "Tests/TwigCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
