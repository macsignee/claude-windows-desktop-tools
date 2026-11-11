# 自動ビルド/テスト ホスト側ツール (C++ / .NET)

Claude Code のサンドボックスからは、Windows 側の MSBuild やテスト exe を直接実行できません。
このツールは、Windows 側で動いて **フラグファイルを監視し、ビルド (必要ならテストも) を実行して、結果をファイルに書きます。**
Claude Code は、フラグを置いて、結果ファイルを読むだけです (対応する Skill: `auto-build` / `build-test-loop`)。

**C++ (`.vcxproj` + GoogleTest)、.NET (WPF・WinForms など、SDK 形式の `.csproj` + MSTest)、その混在**のどれでも、同じように使えます。ソリューションの中身を見て、ウォッチャーが、ビルドとテストの方法を決めます (切り替えの設定は不要)。

```
Claude Code (WSL/サンドボックス)            Windows (このツール)
  trigger_build.flag / trigger_test.flag ─▶  watch_and_build.ps1 が検知して削除
  trigger_uitest.flag (UI テスト)
  trigger_gtest.flag (GoogleTest の取得)
  trigger_package.flag (NuGet / vcpkg / ソースの取り込み)
  trigger_vs.flag (Visual Studio の操作: 開く・前面・ブレークポイント・デバッグ実行)
                                             └─ build-windows.cmd ─▶ MSBuild
                                             └─ (テスト時) xxxTest.exe (GoogleTest)
                                                           dotnet test (MSTest / FlaUI)
  build_result.txt / test_result.txt   ◀───  結果を書く (完了マーカー)
  .claude-logs\test-results\*.xml / *.trx  ◀─  テストの、機械可読な結果 (WSL 側が、共通の形式に変換する)
  build_error.log / test_error.log     ◀───  失敗時のみ
```

