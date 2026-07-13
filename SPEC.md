# SlugDock 仕様書

## 1. 文書情報

- 文書名: `SPEC.md`
- 対象バージョン: `0.1.0`
- 対象OS: macOS Sequoia 15.0以降
- アプリ形態: ローカル専用デスクトップアプリ
- 実装言語: Swift
- UI: SwiftUI
- macOS連携: AppKit
- 想定利用者: 開発者本人
- 対象コンテンツ: Zennの記事
- 対象外: Zennの本、スクラップ

## 2. 目的

ZennのGitHub連携リポジトリでは、記事ファイル名がslugになるため、Finder上では記事タイトルから目的のMarkdownを探しにくい。

本アプリは、Zennリポジトリ内の記事をtitleとslugで一覧化し、選択した記事のMarkdownファイルと対応画像フォルダへ即座にアクセスできるようにする。

特に、以下の操作を簡略化する。

- 記事タイトルからMarkdownファイルを見つける
- Markdownファイルのフルパスを取得する
- MarkdownファイルをFinderで表示する
- 記事専用画像フォルダへアクセスする
- 画像をドラッグ＆ドロップで追加する
- 画像のファイル名を変更する
- Zenn用の画像埋め込み記法を取得する
- 画像ファイルをFinderで表示する

## 3. 基本方針

### 3.1 正本

Zennリポジトリ内のファイルを唯一の正本とする。

アプリ独自のデータベースや記事管理ファイルは作成しない。

### 3.2 Zenn CLIとの関係

記事一覧と画像管理ではZenn CLIを呼び出さない。

以下を直接読み取る。

- `articles/*.md`
- 各MarkdownのFront Matter
- `images/<slug>/`

Zenn CLIのプレビュー起動や記事作成は初版の対象外とする。

### 3.3 画像管理規約

Zenn自体は`images`以下のディレクトリ構造を強制しないが、本アプリでは次の規約を採用する。

```text
<repository-root>/
├── articles/
│   └── <slug>.md
└── images/
    └── <slug>/
        └── <image-file>
```

記事と画像フォルダの対応はslugで決定する。

```text
articles/example-article.md
images/example-article/
```

## 4. 技術構成

### 4.1 採用技術

- Swift 6
- SwiftUI
- AppKit
- Foundation
- Yams 6.2.2
- Swift Package Manager
- Xcodeプロジェクト

開発にはXcode 26.3を使用し、macOS Deployment Targetは15.0とする。

### 4.2 AppKitを使用する機能

- クリップボード操作: `NSPasteboard`
- Finderでファイルを選択表示: `NSWorkspace.activateFileViewerSelecting`
- Finderでフォルダを開く: `NSWorkspace.open`
- リポジトリ選択: `NSOpenPanel`

### 4.3 外部依存

YAML Front Matterの解析にYams 6.2.2を使用する。

外部依存は原則としてYamsだけに限定する。

### 4.4 App Sandbox

初版ではApp Sandboxを無効にする。

理由:

- 開発者本人だけがローカルで使用する
- 任意のZennリポジトリを継続的に読み書きする
- Security-Scoped Bookmark対応を初版へ持ち込まない

将来配布する場合は、App SandboxとSecurity-Scoped Bookmarkへの移行を別途検討する。

## 5. 対応するZenn仕様

### 5.1 記事

- 記事はリポジトリ直下の`articles`ディレクトリに置かれる
- 1記事は1つのMarkdownファイルで管理される
- slugはMarkdownファイル名から取得する
- titleはMarkdown先頭のYAML Front Matterから取得する

例:

```text
articles/example-article.md
```

```yaml
---
title: "記事タイトル"
emoji: "📝"
type: "tech"
topics: []
published: false
---
```

この場合:

```text
title = 記事タイトル
slug  = example-article
```

### 5.2 画像

本アプリで扱う画像は以下に限定する。

- `.png`
- `.jpg`
- `.jpeg`
- `.gif`
- `.webp`

本アプリからドロップで追加する画像のファイルサイズは3MB以内とする。

判定は安全側に倒し、`3,000,000 bytes`以下を許可する。

Zenn用の参照パスは`/images/`から始まる絶対パスとする。

