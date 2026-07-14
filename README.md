# SlugDock

Zennの記事と画像をtitle・slug単位で管理するmacOSアプリ

## 主な機能

- 記事のtitle・slug・変更日一覧表示
- リポジトリルートのFinder表示と絶対パスのコピー
- 選択したアプリでMarkdownを開く
- Markdownと画像フォルダのFinder表示
- ファイルパスのクリップボードコピー
- 画像のドラッグ＆ドロップ追加
- 画像ファイル名の変更
- Zenn用画像記法のコピー

## 操作方法

1. 初回起動時に、`articles/`を含むZennリポジトリのルートを選択する
2. titleまたはslugで記事を検索する
3. 記事をダブルクリックするか、選択してReturnを押し、Workspace Viewを開く
4. `Open MD in App`を押し、初回だけMarkdownを開くアプリを選択する
5. Markdownや画像フォルダのパスコピー、Finder表示を行う
6. 画像一覧へPNG、JPEG、GIF、WebPファイルをドロップして追加する

## 各機能の動作

### 変更日

記事一覧の`Date Modified`には、Markdownファイルが最後に変更された日時を表示する。

日時はmacOSの地域設定に合わせて表示する。

### リポジトリパスのコピー

記事一覧の`Copy Repository Path`を押すと、選択中のリポジトリルートの絶対パスをクリップボードへコピーする。

コピーされる文字列に`cd`、引用符、改行は含まれない。

### Markdownを開くアプリ

`Open MD in App`を初めて使用するときに、Markdownファイルを開くアプリを選択する。

選択したアプリはSlugDockの設定として保存され、次回以降も使用される。macOS全体の既定アプリは変更されない。

使用するアプリを変更する場合は、`Actions`メニューから`Change Markdown App…`を選択する。

### 画像の追加

画像一覧へ、次の形式のファイルをドラッグ＆ドロップして追加できる。

- PNG
- JPEG
- GIF
- WebP

1ファイルあたり3,000,000 bytes以下。

同名のファイルがすでに存在する場合は上書きせず、ファイル名に`-2`、`-3`のような連番を付けて保存する。

### 画像一覧

画像名は拡張子を除いた1行で表示する。

拡張子とファイルサイズは、画像名とは分けて表示する。

画像を選択すると、コンテキストメニューまたはキーボードショートカットから次の操作を実行できる。

- Zenn用Markdown記法のコピー
- 絶対パスのコピー
- Finderでの表示
- ファイル名の変更

### 画像フォルダ

`Open Image Folder`を押すと、対象記事の画像フォルダをFinderで開く。

画像フォルダが存在しない場合は、新しく作成してからFinderで開く。

### 画像名の変更

画像を選択して`Return`を押すか、コンテキストメニューから`Rename Image…`を選択すると、ファイル名を変更できる。

入力欄には拡張子を含めず、拡張子は変更できない。

変更先と同名のファイルがすでに存在する場合は、既存ファイルを上書きしない。

## ショートカット

| ショートカット | 操作 |
|---|---|
| `⌘⇧O` | リポジトリを変更 |
| `⌘R` | 再読み込み |
| `⌘[` | 記事一覧へ戻る |
| `Return` | 選択画像の名前を変更 |
| `⌘⇧C` | 選択画像のMarkdown記法をコピー |
| `⌥⌘C` | 選択画像の絶対パスをコピー |
| `⌘⇧R` | 選択画像をFinderで表示 |

## 開発環境

- macOS 15.0以降
- Xcode 26.3
- Swift 6
- SwiftUI / AppKit
- Yams 6.2.2（Swift Package Manager）

## ビルドと起動

1. `SlugDock.xcodeproj`をXcode 26.3で開く
2. Schemeで`SlugDock`、実行先で`My Mac`を選択する
3. `⌘B`でビルドする
4. `⌘R`でビルドしたアプリを起動する

標準のDebug構成では、アプリは次の場所に生成される。`<識別子>`にはXcodeがプロジェクトごとに付ける文字列が入る。

```text
~/Library/Developer/Xcode/DerivedData/SlugDock-<識別子>/Build/Products/Debug/SlugDock.app
```

初回ビルド時はSwift Package ManagerがYams 6.2.2を取得するため、ネットワーク接続が必要になる。

コマンドラインでテストする場合:

```sh
xcodebuild test \
  -project SlugDock.xcodeproj \
  -scheme SlugDock \
  -destination 'platform=macOS,arch=arm64'
```
