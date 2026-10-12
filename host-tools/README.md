# C++ 自動ビルド/テスト ホスト側ツール

Claude Code のサンドボックスからは、Windows 側の MSBuild やテスト exe を直接実行できません。
このツールは、Windows 側で動いて **フラグファイルを監視し、ビルド (必要ならテストも) を実行して、結果をファイルに書きます。**
Claude Code は、フラグを置いて、結果ファイルを読むだけです (対応する Skill: `cpp-auto-build` / `cpp-build-test-loop`)。

```
Claude Code (WSL/サンドボックス)            Windows (このツール)
  trigger_build.flag / trigger_test.flag ─▶  watch_and_build.ps1 が検知して削除
                                             └─ build-windows.cmd ─▶ MSBuild
                                             └─ (テスト時) xxxTest.exe (GoogleTest)
  build_result.txt / test_result.txt   ◀───  結果を書く (完了マーカー)
  build_error.log / test_error.log     ◀───  失敗時のみ
```

## 1. 構成 (3ファイルは必ず同じフォルダに置く)

| ファイル | 役割 |
|---|---|
| `run_watcher.cmd` | 入口。プロジェクトフォルダを指定して ps1 を起動する (ダブルクリック/ドラッグ&ドロップ可) |
| `watch_and_build.ps1` | **ウォッチャー本体。** フラグ監視、ビルド/テスト実行、結果ファイルの書き出し |
| `build-windows.cmd` | VS (C++) の環境を読み込んで MSBuild を実行する。単体でも使える |