```markdown
![](/images/example-article/image.png)
```

## 6. 用語

### 6.1 リポジトリルート

`articles`ディレクトリを含むZennリポジトリのルートディレクトリ。

### 6.2 記事一覧モード

リポジトリ内の記事をtitleとslugで表示する画面。

### 6.3 Workspace View

選択した記事のMarkdownファイルと画像を管理する画面。

Markdown本文を編集するエディタではない。

### 6.4 対応画像フォルダ

次のパスで決定される記事専用画像フォルダ。

```text
<repository-root>/images/<slug>/
```

## 7. 起動とリポジトリ選択

### 7.1 初回起動

保存済みリポジトリがない場合は、リポジトリ選択画面を表示する。

ユーザーは`NSOpenPanel`からディレクトリを1つ選択する。

### 7.2 リポジトリ判定

選択したディレクトリに次が存在することを必須条件とする。

```text
articles/
```

`images/`は存在しなくてもよい。

### 7.3 無効なディレクトリ

`articles/`が存在しない場合は、そのディレクトリをリポジトリとして登録しない。

次の内容を表示する。

```text
The selected folder does not contain an articles directory.
```

### 7.4 保存

選択したリポジトリルートの絶対パスを`UserDefaults`へ保存する。

次回起動時は保存済みパスを自動的に開く。

保存済みパスが存在しなくなった場合は、保存内容を破棄してリポジトリ選択画面へ戻る。

保存済みリポジトリルート自体は存在するが、`articles/`ディレクトリが存在しなくなった場合は、保存内容を破棄せず、次のエラーを表示する。

```text
articles directory not found
```

この場合、リポジトリ選択画面へ自動的に戻らない。ユーザーは再読み込みまたはリポジトリ変更を実行できる。

### 7.5 リポジトリ変更

記事一覧画面のメニューまたはツールバーから、別のリポジトリを選択できるようにする。

## 8. 記事の読み取り

### 8.1 対象ファイル

`articles`直下にある`.md`ファイルだけを対象とする。

サブディレクトリは再帰的に走査しない。

### 8.2 slug

ファイル名から`.md`を除いた文字列をslugとする。

```text
articles/example-article.md
→ example-article
```

### 8.3 title

Markdownの先頭にあるFront Matterから`title`を取得する。

Front MatterはYAMLとしてYamsで解析する。

正規表現だけで`title:`を抽出してはならない。

### 8.4 Front Matterの範囲

ファイル先頭が`---`で始まる場合に限り、次の`---`までをFront Matterとして扱う。

UTF-8 BOMがある場合は除去してから判定する。

### 8.5 titleが空の場合

以下の場合は表示タイトルを`Untitled`とする。

- `title`キーがない
- `title`が空文字
- `title`が空白だけ

Front Matter自体がない場合も、表示タイトルを`Untitled`とし、エラー状態にはしない。

### 8.6 Front Matterが不正な場合

以下をFront Matterエラーとする。

- 開始区切りの`---`はあるが、終了区切りの`---`がない
- Front MatterがYAMLとして不正
- `title`が文字列以外の型

記事自体は一覧から除外しない。

以下の状態で表示する。

- title: `Front Matter Error`
- slug: 通常どおり表示
- エラー状態を示すアイコンまたはバッジを表示

記事を選択した場合は、Workspace View上部に解析エラーを表示する。

### 8.7 Markdownを読み取れない場合

Markdownファイル自体を読み取れない場合は、Front Matterエラーと区別する。

記事自体は一覧から除外せず、以下の状態で表示する。

- title: `Read Error`
- slug: 通常どおり表示
- エラー状態を示すアイコンまたはバッジを表示

記事を選択した場合は、Workspace View上部に読み取りエラーを表示する。

### 8.8 更新日時

内部データとしてMarkdownファイルの更新日時を保持する。

初版では画面へ表示しなくてよい。

### 8.9 並び順

初期状態ではtitleの昇順とする。

比較は大文字小文字を区別せず、ローカライズされた比較を使用する。

titleが同じ場合はslugの昇順とする。

## 9. 記事一覧モード

### 9.1 表示内容

一覧には最低限、以下の2列を表示する。

