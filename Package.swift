// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TenXApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TenXApp", targets: ["TenXAppExecutable"]),
        .executable(name: "10x-evals", targets: ["TenXEvals"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.1"),
        // Keep Xcode's package scheme and the app project on the same crypto checkout.
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.2.0"),
    ],
    targets: [
        .target(
            name: "TenXAppCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: ".",
            exclude: [
                ".build",
                ".claude",
                ".github",
                ".vercel",
                "build",
                "10x-evals",
                "10x-evalsTests",
                "10x-macosTests",
                "10x-macos.xcodeproj",
                "README.md",
                "ROADMAP.md",
                "ideas.md",
                "docs",
                "evals",
                "output",
                "scripts",
                "10x-macos/Assets.xcassets",
                "10x-macos/Configuration",
                "AppInfo.plist",
                "10x-macos/Preview Content",
                "10x-macos/10x_macos.entitlements",
                "10x-macos/10x_macos_release.entitlements",
                "10x-macos/TenXAppApp.swift",
                "10x-macos/SparkleUpdater.swift",
                "10x-macos/Services/DB/migrations",
                "10x-macos/Resources/Fonts",
            ],
            sources: [
                "10x-macos/Config.swift",
                "10x-macos/ContentView.swift",
                "10x-macos/GlassEffectCompat.swift",
                "10x-macos/Models",
                "10x-macos/Services",
                "10x-macos/Theme.swift",
                "10x-macos/ViewModels",
                "10x-macos/Views",
            ],
            resources: [
                .copy("10x-macos/Resources/xcodegen"),
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-bare-slash-regex", "-enable-testing"]),
            ]
        ),
        .executableTarget(
            name: "TenXAppExecutable",
            dependencies: [
                "TenXAppCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: ".",
            exclude: [
                ".build",
                ".claude",
                ".github",
                ".vercel",
                "build",
                "10x-evals",
                "10x-evalsTests",
                "10x-macosTests",
                "10x-macos.xcodeproj",
                "README.md",
                "ROADMAP.md",
                "ideas.md",
                "docs",
                "evals",
                "output",
                "scripts",
                "10x-macos/Config.swift",
                "10x-macos/Configuration",
                "10x-macos/ContentView.swift",
                "10x-macos/GlassEffectCompat.swift",
                "AppInfo.plist",
                "10x-macos/Models",
                "10x-macos/Preview Content",
                "10x-macos/Resources/xcodegen",
                "10x-macos/Services",
                "10x-macos/10x_macos.entitlements",
                "10x-macos/10x_macos_release.entitlements",
                "10x-macos/Theme.swift",
                "10x-macos/ViewModels",
                "10x-macos/Views",
            ],
            sources: [
                "10x-macos/TenXAppApp.swift",
                "10x-macos/SparkleUpdater.swift",
            ],
            resources: [
                .process("10x-macos/Assets.xcassets"),
                .copy("10x-macos/Resources/Fonts"),
            ]
        ),
        .executableTarget(
            name: "TenXEvals",
            dependencies: [
                "TenXAppCore",
                .product(name: "Yams", package: "Yams"),
            ],
            path: ".",
            exclude: [
                ".build",
                ".claude",
                ".github",
                ".vercel",
                "AppInfo.plist",
                "build",
                "10x-evalsTests",
                "10x-macosTests",
                "10x-macos.xcodeproj",
                "README.md",
                "ROADMAP.md",
                "ideas.md",
                "docs",
                "evals",
                "output",
                "scripts",
                "10x-macos",
            ],
            sources: [
                "10x-evals",
            ]
        ),
        .testTarget(
            name: "TenXEvalsTests",
            dependencies: ["TenXEvals"],
            path: "10x-evalsTests"
        ),
        .testTarget(
            name: "TenXAppCoreTests",
            dependencies: ["TenXAppCore"],
            path: "10x-macosTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)