置き場所は任意です (例: `C:\tools\cpp-watcher\`)。**1つでも欠けると動きません。**
ファイルの形式を保ってください (崩れると、日本語コメントが文字化けしたり、ps1 が読めなくなったりします)。

| ファイル | 文字コード | 改行 |
|---|---|---|
| `run_watcher.cmd` `build-windows.cmd` | **CP932 (Shift_JIS)**。日本語のコメントを含む。画面に出すメッセージは、文字化けを避けるため英語 | CRLF |
| `watch_and_build.ps1` | **BOM 付き UTF-8** (Windows PowerShell 5.1 が、BOM がないと CP932 と誤認して日本語が化けるため) | CRLF |

`.cmd` を UTF-8 で保存し直さないでください (日本語環境のコマンドプロンプトで、コメントが化けて、まれにコマンドとして解釈されるおそれがあります)。

## 2. 動作要件
- Windows、Windows PowerShell 5.1 以降
- Visual Studio (C++ ツール `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` 入り。リリース版の最新を `vswhere` で自動検出。プレビュー版は対象外)
- ソリューション (`.sln` / `.slnx`)。テストを使う場合は `xxx` と `xxxTest` (GoogleTest) が同じソリューションにあり、`xxxTest` が `xxx` をプロジェクト参照していること (ソリューションのビルドで `xxx` → `xxxTest` の順になる)
- 動作確認済み: VS 2026 Enterprise、x64 / Debug、GoogleTest。`Win32` / `ARM64` / `Release` は未確認

## 3. 使い方

### 起動
```bat
run_watcher.cmd <プロジェクトフォルダ> [ソリューション] [Platform] [Configuration]
```
- 引数なしで起動すると、`run_watcher.cmd` があるフォルダが対象になります。
- ソリューション省略時は、フォルダ内の `.slnx`、なければ `.sln` を自動検出します (両方ある場合は `.slnx` を使い、メッセージを出します)。
- Platform: `x64` (既定) / `Win32` / `x86` / `ARM64`。Configuration: `Debug` (既定) / `Release` など。
- **1つのウォッチャーは、1つのプロジェクトフォルダ・1つの Platform/Configuration 専用です。** 別のプロジェクトは、別のウィンドウで起動します。
- 起動時に、ヘッダー (VS、ビルド構成、`QuickEdit : disabled` など) が出ます。

### 停止
ウィンドウを閉じるか、Ctrl+C。

### ps1 を直接起動する (詳細オプション)
`run_watcher.cmd` では渡せないオプションを使うときは、ps1 を直接起動します。
```bat
powershell -ExecutionPolicy Bypass -NoProfile -File C:\tools\cpp-watcher\watch_and_build.ps1 ^
  -TargetDir C:\proj\MyApp -SolutionPath MyApp.sln -TestTimeoutSec 300
```

| 引数 | 既定値 | 内容 |
|---|---|---|
| `-TargetDir` (必須) | | プロジェクトフォルダ。フラグと結果ファイルはここに置かれる |
| `-SolutionPath` (必須) | | ソリューション (相対パスは TargetDir 基準) |
| `-Platform` | `x64` | `x64` / `Win32` / `x86` / `ARM64` |
| `-Configuration` | `Debug` | ビルド構成 |
| `-MSBuildTarget` | `Build` | `Build` / `Rebuild` / `Clean` |
| `-LogDir` | `<TargetDir>\.claude-logs` | 詳細ログの出力先 |
| `-BuildScript` | ps1 と同じフォルダの `build-windows.cmd` | ビルド用バッチ |
| `-TestExePattern` | `(Test\|Tests)\.exe$` | テスト exe の名前 (正規表現) |
| `-TestArgs` | `--gtest_color=no` | テスト exe に渡す引数 |
| `-TestTimeoutSec` | `120` | テスト exe 1本あたりの制限時間 (秒) |
| `-TestWorkingDir` | テスト exe のあるフォルダ | テスト実行時の作業フォルダ |

### ビルドだけを単体で実行する
```bat
build-windows.cmd <target> <Platform> [Configuration] [MSBuildTarget] [LogDir]
```
終了コード: `0` 成功 / `1` ビルド失敗 / `2` 引数不正 / `10` vswhere なし / `11` VS(C++) なし / `12` VsDevCmd なし / `13` VsDevCmd 失敗 / `14` cl.exe か MSBuild.exe が見つからない

## 4. ファイルの取り決め (Skill との契約)
すべて `<TargetDir>` (ソリューションフォルダ) に置かれます。**ここを変えると、Skill 側も同時に直す必要があります。**

| ファイル | 作る人 | 内容 |
|---|---|---|
| `trigger_build.flag` | Claude | 空ファイル。ビルドのみを依頼。ウォッチャーが検知して削除する |
| `trigger_test.flag` | Claude | 空ファイル。ビルド + テストを依頼 (両方あればこちらが優先) |
| `build_result.txt` | ウォッチャー | ビルド終了時に `SUCCESS` / `FAILED`。**ビルドのみの完了マーカー** |
| `build_error.log` | ウォッチャー | ビルド失敗時のみ。エラー行 (相対パス) |
| `test_result.txt` | ウォッチャー | **ビルド + テストの完了マーカー (最後に書かれる)**。下表 |
| `test_error.log` | ウォッチャー | テスト失敗/タイムアウト/環境エラー時のみ |
| `.claude-logs\build.log` `errors.log` `warnings.log` `test.log` | ウォッチャー | 詳細ログ (フルパスのまま) |

`test_result.txt` の値:

| 値 | 意味 |
|---|---|
| `PASSED` | ビルド成功・全テスト成功 |
| `FAILED` | テスト失敗 (または異常終了)。`test_error.log` に失敗したテストと期待値/実際の値 |
| `TIMEOUT` | テストが制限時間内に終わらない。`test_error.log` に `Hung test (was running when killed): ...` |
| `BUILD_FAILED` | ビルド失敗のためテスト未実行。`build_error.log` を見る |
| `ENV_ERROR` | テスト exe が見つからない等。`test_error.log` の先頭が `[ENVIRONMENT ERROR - not a source code problem]` |

補足:
- 各ファイルは、新しい依頼の開始時に、前回分が削除されます。
- `build_error.log` / `test_error.log` のパスは、ソリューションフォルダからの相対パス (`/` 区切り) に変換されます (例: `MyAppTest/TestFoo.cpp(49)`)。Claude がそのまま開けるようにするためです。
- ビルド/テストは、**1件ずつ順番に**処理されます。実行中に次のフラグが置かれても、現在の処理が終わってから処理されます。
- テストは、`<ソリューション>\<x64|Win32|ARM64>\<Configuration>\` にある、`-TestExePattern` に一致する exe をすべて実行します。成功の判定は、終了コード 0 **かつ** 出力に GoogleTest の `[  PASSED  ]` 行があること (引数不正やテスト 0 件を、成功と誤認しないため)。

## 5. Git の設定 (推奨)
生成ファイルを、コミットしないようにします (`.gitignore`)。
```
.claude-logs/
trigger_build.flag
trigger_test.flag
build_result.txt
build_error.log
test_result.txt
test_error.log
```
すでにコミット済みなら、追跡を外します: `git rm -r --cached .claude-logs build_result.txt`

## 6. 更新手順
1. 新しい版の **3ファイルをまとめて** 上書きコピーする (一部だけ更新しない)。
2. 形式が崩れていないか確認する (`.ps1` が BOM 付きなら `239 187 191` と出る)。
   ```powershell
   Get-Content watch_and_build.ps1 -Encoding Byte -TotalCount 3     # PowerShell 7 は -AsByteStream
   ```
3. 稼働中のウォッチャーを閉じて、起動し直す (稼働中のウォッチャーは、古い ps1 のまま動き続ける)。

## 7. トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| ビルド/テストが途中で止まる。ウィンドウのタイトルに `選択` と出る | コンソールをクリックすると出力が一時停止する (クイック編集)。Enter か Esc で再開。起動時のヘッダーが `QuickEdit : disabled` なら発生しない (`not changed` なら Windows Terminal などで無効化できていない。従来のコンソールで起動する) |
| `パラメーター 'SolutionPath' の引数が指定されていません` | ソリューションが空で渡っている。フォルダに `.sln` / `.slnx` があるか、`run_watcher.cmd` の第2引数で指定する |
| `ParserError` や、ps1 の日本語の文字化け | `.ps1` の BOM が落ちている。BOM 付き UTF-8 で保存し直す |
| `.cmd` のコメントが文字化けする、`'xxx' は、内部コマンドまたは外部コマンド...` のようなエラーが出る | `.cmd` が UTF-8 などで保存し直された。CP932 (Shift_JIS) で保存し直す |
| `ENV_ERROR` (テスト exe が見つからない) | ビルド構成 (Platform/Configuration) と、`<ソリューション>\<x64\|Win32\|ARM64>\<Configuration>\` に exe があるか、`-TestExePattern` が名前に合っているかを確認 |
| `ENV_ERROR` (no gtest summary) | テスト exe が GoogleTest でない、または `-TestArgs` が不正 (古い GoogleTest は `--gtest_brief` を知らず、ヘルプだけ表示して終了コード 0 になる) |
| テストが `TIMEOUT` になる | 全体の実行時間が制限 (既定 120 秒) を超えている。`-TestTimeoutSec` を延ばす。`Hung test` は、打ち切られた時点のテスト名で、必ずしもハングしたテストではない |
| Claude 側で `WATCHER_NOT_RUNNING` | ウォッチャーが起動していない (フラグが 15 秒回収されない)。対象プロジェクト用に `run_watcher.cmd` を起動する |
| ビルド環境のエラー (`ENV_ERROR`、VS が見つからない等) | `[ENVIRONMENT ERROR ...]` のメッセージに従う。VS の C++ ワークロードのインストールを確認する |
| `-ExecutionPolicy Bypass` が組織のポリシーで拒否される | IT 管理者に確認する |
| ダウンロードしたファイルがブロックされる | `Get-ChildItem <フォルダ> -Recurse \| Unblock-File` |

## 8. 制限事項
- テストは **GoogleTest のみ** 対応です (MSTest などは未対応)。
- 1つのウォッチャーは、1つのプロジェクトと 1つの Platform/Configuration 専用です。切り替えるには、起動し直します。
- テスト実行時の作業フォルダの既定は、テスト exe のあるフォルダです。プロジェクトフォルダ基準の相対パスでデータを読むテストは、`-TestWorkingDir` が必要です。
- Claude Code (サンドボックス) は、この 3 ファイルを実行しません。ユーザーが Windows 側で起動します。
