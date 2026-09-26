import AppKit
import SwiftUI

@main
struct SwissTransferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("SwissTransfer", id: "main") {
            RootView(model: .shared)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir des fichiers…") {
                    AppModel.shared.pickFiles()
                }
                .keyboardShortcut("o")
                .disabled(AppModel.shared.step == .uploading)
                Divider()
                Button("Oublier cette adresse") {
                    Task { await AppModel.shared.signOut() }
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        styleWindows()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        sender.reply(toOpenOrPrint: .success)
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        Task { @MainActor in
            AppModel.shared.importFiles(urls)
            NSApp.activate()
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        Task { @MainActor in
            AppModel.shared.importFiles(files)
            NSApp.activate()
        }
    }

    private func styleWindows() {
        for window in NSApp.windows {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