| 列 | 内容 |
|---|---|
| Title | Front Matterの`title` |
| Slug | Markdownファイル名から取得したslug |

### 9.2 検索

画面上部に検索欄を設置する。

検索対象:

- title
- slug

条件:

- 部分一致
- 大文字小文字を区別しない
- 前後の空白を無視する
- 入力中に即時更新する

### 9.3 記事選択

単一選択とする。

### 9.4 Workspace Viewへの移行

以下の操作でWorkspace Viewへ移行する。

- 行をダブルクリック
- 行を選択して`Return`
- 行のコンテキストメニューから`Open Workspace`

### 9.5 再読み込み

ツールバーに再読み込みボタンを設置する。

キーボードショートカット:

```text
⌘R
```

再読み込み時は以下を再走査する。

- 記事一覧
- Front Matter
- ファイル更新日時

### 9.6 リポジトリをFinderで開く

ツールバーまたはメニューに次を設置する。

```text
Open Repository in Finder
```

実行時はリポジトリルートをFinderで開く。

## 10. Workspace View

### 10.1 ヘッダー

以下を表示する。

- `Back`ボタン
- title
- slug
- Front Matterエラー
- 再読み込みボタン

### 10.2 Markdown操作

次のボタンを表示する。

- `Copy MD Path`
- `Show MD in Finder`
- `Open MD in App`

`Open MD in App`は、選択中記事のMarkdownをSlugDockで設定したMarkdownアプリで開く。
Markdownアプリが未設定の場合はアプリ選択パネルを表示し、選択されたアプリを保存してからMarkdownを開く。
この設定はmacOS全体の既定アプリを変更しない。

`Actions`メニューに`Change Markdown App…`を表示し、保存済みのMarkdownアプリを再設定できるようにする。

### 10.3 画像フォルダ操作

次のボタンを表示する。

- `Copy Image Folder Path`
- `Open Image Folder`

Markdown操作と画像フォルダ操作の5つのボタンは横一列に並べ、同じ幅にする。
`Back`を含むWorkspace View内の操作ボタンは、文字の周囲に余白を設け、標準ボタンより少し高く表示する。

### 10.4 画像一覧

対応画像フォルダ内の画像をグリッド表示する。

各セルに以下を表示する。

- サムネイル
- 拡張子を除いたファイル名（1行、省略表示）
- ファイルサイズ
- 拡張子

### 10.5 空状態

対応画像フォルダが存在しない、または画像がない場合は次を表示する。

```text
No Images
Drop images here
```

### 10.6 ドロップ領域

Workspace Viewの画像一覧領域全体をドロップ対象とする。

空状態だけでなく、画像が存在する状態でもドロップ可能にする。

### 10.7 戻る操作

以下の操作で記事一覧へ戻る。

- `Back`ボタン
- `⌘[`
- NavigationSplitViewを使用する場合は記事一覧の再選択

## 11. パス操作

### 11.1 MDパスをコピー

対象:

```text
<repository-root>/articles/<slug>.md
```

クリップボードへPOSIX形式の絶対パスをプレーンテキストで格納する。

例:

```text
/Users/example/work/zenn/articles/example-article.md
```

以下は付加しない。

- 引用符
- エスケープ
- `file://`
- Markdown記法

### 11.2 MDをFinderで表示

`NSWorkspace.activateFileViewerSelecting`を使用する。

Finderを開き、対象Markdownファイルを選択状態にする。

単に`articles`フォルダを開くだけにしてはならない。

### 11.3 画像フォルダパスをコピー

対象:

```text
<repository-root>/images/<slug>
```

フォルダが存在しなくても予定パスをコピーする。

### 11.4 画像フォルダをFinderで開く

対応画像フォルダが存在しない場合は作成する。

作成後、`NSWorkspace.open`でフォルダを開く。

### 11.5 コピー完了表示

クリップボードへのコピー成功時は、非モーダルな短い通知を表示する。

例:

```text
MD path copied
```

## 12. 画像の列挙

### 12.1 対象ディレクトリ

```text
<repository-root>/images/<slug>/
```

### 12.2 走査範囲

対応画像フォルダ直下だけを走査する。

