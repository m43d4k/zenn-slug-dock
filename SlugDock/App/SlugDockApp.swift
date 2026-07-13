import SwiftUI

@main
struct SlugDockApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(SettingsService.windowSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Change Repository…") {
                    state.chooseRepository()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Actions") {
                Button("Reload") { state.reload() }
                    .keyboardShortcut("r", modifiers: .command)

                Button("Back to Article List") { state.returnToArticleList() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(state.selectedArticle == nil)

                Button("Change Markdown App…") { state.chooseMarkdownApplication() }

                Divider()

                Button("Copy as Markdown") { state.copySelectedImageMarkdown() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(state.selectedImageID == nil)

                Button("Copy Image Full Path") { state.copySelectedImagePath() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(state.selectedImageID == nil)

                Button("Show Image in Finder") { state.revealSelectedImage() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(state.selectedImageID == nil)

                Button("Rename Image…") { state.requestRenameSelectedImage() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(state.selectedImageID == nil)
            }
        }
    }
}