## 目次
1. [構成](#1-構成)
2. [動作要件](#2-動作要件)
3. [使い方](#3-使い方) — 起動、候補をまとめて起動、フラグごとの使い方 (ビルド・テスト / UI テスト / GoogleTest の取得 / パッケージ)、停止、ps1 の詳細オプション
4. [ファイルの取り決め (Skill との契約)](#4-ファイルの取り決め-skill-との契約)
5. [Git の設定](#5-git-の設定-推奨)
6. [更新手順](#6-更新手順)
7. [トラブルシューティング](#7-トラブルシューティング)
8. [制限事項](#8-制限事項)

## 1. 構成

### ファイル
次のファイルと `lib\` は、**必ず同じフォルダに置く** (置き場所は任意。例: `C:\tools\claude-watcher\`)。

| ファイル | 役割 | 必須 |
|---|---|---|
| `run_watcher.cmd` | 入口。プロジェクトフォルダを指定して ps1 を起動する (ダブルクリック / ドラッグ&ドロップ可) | ○ |
| `watch_and_build.ps1` | **ウォッチャー本体。** 引数、パス解決、ソリューションの判定、二重起動の防止、フラグの監視ループ。機能ごとの関数は、`lib\*.ps1` を読み込む | ○ |
| `lib\*.ps1` (8 ファイル) | `watch_and_build.ps1` が読み込む、機能ごとの関数。`common` (共通)、`build` (ビルドの呼び出し)、`tests` (テストの実行)、`test-results` (結果の解析)、`gtest` (GoogleTest の取得)、`package` (nuget / vcpkg / fetch)、`ui-settings` (`uitest.settings`)、`uitest-desktop` (UI テストのデスクトップ基盤) | ○ |
| `build-windows.cmd` | VS の環境を読み込んで MSBuild を実行する (C++ ツールの要求と NuGet の復元は、第 6 引数で切り替える)。単体でも使える | ○ |
| `run_watcher_visible.cmd` | `run_watcher.cmd` と同じ引数。UI テストを、**ユーザーのデスクトップ**で、操作の間に待ちを入れて実行する (目で確かめるとき。3.3) | 任意 |
| `run_watchers.cmd` | 作業フォルダの下の、候補ごとに、ウォッチャーを起動する (3.2) | 任意 |
| `HOST_VERSION` | このフォルダを、最後に変えたときの、リポジトリの版 (1 行。8 を参照) | — |

`run_watcher.cmd`・`watch_and_build.ps1`・`build-windows.cmd` と `lib\` は、1 つでも欠けると動きません (`lib\` が欠けると、`library script not found` で、終了コード 2)。任意のものを使うときは、同じフォルダに置く。

### ファイルの形式
形式を保ってください (崩れると、日本語コメントが文字化けしたり、ps1 が読めなくなったりします)。

| ファイル | 文字コード | 改行 |
|---|---|---|
| `*.cmd` (`run_watcher.cmd` `run_watcher_visible.cmd` `run_watchers.cmd` `build-windows.cmd`) | **CP932 (Shift_JIS)**。日本語のコメントを含む。画面に出すメッセージは、文字化けを避けるため英語 | CRLF |
| `watch_and_build.ps1`、`lib\*.ps1` | **BOM 付き UTF-8** (Windows PowerShell 5.1 が、BOM がないと CP932 と誤認して日本語が化けるため) | CRLF |

`.cmd` を UTF-8 で保存し直さないでください (日本語環境のコマンドプロンプトで、コメントが化けて、まれにコマンドとして解釈されるおそれがあります)。

## 2. 動作要件
- Windows、Windows PowerShell 5.1 以降
- Visual Studio (リリース版の最新を `vswhere` で自動検出。プレビュー版は対象外)。C++ のプロジェクトがあるソリューションは、C++ ツール `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` 入りであること。**.NET だけのソリューションは、MSBuild (`Microsoft.Component.MSBuild`) があればよい。**
- .NET のプロジェクトがあるソリューションは、**.NET SDK** (`dotnet`。MSBuild の SDK の解決と、`dotnet test` に使う)。NuGet のソースに届くこと (初回の復元)
- ソリューション (`.sln` / `.slnx`)。テストを使う場合は `xxx` と `xxxTest` (C++ は GoogleTest、.NET は MSTest v3 以降 + `Microsoft.NET.Test.Sdk`) が同じソリューションにあり、`xxxTest` が `xxx` をプロジェクト参照していること (ソリューションのビルドで `xxx` → `xxxTest` の順になる)
- 動作確認 (実機の結果は、`docs/TEST-PLAN.md`): VS 2026 Enterprise、x64 / Debug。C++ (GoogleTest。v1.6.0 まで)、.NET (WPF・WinForms + MSTest + FlaUI の UI テスト)、MFC。`Win32` / `ARM64` / `Release` は、ウォッチャーでは未確認 (ウォッチャーの構成は、既定の `Debug` 固定で、`-Configuration` で変える)

## 3. 使い方

### 3.1 起動
```bat
run_watcher.cmd <プロジェクトフォルダ> [ソリューション] [Platform] [Configuration]
```
- 引数なしで起動すると、`run_watcher.cmd` があるフォルダが対象になります。
- ソリューション省略時は、フォルダ内の `.slnx`、なければ `.sln` を自動検出します (両方ある場合は `.slnx` を使い、メッセージを出します)。
- **ソリューションが、まだなくても、起動できます** (`new_solution.py` で作る前に、ウォッチャーを起動しておける)。起動時のヘッダーの `Target` に `(no .sln / .slnx ... yet: it is detected when a trigger arrives)` と出ます。**ソリューションは、トリガー (ビルド・テスト・UI テストのフラグ) が来るたびに、フォルダから探し直します** (起動後に作った・プロジェクトを足した、場合も、再起動は要りません)。トリガーが来たときに、まだなければ、ビルドせずに、`build_result.txt` = `FAILED`、`build_error.log` の先頭が `[ENVIRONMENT ERROR ...]` と `ERROR: no .sln / .slnx found in ...` になります (テストのトリガーのときは `test_result.txt` = `BUILD_FAILED`)。**ただし、引数なしで起動した (`run_watcher.cmd` のあるフォルダが対象になる) ときに、ソリューションがなければ、指定ミスの可能性が高いので、従来どおり、エラーで終了します。**
- Platform: `auto` (既定: C++ のプロジェクトがあれば `x64`、.NET だけなら `AnyCPU`) / `x64` / `Win32` / `x86` / `ARM64` / `AnyCPU`。Configuration: `Debug` (既定) / `Release` など。
- **1 つのウォッチャーは、1 つのプロジェクトフォルダ・1 つの Platform/Configuration 専用です。** 別のプロジェクトは、別のウィンドウで起動します。切り替えるには、起動し直します。
- **同じプロジェクトフォルダで、ウォッチャーを二重には起動できません。** 2 つ目は、`ERROR: a watcher is already running for this folder` と出て、終了コード 3 で終了します (1 つ目が、そのまま使われます)。
- 起動時に、ヘッダー (VS、ビルド構成、`QuickEdit : disabled`、`UI test` の行など) が出ます。
- **停止:** ウィンドウを閉じるか、Ctrl+C。

### 3.2 候補をまとめて起動 (`run_watchers.cmd`、任意)
`/new-solutions` で作った候補を、まとめて起動するときに使います。
```bat
run_watchers.cmd [作業フォルダ] [/list] [/windows]
```
- 作業フォルダ (`solutions.md` があるフォルダ。省略時は、カレントフォルダ) の**直下**のサブフォルダのうち、`.slnx` か `.sln` があるものを候補として、`run_watcher.cmd` を起動します。
- **`wt.exe` (Windows ターミナル) があれば、名前つきのウィンドウ `watchers` の、候補ごとのタブ**で起動します (もう一度実行すると、同じウィンドウに、タブが増えます。動いている候補は、タブに `a watcher is already running` が出て、止まります)。`wt.exe` がないとき、または `/windows` を付けたときは、候補ごとに、別のコンソールのウィンドウです。
- `/list`: 起動せずに、候補の一覧だけを出します (先に確かめるとき)。
- 名前が `.` で始まるフォルダ (`.claude` など) は、飛ばします。すでにウォッチャーが動いている候補は、`run_watcher.cmd` が、二重起動として断ります (壊れません)。
- ウィンドウを閉じると、その候補のウォッチャーだけが止まります。起動したあとに作った候補は、`run_watcher.cmd` で個別に起動するか、もう一度実行します。

### 3.3 フラグごとの使い方
Claude (Skill) が、プロジェクトフォルダに、フラグファイルを置きます。ウォッチャーが検知して、フラグを削除し、処理して、結果のファイルを書きます。ビルド・テストは、**1 件ずつ順番に**処理します (実行中に次のフラグが置かれても、現在の処理が終わってから処理します)。

| フラグ | 依頼の内容 | Skill 側の入口 |
|---|---|---|
| `trigger_build.flag` | ビルドだけ | `auto-build/scripts/build_once.sh` |
| `trigger_test.flag` | ビルド + テスト (両方あれば、こちらが優先) | `build-test-loop/scripts/build_test_once.sh` |
| `trigger_uitest.flag` | ビルド + UI テスト (下記) | `build-test-loop/scripts/uitest_once.sh` |
| `trigger_gtest.flag` | GoogleTest のソースの取得 (下記) | `new-solution/scripts/gtest_once.sh` |
| `trigger_package.flag` | NuGet / vcpkg / ソースの取り込み (4 の表) | `add-package/scripts/package_once.sh` |
| `trigger_vs.flag` | Visual Studio の操作 (下記) | `vs-debug/scripts/vs_once.sh` |

手動でも、空のフラグ (ファイル) を、プロジェクトフォルダに置けば、動かせます。

#### ビルド・テスト (`trigger_build.flag` / `trigger_test.flag`)
- **GoogleTest (C++):** `<ソリューション>\<x64|Win32|ARM64>\<Configuration>\` にある、`-TestExePattern` に一致する exe をすべて実行します (`--gtest_output=xml` を足して、XML も残す)。成功の判定は、終了コード 0 **かつ** 出力に GoogleTest の `[  PASSED  ]` 行があること (引数不正やテスト 0 件を、成功と誤認しないため)。
- **dotnet test (.NET):** ソリューションの `.csproj` / `.vbproj` / `.fsproj` のうち、`Microsoft.NET.Test.Sdk` / `MSTest` を参照するもの、`IsTestProject` が `true` のもの、名前が `Test` / `Tests` で終わるものを、`dotnet test --no-build` で実行します (trx を残す)。成功の判定は、終了コード 0 **かつ** trx の `executed` が 1 以上 (テスト 0 件を、成功と誤認しないため)。**UI テストのプロジェクトは、ここからは除かれます** (下記)。
- 両方ある場合は、両方を実行し、結果は 1 つの `test_result.txt` にまとまります。
- ビルドのあと、ビルドのコマンドの出力 (`build_error.log` / `test_error.log`) のパスは、ソリューションフォルダからの相対パス (`/` 区切り) に変換されます (例: `MyAppTest/TestFoo.cpp(49)`)。Claude がそのまま開けるようにするためです。

#### UI テスト (`trigger_uitest.flag`)
ビルドのあと、**UI テストのプロジェクトだけ** (名前が `UITests` / `UiTests` で終わる、または FlaUI を参照) を、`dotnet test` で実行します。結果のファイルは、`trigger_test.flag` と同じです (`test_result.txt` など)。

- **環境変数:** テストには、`UITEST_SOLUTION_DIR` / `UITEST_CONFIGURATION` / `UITEST_PLATFORM` / `UITEST_SCREENSHOT_DIR` が渡る。失敗時のスクリーンショットは、`.claude-logs\ui-screenshots\` に置く (WSL の Claude が、画像として読める)。テストは、操作の記録 (`.claude-logs\ui-screenshots\ui-trace.txt`) も残す。
- **プロセスの掃除:** 実行の前後に、ソリューションのフォルダの下の exe のプロセス (テストが残したアプリ) を終了する。
- **制限時間:** テストプロジェクト 1 つあたり、`-UiTestTimeoutSec` (既定 600 秒。環境変数 `WATCH_UI_TIMEOUT_SEC`、または、フラグの `timeout=` でも、変えられる)。超えると、`TEST_TIMEOUT`。起動画面の `UI test` の行に、`timeout N s` と出る。
- **実行中は、マウス・キーボードに触らない** (画面のロック、RDP の切断・最小化も避ける。UIA が動かなくなる)。

**フラグの中身** (1 行 1 項目。`#` から行末は、コメント。`uitest.settings` と共通の書式):

| 項目 | 内容 |
|---|---|
| `desktop=visible` / `desktop=separate` (別名 `invisible`) | UI テストを、ユーザーのデスクトップ / 別のデスクトップで、実行する |
| `slowmo=800` | 操作の間隔 (ミリ秒)。ユーザーのデスクトップで、目で確かめるとき |
| `timeout=1800` | この実行の制限時間 (秒。テストプロジェクト 1 つあたり) |
| `filter=<式>` | 実行するテストの絞り込み (`dotnet test --filter`) |
| `hold=60` | 最後の状態を、見せておく秒数 (プレビュー) |
| `present=1` | **プレゼン:** `filter=` で選んだテストだけを、ユーザーのデスクトップで、ゆっくり再生する (操作する要素に、赤い枠)。`filter=` がなければ、無視される |

Skill 側は、`uitest_once.sh <dir> --visible` / `--separate` / `--slowmo 800` / `--filter "<式>"` / `--ui-timeout 1800` / `--preview [秒]` / `--present` と書く。

**どのデスクトップで動くか** (優先順): フラグ > `-UiTestDesktop` / 環境変数 `WATCH_UI_DESKTOP` (`default` / `separate` のとき) > UI テストのプロジェクトの `uitest.settings` (`desktop=visible|separate`、`slowmo=N`) > 別のデスクトップ。`-UiTestDesktop` の既定は `auto` (`uitest.settings` に従う)。UI テストのプロジェクトが複数あるときは、1 つでも `visible` なら `visible`。実行ごとに、`[UI] desktop: ... (理由)` と出る。

- `uitest.settings` は、`add_ui_tests.py` が、プロジェクトを作るときに書く。**WPF には `visible`** (WPF のメニューのポップアップが、別のデスクトップでは、開かないため)、**それ以外には `separate`**。ウォッチャーに、フレームワークごとの判定は、ない。
- **`separate`** (別のデスクトップ。Win32 の `CreateDesktop`): ユーザーの画面にウィンドウが出ず、フォーカスも奪わない。テストが起動して残ったアプリは、ジョブオブジェクトで、すべて終了する。
- **`visible`** (別名 `default`): ユーザーのデスクトップ。ウィンドウが見え、フォーカスを奪うことがある (PC を、快適には使えない)。
- **ウォッチャーを `run_watcher_visible.cmd` に切り替えなくてよい** (1 回ごとに、フラグで指定できる)。`run_watcher_visible.cmd` は、既定を、ユーザーのデスクトップ + 操作の間の待ち (`WATCH_UI_SLOWMO_MS`、既定 800 ミリ秒) にして起動する。待ちは、`watch_and_build.ps1 -UiTestSlowMoMs N` でも指定できる。
- **UI テストの間だけ、WPF をソフトウェアレンダリングにする** (HKCU の `Avalon.Graphics\DisableHWAcceleration`)。元の値は、`%LOCALAPPDATA%\claude-watcher\wpf-hwaccel-backup.txt` に記録して、終了後に復元する。異常終了したときは、次の起動時に復元する。

#### GoogleTest のソースの取得 (`trigger_gtest.flag`)
ビルド・テストとは独立のフラグ。**Windows 側が GitHub に届く**必要がある (git があれば `git clone --depth 1`、なければ zip のダウンロード)。
```
Claude: trigger_gtest.flag を置く (1 行目に、タグ。例: v1.17.0。空なら -GtestTag の既定。2 行目に、実行 ID のコメント `# run=<ID>`)
ホスト: <プロジェクトフォルダ>\ThirdParty\googletest\ に、include\ src\ LICENSE VERSION.txt を置く
        gtest_result.txt = OK / FAILED (最後に書く)。FAILED のときは、gtest_error.log
```
- 同じタグが、すでに置かれていれば、何もせずに `OK`。タグは、`v1.17.0` / `release-1.12.1` の形だけ許可する。
- ソースは、手でコピーしてもよい (`ThirdParty\googletest\include` と `src`)。
- ソリューション内の静的ライブラリ (`gtest.vcxproj`) は、Claude 側 (`add_layer.py` / `/new-solution`) が作る。ウォッチャーは、取得だけ。

#### パッケージの操作 (`trigger_package.flag`)
各行が 1 つの操作です (4 の表)。上から順に実行し、最初の失敗で止まります。`vcpkg.exe` は、`-VcpkgExe` → 環境変数 `VCPKG_ROOT` → Visual Studio 同梱、の順に探します。見つからなければ `ENV_ERROR` (VS の「vcpkg パッケージ マネージャー」コンポーネントを追加する)。

#### Visual Studio の操作 (`trigger_vs.flag`)
各行が 1 つの操作です (空行と `#` 行は無視。上から順に実行し、最初の失敗で止まる)。VS は、実行中のプロセスの表 (ROT。`!VisualStudio.DTE.<版>:<pid>`) から、**`Solution.FullName` がこのソリューションのもの**を探します (版に依らない。VS 2022 / 2026)。複数あれば、`MULTIPLE_INSTANCES` で止まります。

| 操作 | 内容 |
|---|---|
| `open` | VS で開く。開いていなければ、`vswhere.exe` で `devenv.exe` を探し、ソリューションを引数にして起動 (読み込みを待つ)。開いていれば、前面に出す (最小化は戻す) |
| `status` | `SOLUTION:` / `OPEN:` / `INSTANCES:` / `DEBUG_MODE:` (design / run / break) / `DIRTY: <パス>` (未保存のドキュメント) / `DIRTY_COUNT:`。読み取りだけ。VS を起動しない |
| `reload <パス>` | VS で開いていて、未保存の編集がないドキュメントを、閉じて開き直す。未保存なら `RELOAD_SKIP_DIRTY:` |
| `clear` | このツールが置いたブレークポイント (`Tag` = `claude-vs-debug`) だけを消す |
| `break <パス>:<行>` | ブレークポイントを置く (同じ場所にあれば `BREAK_EXISTS:`。最大 20 件)。パスは、ソリューションのフォルダの下の相対パス (`..` と絶対パスは断る) |
| `debug` | デバッグ実行を始める (`DTE.Debugger.Go`)。デザインモードのときだけ。`DEBUG_STARTED` / `DEBUG_MODE:` / break で止まれば `STOPPED:` |

結果は `vs_output.txt` (事実)、失敗時のみ `vs_error.log` (環境の問題は、先頭が `[ENVIRONMENT ERROR - not a source code problem]`)、完了マーカー `vs_result.txt` (`OK` / `FAILED`。最後に書く)。VS が、ダイアログを出して待っていると、COM の呼び出しが拒否され、`TIMEOUT` になることがあります。

#### 実行 ID
Skill のスクリプト (`gtest_once.sh` / `package_once.sh` / ビルド・テスト) は、フラグに実行 ID を書きます (gtest: 2 行目の `# run=<ID>`、package: 先頭のコメント行 `# run=<ID>`、build / test: `run=<ID>`)。古いウォッチャーは、コメントを、タグや操作と取り違えません。ウォッチャーは、結果のマーカーを書く直前に、同じ ID を `.claude-logs\run_id.txt` に書きます (前回の結果と、取り違えないため)。処理の間は、`.claude-logs\watcher_busy.txt` も置きます。

### 3.4 ps1 を直接起動する (詳細オプション)
`run_watcher.cmd` では渡せないオプションを使うときは、ps1 を直接起動します。
```bat
powershell -ExecutionPolicy Bypass -NoProfile -File C:\tools\claude-watcher\watch_and_build.ps1 ^
  -TargetDir C:\proj\MyApp -SolutionPath MyApp.sln -TestTimeoutSec 300
```

| 引数 | 既定値 | 内容 |
|---|---|---|
| `-TargetDir` (必須) | | プロジェクトフォルダ。フラグと結果ファイルはここに置かれる |
| `-SolutionPath` | 自動検出 | ソリューション (相対パスは TargetDir 基準)。省略時は、`.slnx`、なければ `.sln` を、トリガーのときに探す |
| `-Platform` | `auto` | `auto` / `x64` / `Win32` / `x86` / `ARM64` / `AnyCPU`。`auto`: C++ があれば `x64`、.NET だけなら `AnyCPU` |
| `-Configuration` | `Debug` | ビルド構成 |
| `-MSBuildTarget` | `Build` | `Build` / `Rebuild` / `Clean` |
| `-LogDir` | `<TargetDir>\.claude-logs` | 詳細ログの出力先 |
| `-BuildScript` | ps1 と同じフォルダの `build-windows.cmd` | ビルド用バッチ |
| `-TestExePattern` | `(Test\|Tests)\.exe$` | GoogleTest の exe の名前 (正規表現) |
| `-TestArgs` | `--gtest_color=no` | テスト exe に渡す引数 |
| `-TestTimeoutSec` | `120` | テスト exe 1 本あたりの制限時間 (秒) |
| `-TestWorkingDir` | テスト exe のあるフォルダ | GoogleTest の実行時の作業フォルダ |
| `-DotnetTestArgs` | (空) | `dotnet test` に足す引数。例: `-DotnetTestArgs:-p:Platform=x64` (プロジェクトの出力先が、プラットフォーム別のとき)。**値が `-` で始まるので、コロンで結ぶ** (`-DotnetTestArgs "-p:Platform=x64"` は、PowerShell が `-p` をパラメーター名と解釈して、`ambiguous` で失敗する) |
| `-DotnetExe` | `dotnet` | `dotnet` の実行ファイル (PATH にないときは、フルパス) |
| `-UiTestTimeoutSec` | `600` | UI テストの、テストプロジェクト 1 つあたりの制限時間 (秒)。環境変数 `WATCH_UI_TIMEOUT_SEC` |
| `-UiTestDesktop` | `auto` | `auto` / `default` / `visible` / `separate` / `invisible`。環境変数 `WATCH_UI_DESKTOP` (3.3) |
| `-UiTestSlowMoMs` | `0` | UI テストの、操作の間隔 (ミリ秒)。環境変数 `WATCH_UI_SLOWMO_MS` |
| `-PackageTimeoutSec` | `1800` | パッケージの操作 1 件の制限時間 (秒)。`vcpkg install` は、ポートのビルドで長い |
| `-VcpkgExe` | (自動) | `vcpkg.exe`。省略時: 環境変数 `VCPKG_ROOT`、なければ Visual Studio 同梱 (`VC\vcpkg\vcpkg.exe`) |
| `-VcpkgTriplet` | (自動) | vcpkg のトリプレット。省略時は Platform から (`x64-windows-static-md` / `x86-...` / `arm64-...`) |

### 3.5 ビルドだけを単体で実行する
```bat
build-windows.cmd <target> <Platform> [Configuration] [MSBuildTarget] [LogDir] [Features]
```
`Features`: カンマ区切り。`cpp` (C++ ツール入りの VS を要求し、cl.exe を確認する。**省略時の既定**)、`restore` (`/restore`。.NET 用。`Clean` では付けない)。例: `build-windows.cmd MyApp.sln AnyCPU Debug Build "" restore`

終了コード: `0` 成功 / `1` ビルド失敗 / `2` 引数不正 / `10` vswhere なし / `11` 必要な構成要素入りの VS なし / `12` VsDevCmd なし / `13` VsDevCmd 失敗 / `14` MSBuild.exe (`cpp` なら cl.exe も) が見つからない

## 4. ファイルの取り決め (Skill との契約)
すべて `<TargetDir>` (ソリューションフォルダ) に置かれます。**ここを変えると、Skill 側も同時に直す必要があります。**

| ファイル | 作る人 | 内容 |
|---|---|---|
| `trigger_build.flag` | Claude | 空ファイル (または実行 ID)。ビルドのみを依頼。ウォッチャーが検知して削除する |
| `trigger_test.flag` | Claude | ビルド + テストを依頼 (両方あればこちらが優先) |
| `trigger_uitest.flag` | Claude | ビルド + UI テストを依頼。中身は、3.3 の「フラグの中身」 |
| `trigger_gtest.flag` | Claude | GoogleTest のソースの取得を依頼 (3.3) |
| `trigger_package.flag` | Claude | パッケージの操作を依頼。各行が 1 つの操作 (下の表) |
| `trigger_vs.flag` | Claude | Visual Studio の操作を依頼。各行が 1 つの操作 (3.3 の「Visual Studio の操作」) |
| `build_result.txt` | ウォッチャー | ビルド終了時に `SUCCESS` / `FAILED`。**ビルドのみの完了マーカー** |
| `build_error.log` | ウォッチャー | ビルド失敗時のみ。エラー行 (相対パス) |
| `test_result.txt` | ウォッチャー | **ビルド + テストの完了マーカー (最後に書かれる)**。下の表 |
| `test_error.log` | ウォッチャー | テスト失敗 / タイムアウト / 環境エラー時のみ |
| `gtest_result.txt` / `gtest_error.log` | ウォッチャー | GoogleTest の取得の結果 (`OK` / `FAILED`。最後に書く) / 失敗時のみ |
| `package_output.txt` | ウォッチャー | 各操作の出力 (`## <操作>` の見出し付き) |
| `package_error.log` | ウォッチャー | 失敗時のみ。環境の問題 (ネットワーク、`dotnet` / `vcpkg` がない) は、先頭が `[ENVIRONMENT ERROR - not a source code problem]` |
| `package_result.txt` | ウォッチャー | **パッケージの完了マーカー** (最後に書かれる): `OK` / `FAILED` |
| `vs_output.txt` / `vs_error.log` / `vs_result.txt` | ウォッチャー | Visual Studio の操作の、事実 / 失敗時のみ (環境の問題は、先頭が `[ENVIRONMENT ERROR ...]`) / **完了マーカー** (最後に書かれる): `OK` / `FAILED` |
| `.claude-logs\build.log` `errors.log` `warnings.log` `test.log` | ウォッチャー | 詳細ログ (フルパスのまま) |
| `.claude-logs\test-results\<exe名>.xml` `<プロジェクト名>.trx` | ウォッチャー | テストの、機械可読な結果 (GoogleTest の XML、MSTest の trx)。テストの開始時に、前回分が削除される。WSL 側の `summarize_test_log.py` が読む |
| `.claude-logs\ui-screenshots\` | テスト | UI テストの、スクリーンショットと、操作の記録 `ui-trace.txt` (実行のたびに、上書き) |
| `.claude-logs\ui-timing.txt` | ウォッチャー | UI テストの、各段階の時刻 (トリガーの検知、ビルド完了、テストの開始・終了など)。実行のたびに、上書き |
| `.claude-logs\run_id.txt` `watcher_busy.txt` | ウォッチャー | 実行 ID (結果のマーカーを書く直前) / 処理の間だけ置かれる印 |

各ファイルは、新しい依頼の開始時に、前回分が削除されます。

**パッケージの操作 (`trigger_package.flag`)**: 引数は、コマンドに渡るので、決まった文字だけが通ります。

| 操作 | 内容 |
|---|---|
| `nuget search <語>` / `nuget versions <ID>` | nuget.org の検索 (ダウンロード数・発行元の確認済みも出す) / バージョンの一覧 |
| `nuget add <プロジェクト> <ID> [<バージョン>]` / `nuget remove ...` | `dotnet add / remove package`。プロジェクトは、ソリューションの下の `.csproj` などの相対パス |
| `vcpkg search <語>` | `vcpkg search` |
| `vcpkg baseline` | `vcpkg x-update-baseline --add-initial-baseline` (`vcpkg.json` の `builtin-baseline`) |
| `vcpkg install` | `vcpkg install --triplet <Platform から>` (マニフェストモード。`vcpkg.json` が要る) |
| `fetch <owner/repo> <タグ> <名前> [<サブフォルダ>]` | GitHub のタグのソースを、`ThirdParty\<名前>\` に置く (同じ内容なら、何もしない) |

**`test_result.txt` の値:**

| 値 | 意味 |
|---|---|
| `PASSED` | ビルド成功・全テスト成功 |
| `FAILED` | テスト失敗 (または異常終了)。`test_error.log` に失敗したテストと期待値 / 実際の値 |
| `TIMEOUT` | テストが制限時間内に終わらない。`test_error.log` に `Hung test (was running when killed): ...` |
| `BUILD_FAILED` | ビルド失敗のためテスト未実行。`build_error.log` を見る |
| `ENV_ERROR` | テスト (GoogleTest の exe も .NET のテストプロジェクトも) が見つからない、`dotnet` がない、テストが 1 件も実行されない等。`test_error.log` の先頭が `[ENVIRONMENT ERROR - not a source code problem]` |

## 5. Git の設定 (推奨)
生成ファイルを、コミットしないようにします (`.gitignore`)。`/new-solution` が作る `.gitignore` は、`.claude-logs/` を含みます。
```
.claude-logs/
trigger_*.flag
build_result.txt
build_error.log
test_result.txt
test_error.log
gtest_result.txt
gtest_error.log
package_output.txt
package_error.log
package_result.txt
```
すでにコミット済みなら、追跡を外します: `git rm -r --cached .claude-logs build_result.txt`

## 6. 更新手順
1. 新しい版を、**一式 (`lib\` を含む)** 上書きコピーする。`install/install.sh` で配るのが確実 (既定のコピー先: `/mnt/c/tools/claude-watcher`)。一部だけ更新しない。
2. 形式が崩れていないか確認する (`.ps1` が BOM 付きなら `239 187 191` と出る)。
   ```powershell
   Get-Content watch_and_build.ps1 -Encoding Byte -TotalCount 3     # PowerShell 7 は -AsByteStream
   ```
3. 稼働中のウォッチャーを閉じて、起動し直す (稼働中のウォッチャーは、古い ps1 のまま動き続ける)。

## 7. トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| ビルド/テストが途中で止まる。ウィンドウのタイトルに `選択` と出る | コンソールをクリックすると出力が一時停止する (クイック編集)。Enter か Esc で再開。起動時のヘッダーが `QuickEdit : disabled` なら発生しない (`not changed` なら Windows Terminal などで無効化できていない。従来のコンソールで起動する) |
| `ERROR: no .sln / .slnx found in <cmd のあるフォルダ>` | 引数なしで起動したため、`run_watcher.cmd` のあるフォルダが対象になった。プロジェクトのフォルダを、引数で渡す (例: `run_watcher.cmd C:\path\to\MyApp`、またはプロジェクトのフォルダから `run_watcher.cmd .`) |
| `ERROR: a watcher is already running for this folder` (終了コード 3) | 同じプロジェクトフォルダで、すでに別のウォッチャーが動いている。そのウィンドウを使うか、閉じてから、起動し直す。見当たらない場合は、最小化されたウィンドウや、別のユーザーのセッションを、確認する |
| `パラメーター 'SolutionPath' の引数が指定されていません` | (古い版のウォッチャー) ソリューションが空で渡っている。最新版では、省略できる (トリガーのときに、フォルダから探す)。古い版なら、フォルダに `.sln` / `.slnx` があるか、`run_watcher.cmd` の第 2 引数で指定する |
| ビルドのトリガーを置くと、`ERROR: no .sln / .slnx found in ...` (`build_result.txt` = `FAILED`) | ウォッチャーが見ているフォルダに、まだソリューションがない。`new_solution.py` で作ってから、もう一度トリガーを置く (ウォッチャーの再起動は、不要)。フォルダが違うなら、ヘッダーの `Target` の行 (またはフォルダ名) を、確かめる |
| `ParserError` や、ps1 の日本語の文字化け | `.ps1` の BOM が落ちている。BOM 付き UTF-8 で保存し直す |
| `.cmd` のコメントが文字化けする、`'xxx' は、内部コマンドまたは外部コマンド...` のようなエラーが出る | `.cmd` が UTF-8 などで保存し直された。CP932 (Shift_JIS) で保存し直す |
| `ENV_ERROR` (テストが見つからない) | C++: ビルド構成 (Platform/Configuration) と、`<ソリューション>\<x64\|Win32\|ARM64>\<Configuration>\` に exe があるか、`-TestExePattern` が名前に合っているかを確認。.NET: テストプロジェクトが、ソリューションに入っているか、`Microsoft.NET.Test.Sdk` を参照しているか (名前が `Test` / `Tests` で終わるかでも、拾われる) |
| `ENV_ERROR` (no tests were executed) | .NET: `dotnet test` が終了コード 0 でも、trx がない、または `executed=0`。`Microsoft.NET.Test.Sdk` と MSTest のアダプタ (`MSTest` パッケージ) を参照しているか、`[TestMethod]` があるかを確認 |
| .NET のテストで `FAILED`、`no test results: the test host crashed, or dotnet test failed before running tests` | `--no-build` が、アセンブリを見つけられない (出力先が `bin\x64\Debug` など、プラットフォーム別) → `-DotnetTestArgs:-p:Platform=x64` (コロンで結ぶ)。または、テストホストのクラッシュ (`test.log` を見る) |
| .NET のテストが `ENV_ERROR`、`test_error.log` に `the test assembly that was run is older than a build output in another folder` | 出力先が `bin\x64\Debug` などなのに、`dotnet test --no-build` が `bin\Debug` の古い DLL を実行しようとした (偽の成功の防止)。`-DotnetTestArgs:-p:Platform=x64` を付けて起動し直す。または、古い `bin` を消す |
| .NET のビルドで `ENV_ERROR` (`MSB4236` / `NETSDK1045` / `NETSDK1141` / `NU1301`) | .NET SDK が、見つからない / 古い (`global.json`、対象フレームワーク) / NuGet のソースに届かない。SDK のインストールと、ネットワークを確認する |
| `ENV_ERROR` (no gtest summary) | テスト exe が GoogleTest でない、または `-TestArgs` が不正 (古い GoogleTest は `--gtest_brief` を知らず、ヘルプだけ表示して終了コード 0 になる) |
| テストが `TIMEOUT` になる | 全体の実行時間が制限 (既定 120 秒) を超えている。`-TestTimeoutSec` を延ばす。`Hung test` は、打ち切られた時点のテスト名で、必ずしもハングしたテストではない。UI テストは、`-UiTestTimeoutSec` / `timeout=` (3.3) |
| UI テストが、途中で動かなくなる、要素が見つからない | 実行中に、画面のロック・RDP の切断・最小化・マウスやキーボードの操作が、あった。UIA が動かなくなる。やり直す (3.3 の「実行中は、触らない」)。WPF のメニューのポップアップは、別のデスクトップでは、開かない (`--visible` で実行する) |
| Claude 側で `WATCHER_NOT_RUNNING` | ウォッチャーが起動していない (フラグが 15 秒回収されない)。対象プロジェクト用に `run_watcher.cmd` を起動する |
| ビルド環境のエラー (`ENV_ERROR`、VS が見つからない等) | `[ENVIRONMENT ERROR ...]` のメッセージに従う。C++ のソリューションは VS の C++ ワークロード (**C++ ツールのない VS では、C++ のビルドはできない。Visual Studio Installer で「変更」→「C++ によるデスクトップ開発」を、手で追加する**。`no Visual Studio with C++ x86/x64 tools found`、終了コード 11)。**逆に、.NET のビルドで `MSB4236` / `NETSDK1045` / `NETSDK1141`、または `dotnet` が見つからない場合は、Visual Studio Installer で「変更」→「.NET デスクトップ開発」を手で追加する (または .NET SDK をインストールする)** (案内の行が `build_error.log` / `test_error.log` / `package_error.log` に付く) |
| `-ExecutionPolicy Bypass` が組織のポリシーで拒否される | IT 管理者に確認する |
| ダウンロードしたファイルがブロックされる | `Get-ChildItem <フォルダ> -Recurse \| Unblock-File` |

## 8. 制限事項
- テストは、C++ は **GoogleTest のみ**、.NET は **MSTest (VSTest モード)** が対象です (xUnit / NUnit は動く見込みですが、未検証。C++ の `CppUnitTestFramework` と、`Microsoft.Testing.Platform` モードの MSTest は、未対応)。
- パッケージの操作の `search` / `versions` は、nuget.org だけを引きます (社内フィードは見えません。`add` は、ホストの NuGet の設定どおりに動きます)。vcpkg のマニフェストモードと MSBuild の連携は、実機で未確認です (`docs/TEST-PLAN.md` の P 系)。
- .NET のビルドは、VS の MSBuild で行います (VS のない環境での `dotnet build` へのフォールバックは、ありません)。
- .NET のテストプロジェクトの判定は、プロジェクトファイルの中身と名前で行います (`Directory.Build.props` で `IsTestProject` を指定している場合は、名前が `Test` / `Tests` で終わる必要があります)。
- 1 つのウォッチャーは、1 つのプロジェクトと 1 つの Platform/Configuration 専用です。切り替えるには、起動し直します。
- テスト実行時の作業フォルダの既定は、テスト exe のあるフォルダです。プロジェクトフォルダ基準の相対パスでデータを読むテストは、`-TestWorkingDir` が必要です。
- Claude Code (サンドボックス) は、このフォルダのファイルを実行しません。ユーザーが Windows 側で起動します。
- **`HOST_VERSION` (このフォルダ。1 行の版):** ホスト側 (この `host-tools/` の、動作に関わるファイル) を最後に変えたときの、リポジトリの版 (`VERSION`)。**`host-tools/` の中の、動作に関わるファイル (`*.cmd` / `*.ps1` / `lib\`) を変えたら、`HOST_VERSION` を、その版に上げる** (この `README.md` のような、説明だけの変更では、上げない)。`install.sh` が、各 Skill に置き、Skill のスクリプトは、ウォッチャーの版がこれより古いときだけ、「版の不一致」の警告 (NOTE) を出す。Skill だけを配ったときの、毎回の警告を避けるため (DESIGN 4.77)。
