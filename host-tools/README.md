# 自動ビルド/テスト ホスト側ツール (C++ / .NET)

Claude Code のサンドボックスからは、Windows 側の MSBuild やテスト exe を直接実行できません。
このツールは、Windows 側で動いて **フラグファイルを監視し、ビルド (必要ならテストも) を実行して、結果をファイルに書きます。**
Claude Code は、フラグを置いて、結果ファイルを読むだけです (対応する Skill: `auto-build` / `build-test-loop`)。

**C++ (`.vcxproj` + GoogleTest)、.NET (WPF など、SDK 形式の `.csproj` + MSTest)、その混在**のどれでも、同じように使えます。ソリューションの中身を見て、ウォッチャーが、ビルドとテストの方法を決めます (切り替えの設定は不要)。

```
Claude Code (WSL/サンドボックス)            Windows (このツール)
  trigger_build.flag / trigger_test.flag ─▶  watch_and_build.ps1 が検知して削除
  trigger_gtest.flag (GoogleTest の取得)
  trigger_package.flag (NuGet / vcpkg / ソースの取り込み)
                                             └─ build-windows.cmd ─▶ MSBuild
                                             └─ (テスト時) xxxTest.exe (GoogleTest)
                                                           dotnet test (MSTest)  ※ .NET のテストプロジェクトがあるとき
  build_result.txt / test_result.txt   ◀───  結果を書く (完了マーカー)
  .claude-logs\test-results\*.xml / *.trx  ◀─  テストの、機械可読な結果 (WSL 側が、共通の形式に変換する)
  build_error.log / test_error.log     ◀───  失敗時のみ
```

## 1. 構成 (3ファイルは必ず同じフォルダに置く)

| ファイル | 役割 |
|---|---|
| `run_watcher.cmd` | 入口。プロジェクトフォルダを指定して ps1 を起動する (ダブルクリック/ドラッグ&ドロップ可) |
| `watch_and_build.ps1` | **ウォッチャー本体。** フラグ監視、ビルド/テスト実行、GoogleTest のソース取得、結果ファイルの書き出し |
| `build-windows.cmd` | VS の環境を読み込んで MSBuild を実行する (C++ ツールの要求と NuGet の復元は、第 6 引数で切り替える)。単体でも使える |