サブディレクトリは再帰的に表示しない。

### 12.3 対応拡張子

拡張子の比較は大文字小文字を区別しない。

```text
.png
.jpg
.jpeg
.gif
.webp
```

既存ファイルの列挙ではファイルサイズを表示対象の判定に使用しない。対応拡張子であれば、3,000,000 bytesを超えるファイルも一覧に表示する。

3,000,000 bytesの上限は、画像をドロップして追加するときだけ適用する。

### 12.4 並び順

ファイル名の昇順とする。

比較は大文字小文字を区別せず、ローカライズされた比較を使用する。

### 12.5 サムネイル

- `NSImage`またはQuick Look Thumbnailingを利用する
- アスペクト比を維持する
- セル内に収まるよう縮小する
- 元画像を変更しない
- GIFは先頭フレームの静止画でよい

### 12.6 サムネイル失敗

サムネイル生成に失敗しても、画像を一覧から除外しない。

代替アイコンとファイル名を表示する。

## 13. 画像ドロップ

### 13.1 受け付けるデータ

FinderなどからドロップされたローカルファイルURLを受け付ける。

複数ファイルの同時ドロップに対応する。

### 13.2 受け付けないデータ

以下は拒否する。

- ディレクトリ
- リモートURL
- 対応外拡張子
- 3,000,000 bytesを超えるファイル
- 読み取り権限がないファイル

### 13.3 コピー先

```text
<repository-root>/images/<slug>/
```

コピー先フォルダが存在しない場合は作成する。

### 13.4 ファイル名

初版では元のファイル名を維持する。

Unicode、日本語、空白を含むファイル名もそのまま扱う。

### 13.5 同名ファイル

既存ファイルを上書きしてはならない。

同名ファイルが存在する場合は、拡張子の前に連番を追加する。

```text
image.png
image-2.png
image-3.png
```

連番は既存ファイルと衝突しない最小値を使用する。

### 13.6 コピー後

コピーに成功した画像について、以下を実行する。

1. 画像一覧を再読み込みする
2. 最後にコピーした画像を選択状態にする
3. 成功件数を通知する

例:

```text
Added 3 image(s)
```

### 13.7 一部失敗

複数ファイルの一部だけが失敗した場合、成功したファイルは取り消さない。

成功件数と失敗理由をまとめて表示する。

例:

```text
Added 2 image(s)
Failed to add 1 item(s): The image exceeds 3 MB
```

### 13.8 コピー元とコピー先が同一

コピー元URLとコピー先URLが同一の場合はコピー処理を行わない。

画像一覧を再読み込みし、その画像を選択する。

## 14. 画像選択と操作

### 14.1 選択

画像は単一選択とする。

### 14.2 コンテキストメニュー

各画像セルのコンテキストメニューに以下を表示する。

1. `Copy as Markdown`
2. `Copy Full Path`
3. `Show in Finder`
4. `Rename Image…`

### 14.3 ダブルクリック

画像セルのダブルクリックでFinder表示を実行する。

### 14.4 キーボードショートカット

画像一覧にフォーカスがあり、画像が選択されている場合に有効とする。

| 操作 | 機能 |
|---|---|
| `Return` | Rename Image |
| `⌘⇧C` | Copy as Markdown |
| `⌥⌘C` | Copy Full Path |
| `⌘⇧R` | Show in Finder |

`⌘R`は画面再読み込みに使用するため、Finder表示には割り当てない。

### 14.5 画像名の変更

`Rename Image…`または`Return`を実行すると、現在の拡張子を除いたファイル名を初期値とする入力シートを表示する。

入力欄には拡張子を含めない。拡張子は入力欄の外に固定表示し、編集できないようにする。

入力値の前後にある空白と改行は除去する。以下の名前は受け付けない。

- 空の名前
- `/`またはNULL文字を含む名前
- `.`または`..`
- 元画像と異なる拡張子
- 対応画像フォルダ内の既存ファイルと同じ名前

拡張子は大文字小文字を含めて維持し、画像形式の変換は行わない。既存ファイルを上書きしてはならない。

変更前と同じ名前が入力された場合は、ファイル操作を行わずシートを閉じる。

