```markdown
# SlugDock

Zennの記事と画像をtitle・slug単位で管理するmacOSアプリ

## 主な機能

- 記事のtitle・slug一覧表示
- Markdownと画像フォルダのFinder表示
- ファイルパスのクリップボードコピー
- 画像のドラッグ＆ドロップ追加
- Zenn用画像記法のコピー

## 開発環境

- macOS 15.0以降
- Xcode 26.3
- Swift 6
- SwiftUI / AppKit
- Yams 6.2.2（Swift Package Manager）

## ビルドと起動

1. `SlugDock.xcodeproj`をXcode 26.3で開く
2. Schemeで`SlugDock`、実行先で`My Mac`を選択する
3. `⌘R`でビルドして起動する

初回ビルド時はSwift Package ManagerがYams 6.2.2を取得するため、ネットワーク接続が必要になる。

コマンドラインでテストする場合:

```sh
xcodebuild test \
  -project SlugDock.xcodeproj \
  -scheme SlugDock \
  -destination 'platform=macOS,arch=arm64'
```

## 操作方法

1. 初回起動時に、`articles/`を含むZennリポジトリのルートを選択する
2. titleまたはslugで記事を検索する
3. 記事をダブルクリックするか、選択してReturnを押し、執筆モードを開く
4. Markdownや画像フォルダのパスコピー、Finder表示を行う
5. 画像一覧へPNG、JPEG、GIF、WebPファイルをドロップして追加する

ドロップで追加できる画像は1ファイルあたり3,000,000 bytes以下。既存ファイルは上書きせず、同名の場合は`-2`、`-3`のように連番を付ける。

画像を選択すると、コンテキストメニューまたはキーボードショートカットからMarkdown記法、フルパス、Finder表示を利用できる。

| ショートカット | 操作 |
|---|---|
| `⌘R` | 再読み込み |
| `⌘[` | 記事一覧へ戻る |
| `Return` / `⌘C` | 選択画像のMarkdown記法をコピー |
| `⌘⇧C` | 選択画像のフルパスをコピー |
| `⌘⇧R` | 選択画像をFinderで表示 |
