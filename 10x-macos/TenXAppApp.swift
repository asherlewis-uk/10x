import CoreText
import SwiftUI
#if SWIFT_PACKAGE
@testable import TenXAppCore
#endif

@main
struct TenXAppApp: App {
    @State private var authManager = AuthManager()
    @State private var sparkleUpdater = SparkleUpdaterCoordinator()

    init() {
        Self.registerBundledFonts()
        Self.enforceDarkAppearance()
        Self.configureDockTile()
    }

    /// Explicitly register all .otf/.ttf fonts in the app bundle so
    /// `Font.custom` can find them reliably on macOS.
    private static func registerBundledFonts() {
        for ext in ["otf", "ttf"] {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) else { continue }
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    private static func enforceDarkAppearance() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    private static func configureDockTile() {
        DispatchQueue.main.async {
            guard let image = NSImage(named: "DockIconExact") else { return }
            let tileView = DockTileImageView(frame: NSRect(origin: .zero, size: NSApp.dockTile.size))
            tileView.image = image
            NSApp.dockTile.contentView = tileView
            NSApp.dockTile.display()
        }
    }

    var body: some Scene {
        Window("10x", id: "main") {
            Group {
                if authManager.isCheckingAuth {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !authManager.isAuthenticated {
                    LoginView()
                } else {
                    ContentView()
                }
            }
            .environment(authManager)
            .frame(minWidth: 1000, minHeight: 600)
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .task {
                sparkleUpdater.activate()
            }
            .sheet(
                isPresented: Binding(
                    get: { sparkleUpdater.availableUpdatePrompt != nil },
                    set: { isPresented in
                        if !isPresented {
                            sparkleUpdater.dismissPromptForLater()
                        }
                    }
                )
            ) {
                if let prompt = sparkleUpdater.availableUpdatePrompt {
                    SparkleUpdatePromptView(
                        prompt: prompt,
                        primaryAction: {
                            sparkleUpdater.checkForUpdates()
                        },
                        secondaryAction: {
                            sparkleUpdater.dismissPromptForLater()
                        },
                        releaseNotesAction: prompt.releaseNotesURL == nil ? nil : {
                            sparkleUpdater.openReleaseNotes()
                        }
                    )
                    .presentationBackground(.clear)
                }
            }
            .onOpenURL { url in
                BillingDeepLinkStore.shared.save(url)
                NotificationCenter.default.post(name: .tenxBillingDeepLink, object: url)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                #if canImport(Sparkle)
                CheckForUpdatesView(updaterCoordinator: sparkleUpdater)
                #endif
            }
        }
    }
}

private final class DockTileImageView: NSView {
    var image: NSImage?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image, !bounds.isEmpty else { return }

        let inset = min(bounds.width, bounds.height) * 0.055
        let iconRect = bounds.insetBy(dx: inset, dy: inset)
        let cornerRadius = min(iconRect.width, iconRect.height) * 0.224

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSGraphicsContext.current?.shouldAntialias = true
        NSGraphicsContext.current?.imageInterpolation = .high

        let clipPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
        clipPath.addClip()
        image.draw(in: iconRect, from: .zero, operation: .copy, fraction: 1)
    }
}