変更に成功した場合は画像一覧を再読み込みし、変更後の画像を選択状態にして、非モーダルな完了通知を表示する。失敗した場合は理由を非モーダル表示し、元画像を維持する。

## 15. 画像のMarkdown記法

### 15.1 基本形式

```markdown
![](/images/<slug>/<filename>)
```

例:

```markdown
![](/images/example-article/diagram.png)
```

### 15.2 パスの生成

ファイルシステム上の絶対パスではなく、Zenn用の`/images/`から始まるパスを生成する。

### 15.3 特殊文字を含むファイル名

ファイル名またはslugに空白などが含まれる場合は、Markdownのリンク先を山括弧で囲む。

```markdown
![](</images/example-article/image 1.png>)
```

山括弧の内側へ余分な空白や不可視文字を入れてはならない。

### 15.4 クリップボード形式

Markdown記法をプレーンテキストとしてクリップボードへ格納する。

末尾に改行は付けない。

### 15.5 altテキスト

初版ではaltテキストを空にする。

```markdown
![](/images/example-article/image.png)
```

## 16. 画像のフルパス操作

### 16.1 フルパスをコピー

選択画像のPOSIX形式の絶対パスをコピーする。

例:

```text
/Users/example/work/zenn/images/example-article/image.png
```

以下は付加しない。

- 引用符
- `file://`
- Markdown記法

### 16.2 Finderで表示

`NSWorkspace.activateFileViewerSelecting`を使用する。

Finderを開き、対象画像を選択状態にする。

単に対応画像フォルダを開くだけにしてはならない。

## 17. 再読み込み

### 17.1 手動再読み込み

`⌘R`またはツールバーの再読み込みボタンで実行する。

記事一覧モードでは記事を再走査する。

Workspace Viewでは以下を再走査する。

- 選択中記事のFront Matter
- Markdownファイルの存在
- 対応画像フォルダ
- 画像一覧

### 17.2 自動再読み込み

初版では常時ファイル監視を実装しない。

以下のタイミングでは自動再読み込みする。

- アプリが画像をコピーした直後
- アプリがアクティブへ戻ったとき
- リポジトリを変更した直後

アクティブ復帰時は選択状態を可能な限り維持する。

### 17.3 記事が削除された場合

Workspace Viewで開いているMarkdownファイルが存在しなくなった場合は、記事一覧へ戻り、次を表示する。

```text
Article file not found
```

## 18. 状態管理

### 18.1 保存する状態

`UserDefaults`へ保存する。

- 最後に選択したリポジトリルート
- ウインドウサイズ
- Markdownを開くアプリのBundle IDと絶対パス
- 必要であれば最後の検索語

### 18.2 保存しない状態

以下は永続化しない。

- 記事一覧のキャッシュ
- 画像一覧のキャッシュ
- Front Matterの解析結果
- 選択中画像
- 独自の記事ID

### 18.3 ID

記事の識別子はMarkdownファイルURLとする。

画像の識別子は画像ファイルURLとする。

## 19. データモデル

参考モデル:

```swift
struct Article: Identifiable, Hashable {
    let id: URL
    let title: String
    let slug: String
    let markdownURL: URL
    let imageDirectoryURL: URL
    let modifiedAt: Date?
    let frontMatterError: String?
    let readError: String?
}

struct ImageAsset: Identifiable, Hashable {
    let id: URL
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let markdownPath: String
}
```

Front Matterの最小モデル:

```swift
struct ArticleFrontMatter: Decodable {
    let title: String?
}
```

未知のFront Matterフィールドは無視する。

## 20. 推奨コード構成

```text
SlugDock/
├── App/
│   ├── SlugDockApp.swift
│   └── AppState.swift
├── Models/
│   ├── Article.swift
│   ├── ArticleFrontMatter.swift
│   └── ImageAsset.swift
├── Services/
│   ├── RepositoryService.swift
│   ├── ArticleScanner.swift
│   ├── FrontMatterParser.swift
│   ├── ImageService.swift
│   ├── ClipboardService.swift
│   ├── FinderService.swift
│   └── SettingsService.swift
├── Views/
│   ├── RepositorySelectionView.swift
│   ├── ArticleListView.swift
│   ├── WorkspaceView.swift
│   ├── ImageGridView.swift
│   ├── ImageCell.swift
│   └── ErrorBanner.swift
├── Utilities/
│   ├── FileNameCollisionResolver.swift
│   ├── MarkdownImageFormatter.swift
│   └── FileSizeFormatter.swift
└── Tests/
    ├── FrontMatterParserTests.swift
    ├── ArticleScannerTests.swift
    ├── FileNameCollisionResolverTests.swift
    └── MarkdownImageFormatterTests.swift
```

