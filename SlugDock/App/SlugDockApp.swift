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
                Button("リポジトリを変更…") {
                    state.chooseRepository()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("操作") {
                Button("再読み込み") { state.reload() }
                    .keyboardShortcut("r", modifiers: .command)

                Button("記事一覧へ戻る") { state.returnToArticleList() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(state.selectedArticle == nil)

                Divider()

                Button("Markdownをコピー") { state.copySelectedImageMarkdown() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(state.selectedImageID == nil)

                Button("選択画像のMarkdownをコピー") { state.copySelectedImageMarkdown() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(state.selectedImageID == nil)

                Button("画像のフルパスをコピー") { state.copySelectedImagePath() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(state.selectedImageID == nil)

                Button("画像をFinderで表示") { state.revealSelectedImage() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(state.selectedImageID == nil)
            }
        }
    }
}