置き場所は任意です (例: `C:\tools\cpp-watcher\`)。**1つでも欠けると動きません。**
ファイルの形式を保ってください (崩れると、日本語コメントが文字化けしたり、ps1 が読めなくなったりします)。

| ファイル | 文字コード | 改行 |
|---|---|---|
| `run_watcher.cmd` `build-windows.cmd` | **CP932 (Shift_JIS)**。日本語のコメントを含む。画面に出すメッセージは、文字化けを避けるため英語 | CRLF |
| `watch_and_build.ps1` | **BOM 付き UTF-8** (Windows PowerShell 5.1 が、BOM がないと CP932 と誤認して日本語が化けるため) | CRLF |

`.cmd` を UTF-8 で保存し直さないでください (日本語環境のコマンドプロンプトで、コメントが化けて、まれにコマンドとして解釈されるおそれがあります)。

## 2. 動作要件
- Windows、Windows PowerShell 5.1 以降
- Visual Studio (リリース版の最新を `vswhere` で自動検出。プレビュー版は対象外)。C++ のプロジェクトがあるソリューションは、C++ ツール `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` 入りであること。**.NET だけのソリューションは、MSBuild (`Microsoft.Component.MSBuild`) があればよい。**
- .NET のプロジェクトがあるソリューションは、**.NET SDK** (`dotnet`。MSBuild の SDK の解決と、`dotnet test` に使う)。NuGet のソースに届くこと (初回の復元)
- ソリューション (`.sln` / `.slnx`)。テストを使う場合は `xxx` と `xxxTest` (C++ は GoogleTest、.NET は MSTest v3 以降 + `Microsoft.NET.Test.Sdk`) が同じソリューションにあり、`xxxTest` が `xxx` をプロジェクト参照していること (ソリューションのビルドで `xxx` → `xxxTest` の順になる)
- 動作確認済み: VS 2026 Enterprise、x64 / Debug、GoogleTest (C++ のみ。v1.6.0 まで)。**.NET (WPF + MSTest)、混在、`-Platform auto` は、Windows 側で、まだ確認していません** (`docs/TEST-PLAN.md` の 1-5)。`Win32` / `ARM64` / `Release` も未確認

## 3. 使い方

### 起動
```bat
run_watcher.cmd <プロジェクトフォルダ> [ソリューション] [Platform] [Configuration]
```
- 引数なしで起動すると、`run_watcher.cmd` があるフォルダが対象になります。
- ソリューション省略時は、フォルダ内の `.slnx`、なければ `.sln` を自動検出します (両方ある場合は `.slnx` を使い、メッセージを出します)。
- **ソリューションが、まだなくても、起動できます** (`new_solution.py` で作る前に、ウォッチャーを起動しておける)。起動時のヘッダーの `Target` に `(no .sln / .slnx ... yet: it is detected when a trigger arrives)` と出ます。**ソリューションは、トリガー (ビルド・テスト・UI テストのフラグ) が来るたびに、フォルダから探し直します** (起動後に作った・プロジェクトを足した、場合も、再起動は要りません)。トリガーが来たときに、まだなければ、ビルドせずに、`build_result.txt` = `FAILED`、`build_error.log` の先頭が `[ENVIRONMENT ERROR ...]` と `ERROR: no .sln / .slnx found in ...` になります (テストのトリガーのときは `test_result.txt` = `BUILD_FAILED`)。**ただし、引数なしで起動した (`run_watcher.cmd` のあるフォルダが対象になる) ときに、ソリューションがなければ、指定ミスの可能性が高いので、従来どおり、エラーで終了します。**
- Platform: `auto` (既定: C++ のプロジェクトがあれば `x64`、.NET だけなら `AnyCPU`) / `x64` / `Win32` / `x86` / `ARM64` / `AnyCPU`。Configuration: `Debug` (既定) / `Release` など。
- **1つのウォッチャーは、1つのプロジェクトフォルダ・1つの Platform/Configuration 専用です。** 別のプロジェクトは、別のウィンドウで起動します。
- **同じプロジェクトフォルダで、ウォッチャーを二重には起動できません。** 2つ目は、`ERROR: a watcher is already running for this folder` と出て、終了コード 3 で終了します (1つ目が、そのまま使われます)。
- 起動時に、ヘッダー (VS、ビルド構成、`QuickEdit : disabled` など) が出ます。

### GoogleTest のソースを取得する (`trigger_gtest.flag`)
ビルド・テストとは独立の、3 つ目のフラグ。**Windows 側が GitHub に届く**必要がある (git があれば `git clone --depth 1`、なければ zip のダウンロード)。
```
Claude: trigger_gtest.flag を置く (1 行目に、タグ。例: v1.17.0。空なら -GtestTag の既定)
ホスト: <プロジェクトフォルダ>\ThirdParty\googletest\ に、include\ src\ LICENSE VERSION.txt を置く
        gtest_result.txt = OK / FAILED (最後に書く)。FAILED のときは、gtest_error.log
```
- 同じタグが、すでに置かれていれば、何もせずに `OK`。
- タグは、`v1.17.0` / `release-1.12.1` の形だけ許可する。
- 手動でも、フラグ (空のファイル) を、プロジェクトフォルダに置けば、取得できる。ソースは、手でコピーしてもよい (`ThirdParty\googletest\include` と `src`)。
- ソリューション内の静的ライブラリ (`gtest.vcxproj`) は、Claude 側 (`add_layer.py` / `/new-solution`) が作る。ウォッチャーは、取得だけ。

### UI テストを実行する (`trigger_uitest.flag`)

ビルドのあと、**UI テストのプロジェクトだけ** (名前が `UITests` / `UiTests` で終わる、または FlaUI を参照) を、`dotnet test` で実行する。結果のファイルは `trigger_test.flag` と同じ (`test_result.txt` など)。**UI テストのプロジェクトは、通常のテスト (`trigger_test.flag`) からは除かれる。**

- テストには、環境変数 `UITEST_SOLUTION_DIR` / `UITEST_CONFIGURATION` / `UITEST_PLATFORM` / `UITEST_SCREENSHOT_DIR` が渡る。失敗時のスクリーンショットは、`.claude-logs\ui-screenshots\` に置く (WSL の Claude が、画像として読める)。
- 実行の前後に、ソリューションのフォルダの下の exe のプロセス (テストが残したアプリ) を終了する。
- 制限時間は、テストプロジェクトごとに `-UiTestTimeoutSec` (既定 600 秒)。
- **UI テストは、既定で、別のデスクトップで実行する** (`-UiTestDesktop separate`。ユーザーの画面にウィンドウが出ず、フォーカスも奪わない)。**UI テストの間だけ、WPF をソフトウェアレンダリングにする** (HKCU の `Avalon.Graphics\DisableHWAcceleration`。元の値は、`%LOCALAPPDATA%\claude-watcher\wpf-hwaccel-backup.txt` に記録して、終了後に復元する。異常終了したときは、次の起動時に復元する)。**目で確かめたいとき:** `run_watcher_visible.cmd` (`run_watcher.cmd` と同じ引数) で起動する。UI テストを、**ユーザーのデスクトップ**で、操作の間に待ち (`WATCH_UI_SLOWMO_MS`、既定 800 ミリ秒) を入れて、実行する (ウィンドウが見え、PC を、快適には使えない)。待ちは、`watch_and_build.ps1 -UiTestSlowMoMs N` でも指定できる。テストは、操作の記録 (`.claude-logs\ui-screenshots\ui-trace.txt`) を残す。ユーザーのデスクトップで実行するには、環境変数 `WATCH_UI_DESKTOP=default` (`run_watcher.cmd` の前に `set WATCH_UI_DESKTOP=default`)、または `watch_and_build.ps1 -UiTestDesktop default`。
- **実行中は、マウス・キーボードに触らない** (画面のロック、RDP の切断・最小化も避ける。UIA が動かなくなる)。

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
| `-Platform` | `auto` | `auto` / `x64` / `Win32` / `x86` / `ARM64` / `AnyCPU`。`auto`: C++ があれば `x64`、.NET だけなら `AnyCPU` |
| `-Configuration` | `Debug` | ビルド構成 |
| `-MSBuildTarget` | `Build` | `Build` / `Rebuild` / `Clean` |
| `-LogDir` | `<TargetDir>\.claude-logs` | 詳細ログの出力先 |
| `-BuildScript` | ps1 と同じフォルダの `build-windows.cmd` | ビルド用バッチ |
| `-TestExePattern` | `(Test\|Tests)\.exe$` | GoogleTest の exe の名前 (正規表現) |
| `-TestArgs` | `--gtest_color=no` | テスト exe に渡す引数 |
| `-TestTimeoutSec` | `120` | テスト exe 1本あたりの制限時間 (秒) |
| `-TestWorkingDir` | テスト exe のあるフォルダ | GoogleTest の実行時の作業フォルダ |
| `-DotnetTestArgs` | (空) | `dotnet test` に足す引数。例: `-DotnetTestArgs:-p:Platform=x64` (プロジェクトの出力先が、プラットフォーム別のとき)。**値が `-` で始まるので、コロンで結ぶ** (`-DotnetTestArgs "-p:Platform=x64"` は、PowerShell が `-p` をパラメーター名と解釈して、`ambiguous` で失敗する) |
| `-DotnetExe` | `dotnet` | `dotnet` の実行ファイル (PATH にないときは、フルパス) |
| `-PackageTimeoutSec` | `1800` | パッケージの操作 1 件の制限時間 (秒)。`vcpkg install` は、ポートのビルドで長い |
| `-VcpkgExe` | (自動) | `vcpkg.exe`。省略時: 環境変数 `VCPKG_ROOT`、なければ Visual Studio 同梱 (`VC\vcpkg\vcpkg.exe`) |
| `-VcpkgTriplet` | (自動) | vcpkg のトリプレット。省略時は Platform から (`x64-windows-static-md` / `x86-...` / `arm64-...`) |

### ビルドだけを単体で実行する
```bat
build-windows.cmd <target> <Platform> [Configuration] [MSBuildTarget] [LogDir] [Features]
```
`Features`: カンマ区切り。`cpp` (C++ ツール入りの VS を要求し、cl.exe を確認する。**省略時の既定**)、`restore` (`/restore`。.NET 用。`Clean` では付けない)。例: `build-windows.cmd MyApp.sln AnyCPU Debug Build "" restore`

終了コード: `0` 成功 / `1` ビルド失敗 / `2` 引数不正 / `10` vswhere なし / `11` 必要な構成要素入りの VS なし / `12` VsDevCmd なし / `13` VsDevCmd 失敗 / `14` MSBuild.exe (`cpp` なら cl.exe も) が見つからない

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
| `trigger_package.flag` | Claude | **パッケージの操作を依頼。** 各行が 1 つの操作 (下記)。ウォッチャーが検知して削除する |
| `package_output.txt` | ウォッチャー | 各操作の出力 (`## <操作>` の見出し付き) |
| `package_error.log` | ウォッチャー | 失敗時のみ。環境の問題 (ネットワーク、`dotnet` / `vcpkg` がない) は、先頭が `[ENVIRONMENT ERROR - not a source code problem]` |
| `package_result.txt` | ウォッチャー | **完了マーカー** (最後に書かれる): `OK` / `FAILED` |
| `.claude-logs\build.log` `errors.log` `warnings.log` `test.log` | ウォッチャー | 詳細ログ (フルパスのまま) |
| `.claude-logs\test-results\<exe名>.xml` `<プロジェクト名>.trx` | ウォッチャー | テストの、機械可読な結果 (GoogleTest の XML、MSTest の trx)。テストの開始時に、前回分が削除される。WSL 側の `summarize_test_log.py` が読む |

**パッケージの操作 (`trigger_package.flag`)**: 上から順に実行し、最初の失敗で止まります。引数は、コマンドに渡るので、決まった文字だけが通ります。

| 操作 | 内容 |
|---|---|
| `nuget search <語>` / `nuget versions <ID>` | nuget.org の検索 (ダウンロード数・発行元の確認済みも出す) / バージョンの一覧 |
| `nuget add <プロジェクト> <ID> [<バージョン>]` / `nuget remove ...` | `dotnet add / remove package`。プロジェクトは、ソリューションの下の `.csproj` などの相対パス |
| `vcpkg search <語>` | `vcpkg search` |
| `vcpkg baseline` | `vcpkg x-update-baseline --add-initial-baseline` (`vcpkg.json` の `builtin-baseline`) |
| `vcpkg install` | `vcpkg install --triplet <Platform から>` (マニフェストモード。`vcpkg.json` が要る) |
| `fetch <owner/repo> <タグ> <名前> [<サブフォルダ>]` | GitHub のタグのソースを、`ThirdParty\<名前>\` に置く (同じ内容なら、何もしない) |

`vcpkg.exe` は、`-VcpkgExe` → 環境変数 `VCPKG_ROOT` → Visual Studio 同梱、の順に探します。見つからなければ `ENV_ERROR` (VS の「vcpkg パッケージ マネージャー」コンポーネントを追加する)。

`test_result.txt` の値:

| 値 | 意味 |
|---|---|
| `PASSED` | ビルド成功・全テスト成功 |
| `FAILED` | テスト失敗 (または異常終了)。`test_error.log` に失敗したテストと期待値/実際の値 |
| `TIMEOUT` | テストが制限時間内に終わらない。`test_error.log` に `Hung test (was running when killed): ...` |
| `BUILD_FAILED` | ビルド失敗のためテスト未実行。`build_error.log` を見る |
| `ENV_ERROR` | テスト (GoogleTest の exe も .NET のテストプロジェクトも) が見つからない、`dotnet` がない、テストが 1 件も実行されない等。`test_error.log` の先頭が `[ENVIRONMENT ERROR - not a source code problem]` |

補足:
- 各ファイルは、新しい依頼の開始時に、前回分が削除されます。
- `build_error.log` / `test_error.log` のパスは、ソリューションフォルダからの相対パス (`/` 区切り) に変換されます (例: `MyAppTest/TestFoo.cpp(49)`)。Claude がそのまま開けるようにするためです。
- ビルド/テストは、**1件ずつ順番に**処理されます。実行中に次のフラグが置かれても、現在の処理が終わってから処理されます。
- **GoogleTest (C++):** `<ソリューション>\<x64|Win32|ARM64>\<Configuration>\` にある、`-TestExePattern` に一致する exe をすべて実行します (`--gtest_output=xml` を足して、XML も残す)。成功の判定は、終了コード 0 **かつ** 出力に GoogleTest の `[  PASSED  ]` 行があること (引数不正やテスト 0 件を、成功と誤認しないため)。
- **dotnet test (.NET):** ソリューションの `.csproj` / `.vbproj` / `.fsproj` のうち、`Microsoft.NET.Test.Sdk` / `MSTest` を参照するもの、`IsTestProject` が `true` のもの、名前が `Test` / `Tests` で終わるものを、`dotnet test --no-build` で実行します (trx を残す)。成功の判定は、終了コード 0 **かつ** trx の `executed` が 1 以上 (テスト 0 件を、成功と誤認しないため)。
- 両方ある場合は、両方を実行し、結果は 1 つの `test_result.txt` にまとまります。

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
| `ERROR: no .sln / .slnx found in <cmd のあるフォルダ>` | 引数なしで起動したため、`run_watcher.cmd` のあるフォルダが対象になった。プロジェクトのフォルダを、引数で渡す (例: `run_watcher.cmd C:\path\to\MyApp`、またはプロジェクトのフォルダから `run_watcher.cmd .`) |
| `ERROR: a watcher is already running for this folder` (終了コード 3) | 同じプロジェクトフォルダで、すでに別のウォッチャーが動いている。そのウィンドウを使うか、閉じてから、起動し直す。見当たらない場合は、最小化されたウィンドウや、別のユーザーのセッションを、確認する |
| `パラメーター 'SolutionPath' の引数が指定されていません` | (古い版のウォッチャー) ソリューションが空で渡っている。最新版では、省略できる (トリガーのときに、フォルダから探す)。古い版なら、フォルダに `.sln` / `.slnx` があるか、`run_watcher.cmd` の第2引数で指定する |
| ビルドのトリガーを置くと、`ERROR: no .sln / .slnx found in ...` (`build_result.txt` = `FAILED`) | ウォッチャーが見ているフォルダに、まだソリューションがない。`new_solution.py` で作ってから、もう一度トリガーを置く (ウォッチャーの再起動は、不要)。フォルダが違うなら、ヘッダーの `Target` の行 (またはフォルダ名) を、確かめる |
| `ParserError` や、ps1 の日本語の文字化け | `.ps1` の BOM が落ちている。BOM 付き UTF-8 で保存し直す |
| `.cmd` のコメントが文字化けする、`'xxx' は、内部コマンドまたは外部コマンド...` のようなエラーが出る | `.cmd` が UTF-8 などで保存し直された。CP932 (Shift_JIS) で保存し直す |
| `ENV_ERROR` (テストが見つからない) | C++: ビルド構成 (Platform/Configuration) と、`<ソリューション>\<x64\|Win32\|ARM64>\<Configuration>\` に exe があるか、`-TestExePattern` が名前に合っているかを確認。.NET: テストプロジェクトが、ソリューションに入っているか、`Microsoft.NET.Test.Sdk` を参照しているか (名前が `Test` / `Tests` で終わるかでも、拾われる) |
| `ENV_ERROR` (no tests were executed) | .NET: `dotnet test` が終了コード 0 でも、trx がない、または `executed=0`。`Microsoft.NET.Test.Sdk` と MSTest のアダプタ (`MSTest` パッケージ) を参照しているか、`[TestMethod]` があるかを確認 |
| .NET のテストで `FAILED`、`no test results: the test host crashed, or dotnet test failed before running tests` | `--no-build` が、アセンブリを見つけられない (出力先が `bin\x64\Debug` など、プラットフォーム別) → `-DotnetTestArgs:-p:Platform=x64` (コロンで結ぶ)。または、テストホストのクラッシュ (`test.log` を見る) |
| .NET のテストが `ENV_ERROR`、`test_error.log` に `the test assembly that was run is older than a build output in another folder` | 出力先が `bin\x64\Debug` などなのに、`dotnet test --no-build` が `bin\Debug` の古い DLL を実行しようとした (偽の成功の防止)。`-DotnetTestArgs:-p:Platform=x64` を付けて起動し直す。または、古い `bin` を消す |
| .NET のビルドで `ENV_ERROR` (`MSB4236` / `NETSDK1045` / `NETSDK1141` / `NU1301`) | .NET SDK が、見つからない / 古い (`global.json`、対象フレームワーク) / NuGet のソースに届かない。SDK のインストールと、ネットワークを確認する |
| `ENV_ERROR` (no gtest summary) | テスト exe が GoogleTest でない、または `-TestArgs` が不正 (古い GoogleTest は `--gtest_brief` を知らず、ヘルプだけ表示して終了コード 0 になる) |
| テストが `TIMEOUT` になる | 全体の実行時間が制限 (既定 120 秒) を超えている。`-TestTimeoutSec` を延ばす。`Hung test` は、打ち切られた時点のテスト名で、必ずしもハングしたテストではない |
| Claude 側で `WATCHER_NOT_RUNNING` | ウォッチャーが起動していない (フラグが 15 秒回収されない)。対象プロジェクト用に `run_watcher.cmd` を起動する |
| ビルド環境のエラー (`ENV_ERROR`、VS が見つからない等) | `[ENVIRONMENT ERROR ...]` のメッセージに従う。C++ のソリューションは VS の C++ ワークロード (**C++ ツールのない VS では、C++ のビルドはできない。Visual Studio Installer で「変更」→「C++ によるデスクトップ開発」を、手で追加する**。`no Visual Studio with C++ x86/x64 tools found`、終了コード 11)。**逆に、.NET のビルドで `MSB4236` / `NETSDK1045` / `NETSDK1141`、または `dotnet` が見つからない場合は、Visual Studio Installer で「変更」→「.NET デスクトップ開発」を手で追加する (または .NET SDK をインストールする)** (案内の行が `build_error.log` / `test_error.log` / `package_error.log` に付く) |
| `-ExecutionPolicy Bypass` が組織のポリシーで拒否される | IT 管理者に確認する |
| ダウンロードしたファイルがブロックされる | `Get-ChildItem <フォルダ> -Recurse \| Unblock-File` |

## 8. 制限事項
- テストは、C++ は **GoogleTest のみ**、.NET は **MSTest (VSTest モード)** が対象です (xUnit / NUnit は動く見込みですが、未検証。C++ の `CppUnitTestFramework` と、`Microsoft.Testing.Platform` モードの MSTest は、未対応)。
- パッケージの操作の `search` / `versions` は、nuget.org だけを引きます (社内フィードは見えません。`add` は、ホストの NuGet の設定どおりに動きます)。vcpkg のマニフェストモードと MSBuild の連携は、実機で未確認です (`docs/TEST-PLAN.md` の P 系)。
- .NET のビルドは、VS の MSBuild で行います (VS のない環境での `dotnet build` へのフォールバックは、ありません)。
- .NET のテストプロジェクトの判定は、プロジェクトファイルの中身と名前で行います (`Directory.Build.props` で `IsTestProject` を指定している場合は、名前が `Test` / `Tests` で終わる必要があります)。
- 1つのウォッチャーは、1つのプロジェクトと 1つの Platform/Configuration 専用です。切り替えるには、起動し直します。
- テスト実行時の作業フォルダの既定は、テスト exe のあるフォルダです。プロジェクトフォルダ基準の相対パスでデータを読むテストは、`-TestWorkingDir` が必要です。
- Claude Code (サンドボックス) は、この 3 ファイルを実行しません。ユーザーが Windows 側で起動します。