この構成は目安であり、ファイル数を増やすためだけの分割は行わない。

## 21. UI構成

### 21.1 記事一覧

```text
┌──────────────────────────────────────────────────────┐
│ SlugDock              [Repository] [Reload]         │
├──────────────────────────────────────────────────────┤
│ [ Search by title or slug                       ]  │
├──────────────────────────────┬───────────────────────┤
│ Title                        │ Slug                  │
├──────────────────────────────┼───────────────────────┤
│ Zenn CLIの使い方             │ example-article       │
│ SwiftUIでアプリを作る        │ swiftui-app           │
└──────────────────────────────┴───────────────────────┘
```

### 21.2 Workspace View

```text
┌──────────────────────────────────────────────────────┐
│ [Back] Article Title                       [Reload] │
│        example-article                               │
├──────────────────────────────────────────────────────┤
│ [Copy MD Path] [Show MD in Finder] [Open MD in App]│
│ [Copy Image Folder Path] [Open Image Folder]       │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐     │
│  │ thumbnail  │  │ thumbnail  │  │ thumbnail  │     │
│  └────────────┘  └────────────┘  └────────────┘     │
│  image1.png      diagram.webp    result.jpg          │
│                                                      │
│                  Drop images here                  │
└──────────────────────────────────────────────────────┘
```

### 21.3 ウインドウ

- UIのラベル、メニュー、通知、エラーメッセージは英語で表示する
- 標準的なmacOSウインドウ
- 最小サイズを設定する
- 記事一覧と画像グリッドが極端に崩れないサイズとする
- ダークモードとライトモードの両方へ自動対応する
- 固定色を多用しない
- システム標準コンポーネントを優先する

## 22. エラー処理

### 22.1 原則

ファイル操作の失敗を黙って無視してはならない。

ユーザーが次に何を確認すべきか分かる文言を表示する。

### 22.2 表示方法

通常の成功通知と軽微な警告は非モーダル表示とする。

処理を継続できないエラーだけアラートを使用する。

### 22.3 主なエラー

- リポジトリが存在しない
- `articles`が存在しない
- Markdownを読み取れない
- Front Matterを解析できない
- 画像フォルダを作成できない
- 画像をコピーできない
- 画像名を変更できない
- 変更後の画像名が既存ファイルと重複している
- 対応外の画像形式
- 画像が3MBを超えている
- Finder表示の対象ファイルまたはフォルダが存在しない
- 保存したMarkdownアプリが存在しない、またはアプリとして使用できない
- Markdownを選択したアプリで開けない
- クリップボードへ書き込めない

Finder操作では、呼び出し前に対象ファイルまたはフォルダの存在を確認し、画像フォルダの作成失敗など、アプリが検出できるエラーを表示する。

Finder操作では、`NSWorkspace.activateFileViewerSelecting`または`NSWorkspace.open`を呼び出した後のFinder側の成否は追跡せず、保証しない。

Markdownの外部アプリ起動には`NSWorkspace.open(_:withApplicationAt:configuration:)`を使用し、非同期に返される失敗を表示する。
保存済みアプリを解決できない場合は、別アプリへ暗黙的にフォールバックせず、`Change Markdown App…`からの再選択を案内する。

### 22.4 パス情報

エラーメッセージには、問題の特定に必要な場合だけ対象パスを表示する。

## 23. パフォーマンス

### 23.1 記事走査

数百記事程度を前提とする。

記事一覧読み込み時に各MarkdownのFront Matterだけを読み取る。

本文全体を永続的にメモリへ保持しない。

### 23.2 Front Matter読み取り

ファイル先頭からFront Matter終端までを読み取ればよい。

ただし、単純化のため初版でファイル全体を読み取っても、数百記事規模で問題がなければ許容する。

### 23.3 サムネイル

元画像をフル解像度のままグリッドへ保持しない。

必要な表示サイズへ縮小したサムネイルを利用する。

### 23.4 UIスレッド

ディレクトリ走査、画像コピー、サムネイル生成はメインスレッドを長時間ブロックしない。

UI状態の更新だけをMainActor上で行う。

## 24. アクセシビリティ

最低限、以下を満たす。

- ボタンに明確なラベルを設定する
- アイコンだけのボタンにはaccessibility labelを設定する
- キーボードだけで主要操作を実行できる
- 選択状態を色だけで表現しない
- VoiceOverでtitle、slug、画像ファイル名を読み取れる

## 25. テスト

### 25.1 必須ユニットテスト

#### Front Matter解析

- 正常なtitleを取得できる
- titleにコロンが含まれても解析できる
- titleが空の場合に`Untitled`となる
- Front Matterがない場合に`Untitled`となり、エラー状態にならない
- 開始区切りがあり終了区切りがない場合にエラー状態を返す
- YAMLが壊れている場合にエラー状態を返す
- `title`が文字列以外の場合にエラー状態を返す
- Markdownを読み取れない場合にFront Matterエラーとは異なる読み取りエラーを返す
- UTF-8 BOMを処理できる

#### 記事走査

- `articles`直下の`.md`だけを取得する
- サブディレクトリを無視する
- `.MD`の扱いを明確にする
- slugをファイル名から取得する
- title、slug順に並べる

`.MD`は初版では対象外とし、小文字の`.md`だけを正式対応とする。

#### 画像検証

- 対応拡張子を受け付ける
- 拡張子の大文字小文字を区別しない
- 対応外拡張子を拒否する
- 3,000,000 bytesを受け付ける
- 3,000,001 bytesを拒否する
- ディレクトリを拒否する
- 既存の3,000,001 bytes以上の対応画像を一覧から除外しない

#### 同名解決

- 衝突がなければ元のファイル名を使用する
- `image.png`が存在すれば`image-2.png`になる
- `image-2.png`も存在すれば`image-3.png`になる
- 複数ドットを含むファイル名を処理できる

#### Markdown記法

- 通常ファイル名の記法を生成できる
- Unicodeファイル名を保持する
- 空白を含む場合に安全な記法を生成できる
- 末尾改行を付けない

#### 画像名の変更

- Unicodeや空白を含む名前へ変更できる
- 空の名前、パス区切り、拡張子変更を拒否する
- 既存ファイルと同じ名前を拒否し、上書きしない
- 変更後のURLとMarkdown記法が新しいファイル名を反映する

### 25.2 手動確認

- リポジトリ選択
- 記事検索
- ダブルクリックでWorkspace Viewへ移行
- ReturnでWorkspace Viewへ移行
- 各パスのコピー
- FinderでMarkdownを選択表示
- 初回のMarkdownアプリ選択とMarkdown表示
- 保存したMarkdownアプリでの再表示
- Markdownアプリの再設定
- 保存したMarkdownアプリが存在しない場合のエラー表示
- 画像フォルダ作成と表示
- 単一画像ドロップ
- 複数画像ドロップ
- 同名画像の自動リネーム
- 3MB超過画像の拒否
- Markdown記法のコピー
- 画像フルパスのコピー
- Finderで画像を選択表示
- 画像名の変更
- 既存画像と同じ名前への変更拒否
- ダークモード
- アプリ再起動後のリポジトリ復元

## 26. 受け入れ条件

### 26.1 リポジトリ

- 有効なZennリポジトリを選択できる
- 選択したリポジトリが次回起動時に復元される
- 無効なリポジトリを登録しない

### 26.2 記事一覧

- `articles/*.md`のtitleとslugが表示される
- titleまたはslugで検索できる
- Front Matterが不正な記事も一覧から消えない
- ダブルクリックまたはReturnでWorkspace Viewへ移行できる

### 26.3 Markdown操作

- Markdownの絶対パスをコピーできる
- Finderで対象Markdownが選択状態になる
- 初回に選択したアプリで対象Markdownを開ける
- 選択したアプリが次回起動時にも使用される
- `Change Markdown App…`から使用するアプリを変更できる
- 保存したアプリが見つからない場合は、別アプリで開かず再設定を案内する

### 26.4 画像フォルダ操作

- 対応画像フォルダの予定絶対パスをコピーできる
- フォルダがなければ作成してFinderで開ける

### 26.5 画像一覧

- 対応画像だけが一覧表示される
- サムネイル、拡張子を除いた1行のファイル名、ファイルサイズ、拡張子が表示される
- 手動再読み込みで外部変更が反映される

### 26.6 ドロップ

- Finderから画像をドロップして対応画像フォルダへコピーできる
- 複数画像を同時に処理できる
- 同名ファイルを上書きしない
- 3MB超過または対応外形式を拒否する
- コピー後に画像一覧が更新される

### 26.7 画像操作

- Zenn用Markdown記法をコピーできる
- 画像の絶対パスをコピーできる
- Finderで対象画像が選択状態になる
- 画像名を変更でき、変更後の画像が選択状態になる
- 不正な名前や既存ファイルと同じ名前では変更せず、元画像を維持する

### 26.8 品質

- 主要な失敗が無言で終わらない
- UIがファイル操作中に長時間固まらない
- ダークモードとライトモードで操作できる
- 必須ユニットテストが通る
- Xcodeからビルドして起動できる

## 27. 初版の対象外

以下は実装しない。

- Markdown本文の編集
- 記事の新規作成
- 記事の削除
- Front Matterの編集
- slugの変更
- 画像の削除
- 画像編集
- Git commit
- Git push
- Git branch操作
- GitHub API連携
- Zennへのログイン
- `npx zenn preview`の起動
- ブラウザプレビュー
- Zennの本
- Zennのスクラップ
- 複数リポジトリの同時表示
- 常時ファイル監視
- App Sandbox
- アプリ配布、署名、公証
- Windows、Linux対応

対象外の機能を先回りして追加しない。

## 28. 実装上の優先順位

### Phase 1

- Xcodeプロジェクト作成
- リポジトリ選択
- 記事走査
- Front Matter解析
- titleとslug一覧
- 検索
- Workspace Viewへの移行

### Phase 2

- Markdownパスのコピー
- MarkdownのFinder表示
- Markdownを選択した外部アプリで開く
- 画像フォルダパスのコピー
- 画像フォルダの作成とFinder表示

### Phase 3

- 画像一覧
- サムネイル
- 画像選択
- Markdown記法のコピー
- 画像フルパスのコピー
- Finderで画像を選択表示

### Phase 4

- ドラッグ＆ドロップ
- 画像検証
- 複数画像コピー
- 同名ファイル解決
- 一部失敗時の結果表示

### Phase 5

- ショートカット
- アクセシビリティ
- エラー表示の整理
- 画像名の変更
- ユニットテスト
- README
- 最終ビルド確認

## 29. Codexへの実装指示

- 本仕様を実装の正本とする
- 要件を独自解釈して拡張しない
- 初版の対象外機能を追加しない
- macOS専用として実装する
- SwiftUIを主体とし、macOS固有機能だけAppKitを使用する
- 記事一覧取得にZenn CLIを使用しない
- ファイルシステムを正本とし、独自DBを作らない
- Front Matterを正規表現だけで解析しない
- ファイルの上書きを行わない
- エラーを黙って無視しない
- 不要な抽象化や過剰なレイヤー分割を避ける
- コードには意図が分かるコメントを付ける
- 主要なロジックへユニットテストを追加する
- 最終的にXcodeからビルド可能な状態にする
- ルートにREADMEを作成し、ビルド方法と操作方法を記載する

## 30. 完成物

Codexは最低限、以下を作成する。

```text
SlugDock/
├── SlugDock.xcodeproj
├── SlugDock/
├── SlugDockTests/
├── README.md
└── SPEC.md
```

READMEには以下を含める。

- アプリ概要
- 必要環境
- Xcodeでの開き方
- ビルド方法
- 初回起動時のリポジトリ選択
- 基本操作
- 画像フォルダ規約
- 現在の制限
