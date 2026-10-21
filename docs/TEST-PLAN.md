# テスト手順書

実機 (Windows + WSL) で行う確認の手順と、期待する結果。
「状況」列は、**この手順書を作った時点 (v1.0.0) の実績**。変更したときは、該当する項目を再確認して、更新する。

凡例: ✔ 実機で確認済み / △ 一部のみ確認 / ✗ 未確認

## 0. 事前準備

- テスト用の C++ ソリューション (`MyApp.sln`): `MyApp` (本体) と `MyAppTest` (GoogleTest、`MyApp` をプロジェクト参照)。
- ホスト側ツール 3 ファイルを、同じフォルダに配置 (例: `C:\tools\cpp-watcher\`)。形式が崩れていないこと。
  ```powershell
  Get-Content C:\tools\cpp-watcher\watch_and_build.ps1 -Encoding Byte -TotalCount 3   # 239 187 191 なら BOM あり
  ```
- Skill を `~/.claude/skills/` (または、プロジェクトの `.claude/skills/`) に配置 → **新しいセッション**で起動。
- ウォッチャーの起動:
  ```bat
  C:\tools\cpp-watcher\run_watcher.cmd C:\path\to\MyApp
  ```
  ヘッダーに `QuickEdit : disabled` が出ること。

以下、`<SLN>` はソリューションフォルダ。PowerShell を、別のウィンドウで開いて、`cd <SLN>` する。

## 1. ホスト側ツール単体 (Claude を介さない)

### 1-1. ビルドのみ (`trigger_build.flag`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| H1 | ソースが正常な状態で、`New-Item trigger_build.flag -ItemType File` | フラグが消える。`build_result.txt` = `SUCCESS`。`build_error.log` なし。`test_result.txt` なし | ✔ |
| H2 | 構文エラーを 1 行入れて、同上 | `build_result.txt` = `FAILED`。`build_error.log` に `error C...` の行 (相対パス)、末尾に `Build failed with exit code: 1`。行頭に `2>` がない | ✔ |
| H3 | エラーを直して、同上 | 開始時に、前回の `build_result.txt` / `build_error.log` が消え、`SUCCESS` になる | ✔ |
| H4 | `build-windows.cmd` を一時的に別名にして、同上 | `FAILED`。`build_error.log` の先頭が `[ENVIRONMENT ERROR - not a source code problem]` | ✗ |

### 1-1b. ビルドの出力の表示 (`Invoke-BuildScript`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| H6 | ウォッチャーを起動して、`trigger_build.flag` を置く | **別のコンソール (ウィンドウ / タブ) が、開かない。** `[VS]` `[MSBuild]` `[BUILD]` と、MSBuild の出力が、**ウォッチャーの画面に**、ビルド中に、1 行ずつ流れる | ✔ (2026-10-14 実機: ClaudeProject) |
| H7 | 日本語のエラーを含むビルド (構文エラーを 1 行入れる) | エラーメッセージの日本語が、文字化けせずに、ウォッチャーの画面に出る。ビルド後も、ウォッチャーの画面の表示が、乱れない (`chcp` の影響なし) | ✔ (2026-10-14 実機: ClaudeProject) |
| H8 | H6 の結果 | `build_result.txt` (`SUCCESS` / `FAILED`)、`build_error.log` が、従来どおり (H1〜H3 と同じ)。終了コードが、環境エラー (10〜14) のときも、`[ENVIRONMENT ERROR ...]` が付く | ✔ (2026-10-14 実機: ClaudeProject) |

### 1-2. ビルド + テスト (`trigger_test.flag`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| T1 | 正常な状態で `trigger_test.flag` | `build_result.txt` = `SUCCESS`、`test_result.txt` = `PASSED`。`test_error.log` なし。`.claude-logs\test.log` に各テストの `[       OK ]` | ✔ |
| T2 | テストが落ちるバグを、ソースに入れて同上 | `test_result.txt` = `FAILED`。`test_error.log` に、失敗したテスト名・期待値・実際の値 (`file(line): error:`)、相対パス | ✔ |
| T3 | 構文エラーを入れて同上 | `test_result.txt` = `BUILD_FAILED`。`build_error.log` にエラー | ✔ (Skill 経由のループの中で確認) |
| T4 | ウォッチャーを `-TestTimeoutSec 5` で起動し、同上 | `TIMEOUT`。`test_error.log` に `TIMEOUT after 5s (killed)` と `Hung test ...`。テスト exe のプロセスが残らない (`Get-Process`) | ✔ |
| T5 | `-TestExePattern 'NoSuch\.exe$'` で起動し、同上 | `ENV_ERROR`。`test_error.log` の先頭が `[ENVIRONMENT ERROR ...]` | ✔ |
| T6 | 古い GoogleTest に、`--gtest_brief=1` を `-TestArgs` で渡して同上 | ヘルプだけが出ても、`PASSED` にならず、`ENV_ERROR` (`no gtest summary`) | △ (原因の発見までは実機。修正後の分岐は、単体では未実行) |
| T7 | ビルド中に、ウォッチャーのウィンドウをクリック/選択 | ビルドが止まらない。タイトルバーに `選択` と出ない | ✔ |
| T8 | 別のウォッチャーを、`.slnx` のソリューションで起動し、同上 | `.slnx` を自動検出して、ビルドが通る | ✗ |
| T9 | `-Platform Win32` / `-Configuration Release` で起動し、同上 | exe を `Win32\` / `Release\` から探して、実行する | ✗ |

### 1-2b. GoogleTest のソース取得 (`trigger_gtest.flag`)

Windows 側が GitHub に届く環境で行う。**手書きの PowerShell なので、最初の実機確認が必要。**

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| G1 | ウォッチャーを起動し、`New-Item trigger_gtest.flag -ItemType File` | フラグが消える。`ThirdParty\googletest\` に `include\gtest\gtest.h`、`src\gtest-all.cc`、`src\gtest_main.cc`、`LICENSE`、`VERSION.txt` (`v1.17.0`)。`gtest_result.txt` = `OK`。`gtest_error.log` なし | ✔ (2026-10-14 実機: ClaudeProject) |
| G2 | G1 の直後に、もう一度、フラグを置く | **何も再取得せず**、すぐ `OK` (冪等。画面に `is already in`) | ✔ (2026-10-14 実機: ClaudeProject) |
| G3 | フラグの 1 行目に、別のタグ (`release-1.12.1`) を書いて置く | そのタグのソースに、置き換わる。`VERSION.txt` が変わる | ✗ |
| G4 | フラグの 1 行目に、不正なタグ (`v1;calc`) | `FAILED`。`gtest_error.log` の先頭が `[ENVIRONMENT ERROR ...]`、`invalid GoogleTest tag`。**コマンドは、実行されない** | ✔ (2026-10-14 実機: ClaudeProject) |
| G5 | 存在しないタグ (`v9.99.9`) | `FAILED`。git の失敗と、zip の失敗が、ログに残る | ✔ (2026-10-14 実機: ClaudeProject) |
| G6 | ネットワークを切って (またはプロキシで遮断して) G1 | `FAILED`。ネットワークの失敗が、ログに残る。ウォッチャーは、止まらない | ✗ |
| G7 | git を PATH から外して G1 | zip のダウンロードで、取得できる | ✗ |
| G8 | G1 のあと、`trigger_test.flag` と同時に置く | gtest が先に処理され、そのあと、ビルド + テスト | ✗ |

### 1-5. C++ と .NET (WPF) の統合 (`docs/DESIGN.md` 4.24)

**v2.0.0 で追加。Windows 側の変更は、すべて未確認 (状況 ✗)。** 最初の実機確認が必要。
準備: WPF + MSTest の小さなソリューション `WpfSample` (`WpfSample` = WPF アプリ、`WpfSample.Tests` = MSTest v3 + `Microsoft.NET.Test.Sdk`、`WpfSample.Tests` が `WpfSample` を参照) と、混在のソリューション (C++ の DLL + GoogleTest、WPF + MSTest が、同じ `.slnx`)。
ホスト側ツールは、**3 ファイルをまとめて**、配り直す (`install/install.sh`)。稼働中のウォッチャーは、閉じて、起動し直す。

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| U1 | **回帰:** 従来の C++ のソリューション (`MyApp`) で、1-1 の H1〜H3 と、1-2 の T1 / T2 / T4 / T5 | すべて、v1.6.0 と同じ結果。`[BUILD] features=cpp`。`.claude-logs\test-results\<exe名>.xml` ができる | ✔ (2026-10-18 実機。ユーザーの報告: H1〜H3、T1 / T2 / T4 / T5 の、すべてが期待どおり。ログの提出はなし) |
| U2 | ウォッチャーの起動時のヘッダー | `Solution : C++ (build features: cpp)`、`dotnet test : dotnet (projects: 0)` | ✔ (2026-10-18 実機。ユーザーの報告: U1 の手順の中で確認) |
| U3 | `WpfSample` で、ウォッチャーを起動 (Platform 省略)、`trigger_build.flag` | ヘッダーが `Solution : .NET (build features: restore)`、`Build : Debug\|AnyCPU`。`[BUILD] features=restore`。`SUCCESS` (初回は、NuGet の復元が走る) | ✔ (2026-10-18 実機。ユーザーの報告: 期待どおり。ビルドは `SUCCESS` で、NuGet の復元と AnyCPU の出力も、成果物で確認) |
| U4 | `MainWindow.xaml` に、未定義の型 (`<local:NoSuch/>`) を入れて、`trigger_build.flag` | `FAILED`。`build_error.log` に `error XDG...` / `MC...` の行 (`.xaml` の相対パス)。WSL 側の要約が、`MC` / `XDG` を解釈する | ✔ (2026-10-19 実機。コンソールの Claude の報告: `FAILED`、要約に `MC3000` と `.xaml` の相対パス・行列) |
| U5 | C# に構文エラーを入れて、同上 | `FAILED`。`error CS...` の行 (相対パス) | ✔ (2026-10-19 実機。コンソールの Claude の報告: `FAILED`、要約に `CS1002` と `ViewModels/MainViewModel.cs(10,70)`) |
| U6 | `WpfSample` で `trigger_test.flag` (全テスト成功) | `PASSED`。`.claude-logs\test-results\WpfSample.Tests.trx` ができる。`test_result.txt` が、trx より後に書かれる | ✔ (2026-10-18 17:34 実機。`PASSED`。trx が 3 つできた) |
| U6b | **文字化けしない (v2.4.1):** 日本語のメッセージを含むテスト (`Assert.AreEqual("こんにちは", ...)` が失敗する) で、`trigger_test.flag` | `test_error.log` と `.claude-logs\test.log` の日本語が、そのまま読める。`dotnet test` の出力が UTF-8 であることを、バイト列 (`Format-Hex`) でも確認する。**GoogleTest の日本語のメッセージ (ANSI) も、化けない** (U1 の T2 のテストに、日本語のメッセージを入れて確認) | ✔ (2026-10-18 `test.log`、2026-10-19 失敗メッセージ (`test_error.log`) も、UTF-8 で化けない。コンソールの Claude の報告。GoogleTest の日本語 (ANSI) は、未確認) |
| U6c | **環境変数 `Platform` が漏れない (v2.4.1):** PowerShell で `$env:Platform = "auto"` を設定してから、ウォッチャーを起動し、`trigger_test.flag` | テストの DLL が見つかる (`bin\Debug\net8.0\`)。`test.log` のパスに `bin\auto` が出ない。`run_watcher.cmd` の旧版を使った場合の、再現でもある | △ (2026-10-18 実機。修正版で、テストの DLL が見つかり、`PASSED`。**`$env:Platform = "auto"` を、わざと設定した場合の再現は、未実施**) |
| U7 | (同じ `Assert.AreEqual`)、`trigger_test.flag` | `FAILED`。`test_error.log` に `FAILED <クラス名.メソッド名>`、メッセージ、`at ...cs:line N`。WSL 側の要約が、**同じメッセージを x2 にまとめ**、`[ran N: ...]` が出る | △ (2026-10-19。**実機の実行は、古いコピー (`~/cpp-build-test-loop/scripts/build_test_once.sh`、10/12 の版) を使ったため、要約と `test_summary.json` が出なかった = ツールの不具合ではない。** 配布済みの現行版では、実機の trx (成功の結果を、失敗に書き換えたもの) を使い、WSL で `[ran 8: passed 6 / failed 2 / skipped 0]`、同じメッセージの集約 (`x2`)、`test_summary.json` が出ることを確認。**現行版での、実機の失敗の実行は、未実施**) |
| U8 | **実機の trx / gtest XML を、`tests/fixtures/` と見比べる** (`.claude-logs\test-results\` の実物を、WSL に持ってきて、`summarize_test_log.py --results-dir` に渡す) | 要約が出る。**形が違えば、`summarize_test_log.py` と `tests/fixtures/` を、実物に合わせて直す** (サンプルは、仕様から書いたもの) | △ (2026-10-19。**MSTest の trx: 実機のファイル (`dotnet test` が出したもの) を、解釈できることを確認** (テスト名 = クラス名 + メソッド名、合計 8 件、ソース別の件数)。**GoogleTest の XML と、実機の失敗の trx (日本語 OS のスタックトレース) は、未確認**) |
| U9 | 混在のソリューションで、`trigger_test.flag` (C++ と .NET の、両方に失敗を入れる) | 両方のテストが実行される。要約が 1 つで、`sources` に `gtest` と `mstest` の両方。`[ran N: ...]` が、両方の合計 | ✗ |
| U10 | 混在のソリューションで、ヘッダーと Platform | `Solution : C++ + .NET (build features: cpp,restore)`、`Build : Debug\|x64`。ビルドが通る (.NET 側は、ソリューション構成で `Any CPU` に対応づく) | ✗ |
| U11 | テストが 0 件のテストプロジェクト (`[TestMethod]` を、すべて外す)、`trigger_test.flag` | `ENV_ERROR` (`no tests were executed`)。`PASSED` にならない | ✔ (2026-10-20 実機: `ViewModels.Tests` だけ 0 件にして `build_test_once.sh` → **全体が `ENV_ERROR`** (`ViewModels.Tests.dll で使用できるテストはありません`)。ほかのテストプロジェクトが成功していても、0 件のプロジェクトが 1 つあれば、止まる (安全側)。**発見: 前回の `test_summary.json` が残った** → v2.4.2 で、実行の最初に消すよう修正。**元に戻すときは、`cp -p` を使わない** (古い日時で、MSBuild が再ビルドしない。`touch` が要る)) |
| U12 | `-DotnetExe NoSuchDotnet` で起動し、`WpfSample` で `trigger_test.flag` | `ENV_ERROR` (`'NoSuchDotnet' was not found`) | ✗ |
| U13 | `global.json` に、存在しない SDK を指定して、`trigger_build.flag` | `FAILED`。`build_error.log` の先頭が `[ENVIRONMENT ERROR ...]` (`NETSDK1141`) | ✗ |
| U14 | C++ ワークロードのない VS (MSBuild だけ) で、`WpfSample` の `trigger_build.flag` | ビルドが通る (`cpp` を要求しないため)。**この環境がなければ、△ のまま** | ✗ |
| U15 | WPF が `bin\x64\Debug` に出す構成で、`-DotnetTestArgs "-p:Platform=x64"` | `dotnet test --no-build` が、アセンブリを見つけて、テストが走る。指定がなければ、見つからず、`FAILED` (`no test results ...`) になることも確認 | ✗ |
| U16 | `Skill` 経由: 新しいセッションで、`auto-build` / `build-test-loop` を使う (旧名の `cpp-*` が残っていないこと) | description が競合せず、WPF のソリューションでも、C++ のソリューションでも、同じ手順で動く | ✗ |

### 1-6. パッケージの操作 (`trigger_package.flag`、`docs/DESIGN.md` 4.26)

**v2.2.0 で追加。Windows 側は、すべて未確認 (状況 ✗)。** 準備: WPF + MSTest の `WpfSample` (1-5)、C++ の `MyApp` (MFC など)。Windows 側が、nuget.org と GitHub に届くこと。VS の「vcpkg パッケージ マネージャー」コンポーネント (この PC では、VS 2026 Enterprise の `VC\vcpkg\vcpkg.exe` を確認済み)。ホスト側ツールは、3 ファイルをまとめて、配り直す。
フラグは、PowerShell で置いてよい (`Set-Content trigger_package.flag "nuget versions Newtonsoft.Json"`)。結果は、`package_output.txt` / `package_error.log` / `package_result.txt`。

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| P1 | ウォッチャーを起動し、`nuget versions Newtonsoft.Json`、`nuget search json` | `package_result.txt` = `OK`。出力に、バージョンの一覧 (stable 10 件 + prerelease)、検索結果 (ID・version・downloads・verified・authors)。**`package_result.txt` が、`package_output.txt` より後に書かれる** | ✔ (2026-10-20 実機: 86 バージョン (stable 10 件)、検索結果あり。`package_result.txt` が `package_output.txt` の約 17ms 後) |
| P2 | 存在しない名前: `nuget versions No.Such.Pkg.Xyz` | `FAILED`、`package_error.log` に `not found (HTTP 404)`。先頭が `[ENVIRONMENT ERROR ...]` **でない** | ✔ (2026-10-20 実機: `FAILED`、`not found (HTTP 404). Check the spelling with 'nuget search'.`) |
| P3 | `WpfSample` に、`nuget add WpfSample/WpfSample.csproj CommunityToolkit.Mvvm 8.4.0` | `OK`。`added CommunityToolkit.Mvvm 8.4.0 -> ...`。`.csproj` に `PackageReference` が増える。続けて `trigger_build.flag` で、ビルドが通る | ✔ (2026-10-20 実機: `OK`、`PackageReference` が増え、ビルド `SUCCESS`) |
| P4 | 中央管理 (`Directory.Packages.props` に `ManagePackageVersionsCentrally`) のソリューションで、同様に `nuget add` | `OK`。バージョンは、`Directory.Packages.props` に入り、結果は `... (Directory.Packages.props)` と出る | ✗ |
| P5 | `nuget add WpfSample/WpfSample.csproj Nope.Pkg.Xyz` | `FAILED` (`NU1101`)。**環境エラーにならない** (ソースの問題) | ✔ (2026-10-20 実機: `FAILED` (`パッケージ 'Nope.Pkg.Xyz' に使用できるバージョンがありません`)、`.csproj` は不変。**`NU1101` のコードは、出力に出ない** (メッセージは、NU1101 と同じ内容。期待値の「(`NU1101`)」は、「版がない旨のメッセージ」と読み替える)) |
| P6 | ネットワークを切る (または、プロキシを誤設定) して、`nuget add ...` と `nuget versions ...` | `ENV_ERROR` (`NU1301` / `could not reach nuget.org`)。先頭が `[ENVIRONMENT ERROR ...]` | ✗ |
| P7 | `nuget remove WpfSample/WpfSample.csproj CommunityToolkit.Mvvm` | `OK`。`PackageReference` が消える | ✔ (2026-10-20 実機: `OK`、`.csproj` が元と完全一致、ビルド `SUCCESS`) |
| P8 | **C++ のセットアップ:** WSL で `cpp_pkg.py setup <SLN>` → VS で、プロジェクトを開き直す | `vcpkg.json` ができ、各 `.vcxproj` に `Label="Vcpkg"` のグループが入る。**VS が、プロジェクトを読み込める** (XML の誤りがない)。プロパティページの「vcpkg」で、マニフェストが有効と表示される | ✗ ✔ (2026-10-19 実機。P11: `FMT_UNICODE=0` 追加後、`<fmt/format.h>` でリンクまで SUCCESS。P12: Release で `\lib\` (debug でない) を使い、LNK2038 なし) |
| P9 | `vcpkg search fmt` | `OK` (ポートが出る)。**出ない・失敗する場合は、理由を、`package_error.log` から記録し、`vcpkg search` の扱い (DESIGN 4.26 の限界) を見直す** | ✗ **実機 (2026-10-19): baseline 未設定で FAILED。baseline 後は OK (約 170 秒、fmt を含む一覧)。✔ (所要時間が長いので `--timeout 600` 以上を推奨)** |
| P10 | `cpp_pkg.py add <SLN> fmt` → `vcpkg baseline` → `vcpkg install` (`--timeout 1800`) | `vcpkg.json` に `builtin-baseline` が入る (`cpp_pkg.py list` で確認)。`vcpkg install` が `OK` (初回は、数分以上)。`vcpkg_installed\x64-windows-static-md\` ができる | ✗ ✔ (2026-10-19 実機。P11: `FMT_UNICODE=0` 追加後、`<fmt/format.h>` でリンクまで SUCCESS。P12: Release で `\lib\` (debug でない) を使い、LNK2038 なし) |
| P11 | **MSBuild との連携:** P10 のあと、C++ のソースに `#include <fmt/core.h>` と `fmt::print("{}", 1);` を足して、`trigger_build.flag` | ビルドが通る (インクルード・リンクが、自動)。**ビルド中の、自動の `vcpkg install` が、何もしない (速い)。** **通らない場合: (a) `vcpkg.json` を、ソリューションのフォルダから見つけるか、(b) `Label="Vcpkg"` の位置で効くか、(c) `VcpkgTriplet` が効くか、を、ビルドログで確認して記録する** | ✗ ✔ (2026-10-19 実機。P11: `FMT_UNICODE=0` 追加後、`<fmt/format.h>` でリンクまで SUCCESS。P12: Release で `\lib\` (debug でない) を使い、LNK2038 なし) |
| P12 | **CRT の整合:** P11 で、`/MD` (動的 CRT) の、Debug と Release の両方 | リンクエラー (`LNK2038` ランタイムの不一致、`LNK2001`) がない | ✗ ✔ (2026-10-19 実機。P11: `FMT_UNICODE=0` 追加後、`<fmt/format.h>` でリンクまで SUCCESS。P12: Release で `\lib\` (debug でない) を使い、LNK2038 なし) |
| P13 | 存在しないポートを、`cpp_pkg.py add <SLN> no-such-port-xyz` → `vcpkg install` | `FAILED` (ポートがない。環境エラーでは、ない) | ✗ ✔ (2026-10-19 実機。P11: `FMT_UNICODE=0` 追加後、`<fmt/format.h>` でリンクまで SUCCESS。P12: Release で `\lib\` (debug でない) を使い、LNK2038 なし) |
| P14 | `vcpkg.exe` を見つけられない環境 (`-VcpkgExe C:\nosuch\vcpkg.exe` を、`VCPKG_ROOT` なしで) | `ENV_ERROR` (`vcpkg.exe was not found`)。**`-VcpkgExe` が存在しないとき、次の候補 (VS 同梱) に進む** (ので、実際に再現するには、VS からも見つからない状態が要る。**再現できなければ、△ のまま**) | ✗ |
| P15 | `-PackageTimeoutSec 5` で起動し、`vcpkg install` (ポートが多い状態から) | `ENV_ERROR` (`vcpkg timed out`)。もう一度、通常の制限時間で `vcpkg install` すると、**続きから (キャッシュで) 進む** | ✗ |
| P16 | `fetch nlohmann/json v3.11.3 json single_include` | `OK`。`ThirdParty\json\nlohmann\json.hpp` ができ、`VERSION.txt` が `nlohmann/json@v3.11.3#single_include`。LICENSE も、置かれる。**もう一度、同じ操作 → `already present`** | ✔ (2026-10-19 実機、`wpfsample` で実施: `OK`。`ThirdParty/json/nlohmann/json.hpp` と `json_fwd.hpp`、`VERSION.txt` = `nlohmann/json@v3.11.3#single_include`、`LICENSE.MIT`。2 回目は `already present`。**`fetch` は C++ 限定ではなく、.NET / WPF のソリューションでも動く**) |
| P17 | P16 のあと、`cpp_pkg.py include-dir <vcxproj> '$(SolutionDir)ThirdParty\json'` と、`#include <nlohmann/json.hpp>` で、ビルド | ビルドが通る。**VS で、プロジェクトのプロパティの「追加のインクルード ディレクトリ」に、パスが入っている** | ✔ (2026-10-20 実機、`MfcSdiLayers`: `fetch` → `include-dir` (2 構成とも反映) → `#include <nlohmann/json.hpp>` でビルド `SUCCESS`。戻して差分なし。**VS を開いたままだと、プロパティページに、すぐには反映されない** (VS の再読み込みが要る。SKILL.md に注記)) |
| P18 | `fetch nlohmann/json no-such-tag json` / `fetch no-such-owner/no-such-repo v1 x` | `ENV_ERROR` (取得できない。`git clone` と zip の、両方の失敗が出る)。**タグ・リポジトリの誤りと、ネットワークの問題は、区別できない** (既知の限界。GoogleTest の取得と同じ) | ✔ (2026-10-19 実機: 両方とも `ENV_ERROR` (`git clone failed` → zip も失敗)。タグの誤りとネットワークの問題は区別できない (既知の限界)) |
| P19 | `cpp_pkg.py record-fetch ...` のあと、別のフォルダにクローンし直して、`package_once.sh --file ThirdParty.manifest` | `ThirdParty\json\` が、再現される | ✔ (2026-10-20 実機、`MfcSdiLayers`: `record-fetch` → `ThirdParty/json` を退避 → `--file ThirdParty.manifest` で再作成。`diff -r` 差分なし) |
| P20 | **注入:** フラグを手で書く: `nuget add WpfSample/WpfSample.csproj Foo;calc` / `vcpkg install --triplet evil` / `fetch a/b v1 ..\x` | **すべて `FAILED` (`ERROR: invalid ...` / `usage: ...`)。コマンドは、実行されない** (WSL 側の検証を、迂回した場合の、ホスト側の検証の確認) | ✔ (2026-10-20 実機: 手書きのフラグ `vcpkg install --triplet evil` → `FAILED` (`ERROR: usage: vcpkg install`)。`package_output.txt` に vcpkg の出力なし = 実行されない。nuget / fetch の拒否は、2026-10-19 に確認済み) |
| P21 | Claude Code で、`add-package` を起動する依頼 (「CommunityToolkit.Mvvm を追加して」「fmt を使いたい」) | Skill が起動し、`versions` / `search` で確認 → `add` → ビルド、の順で進む。**名前を、推測で書かない。確認 (`ask`) が出る** (推奨設定を入れていれば)。報告に、バージョンと、変更したファイルが入る | ✔ (2026-10-20 実機、後半: 「fmt を使いたい」で Skill の手順どおり (search → add → install → build)、`SUCCESS`。`FMT_UNICODE=0` が自動で入り、`remove` で消えた。bak との差分は、意図した 2 件のみ。前半の NuGet は 2026-10-19 に確認済み) |
| P22 | **有効化の方法の確認 (v2.4.2 で、内容を改訂):** 公式の記事 (2026-05-19) では、**VS の設定画面は、なく、MSBuild プロパティ `EnableNativePackageReferenceSupport` を `true` にして有効にする** (`Globals` か `Directory.Build.props`)。VS 2026 (18.8.1) の「ツール → オプション」に、C++ の PackageReference に関する設定が、**ほかに**あるか | 設定が、あれば、場所と名前を、報告 (なければ、「ない」)。**プロパティだけで有効になる**ことは、P23 で確認 | ✔ (2026-10-19 公式の記事で確認: 設定画面での有効化は、記載なし。プロパティで有効化。手元の VS 2026 の MSBuild のターゲットの定義とも、一致。VS の画面に、追加の設定があるかは、未確認 (なくても、支障はない)) |
| P23 | **コマンドライン (ウォッチャー) で、PackageReference が動くか:** 使い捨てのプロジェクト (`MfcSdiLayers` のバックアップ版の `LogicLayer` など) の `.vcxproj` の、`Label="Globals"` のグループに `<EnableNativePackageReferenceSupport>true</EnableNativePackageReferenceSupport>` を足し、`<ItemGroup><PackageReference Include="Microsoft.Windows.ImplementationLibrary" Version="(nuget versions で、実在を確認した版)" /></ItemGroup>` を足す。**VS で開いてビルドして、復元を済ませてから**、ウォッチャーで `trigger_build.flag` | VS で、復元が走り、`obj\project.assets.json` ができる。`#include <wil/result.h>` が通り、`SUCCESS`。**ウォッチャー (`/restore` なし) でも、復元済みなら、ビルドが通るか**を、報告する | 見送り (2026-10-19、ユーザーの決定: C++ の PackageReference は Experimental のため、対応しない。再開の条件は、DESIGN 4.26 の「再開の条件」) |
| P24 | **復元をウォッチャーで行えるか:** P23 のあと、`obj\` を削除して (または、新しいクローンで)、ウォッチャーで `trigger_build.flag` | 復元されていないので、`NU1101` / `ファイルが見つからない` などで `FAILED` になる = **C++ のソリューションでも、`/restore` が要る** (今のウォッチャーは、`.NET` があるときだけ `/restore` を付ける)。この結果で、ウォッチャーの変更 (DESIGN 4.26 の、次の一手 (b)) を決める | 見送り (2026-10-19、ユーザーの決定: C++ の PackageReference は Experimental のため、対応しない。再開の条件は、DESIGN 4.26 の「再開の条件」) |

### 1-7. UI テスト (`trigger_uitest.flag`、`docs/DESIGN.md` 4.29、段階 1)

**準備:** ウォッチャーを再配置 (`~/src/copy-host-tools.sh`) し、`poc/flaui/UiPoc` (`C:\workspace\macsignee\source\repos\UiPoc`。環境変数で変える項目は、下の表) で起動する。実行中は、マウス・キーボードに触らない。

| ID | 内容 | 期待 | 状況 |
|---|---|---|---|
| UT1 | **通常のテストから除外:** `UiPoc` (UI テストのプロジェクトだけ) で、`build_test_once.sh` (`trigger_test.flag`) | UI テストは**実行されない**。`ENV_ERROR` (`no tests found`。テストプロジェクトが、1 つもないため)。ウォッチャーの起動画面の `dotnet test (projects: 0)` | ✔ (2026-10-20 実機: `build_test_once.sh` は `ENV_ERROR` (`no tests found`)。UI テストのプロジェクトは、通常のテストから除外された) |
| UT2 | **UI テストの実行:** `uitest_once.sh "$PWD" 900` | `PASSED` (4 件: `Wpf_Uia3_EnterNameAndClear`、`Mfc_Dump_Uia3`、`Mfc_Dump_Uia2`、`Watcher_ProvidesUiTestEnvironment`)。ウォッチャーの画面に `build + UI test` | ✔ (2026-10-20 実機: `uitest_once.sh` が `PASSED` (4 件)。新しい `trigger_uitest.flag` が動いた。最後に、スクリーンショットの一覧が出た) |
| UT3 | **環境変数:** UT2 のあと `.claude-logs/ui-poc/env.txt` | `UITEST_SOLUTION_DIR` (UiPoc のフォルダ)、`UITEST_CONFIGURATION` (Debug)、`UITEST_PLATFORM` (AnyCPU)、`UITEST_SCREENSHOT_DIR` (`...\.claude-logs\ui-screenshots`) | ✔ (2026-10-20 実機: `UITEST_SOLUTION_DIR` / `UITEST_CONFIGURATION=Debug` / `UITEST_PLATFORM=AnyCPU` / `UITEST_SCREENSHOT_DIR=...\.claude-logs\ui-screenshots` が渡った) |
| UT4 | **通常と UI の分離:** 通常のテストと UI テストの、両方があるソリューション (例: `WpfLate` に `UiPoc.UITests` を足す。`UIPOC_WPF_EXE` は、そのアプリの exe) で、`build_test_once.sh` と `uitest_once.sh` | `build_test_once.sh` は、通常のテストだけ (8 件)。`uitest_once.sh` は、UI テストだけ。件数が、互いに混ざらない | ✗ |
| UT5 | **失敗時のスクリーンショット:** PowerShell で `$env:UIPOC_FAIL = "1"` を設定してから、ウォッチャーを起動し、`uitest_once.sh` | `FAILED` (`意図的な失敗`)。**最後に `.claude-logs/ui-screenshots/wpf-failure-*.png` の一覧が出る**。Read ツールで開くと、WPF のウィンドウが写っている | ✔ (2026-10-20 実機、`UIPOC_FAIL=1`: `uitest_once.sh` が `FAILED` (`[ran 4: passed 3 / failed 1 / skipped 0]`、`Assert.Fail に失敗しました。意図的な失敗`、`PocTests.cs(46)`)。**最後に `wpf-failure-screen.png` / `wpf-failure-window.png` の一覧が出た。Claude が画像を読み、ウィンドウの状態 (タイトル `wpfsample`、空の入力欄、`名前を入力してください`、`文字数: 0`、`クリア` / `反転`) と、画面全体の様子を、説明できた** = 失敗時の原因調査に使える。`test_summary.json` も、失敗したテストの名前・メッセージ・場所を持つ。PoC は、成功したテストのスクリーンショットも保存するため、一覧に混ざる (ひな形 (段階 2) は、失敗時だけ撮る)) |
| UT6 | **残ったアプリの後始末:** `$env:UIPOC_LEAK = "1"` (アプリを終了せずに残す) で、**ソリューションのフォルダの下に exe がある** ソリューション (UT4 の `WpfLate` + `UiPoc.UITests`) で `uitest_once.sh`、続けて `build_once.sh` | ウォッチャーの画面に `[UITEST] Stopping leftover process`。アプリのウィンドウが閉じている。次の `build_once.sh` が、exe のロックで失敗しない (`SUCCESS`) | ✗ |
| UT7 | **固まったテスト:** `$env:UIPOC_HANG = "1"`、ウォッチャーを `-UiTestTimeoutSec 20` で起動し、`uitest_once.sh` | `TEST_TIMEOUT`。ウォッチャーが `dotnet test` とアプリを終了し、**ウォッチャー自体は、固まらない** (次のトリガーを受け付ける) | ✔ (2026-10-20 実機、修正版: 別のデスクトップで `-UiTestTimeoutSec 20` → **`TEST_TIMEOUT`** (約 27 秒)。`ENV_ERROR` にならない。ウォッチャーは固まらず、次の `build_once.sh` が `SUCCESS`。通常のデスクトップでの時間切れは、同じ読み取りの修正を使う (別途の実機確認はしていない)) |
| UT8 | **古いウォッチャー:** 再配置の前のウォッチャーで `uitest_once.sh` | `WATCHER_NOT_RUNNING` (疑似ウォッチャーで確認済み: `tests/uitest_once_test.sh`)。メッセージに「再配置して起動し直す」案内 | 疑似: ✔ / 実機: ✗ |

#### 別のデスクトップでの実行 (`-UiTestDesktop separate`、PoC。DESIGN 4.29)

**準備:** ウォッチャーを、PowerShell で `watch_and_build.ps1 -TargetDir <UiPoc> -SolutionPath UiPoc.slnx -UiTestDesktop separate` と起動する。`UiPoc` は、更新版 (`env.txt` に `desktop=` が出る)。**実行中は、メモ帳などで、普通に、キーボードとマウスを使い続ける** (ウィンドウが出ない・フォーカスを奪われないことの確認)。

| ID | 内容 | 期待 | 状況 |
|---|---|---|---|
| UT9 | **別のデスクトップで UT2:** `uitest_once.sh "$PWD" 900` | `PASSED` (4 件)。`env.txt` の `desktop=` が `Default` でなく `ClaudeUiTest<PID>`。ウォッチャーの起動画面に `desktop: separate`。**実行中、ユーザーの画面に、WPF / MFC のウィンドウが出ない。メモ帳での入力が、途切れない** | ✔ (2026-10-20 実機、`-UiTestDesktop separate`、更新版: `uitest_once.sh` が `PASSED` (3 件合格、1 件スキップ = `Mfc_Dump_Uia2` (UIA2 の `Invoke` は、別のデスクトップでは使えない (既知)))。`env.txt` は `desktop=ClaudeUiTest...`。**ユーザーの報告: 実行中、ウィンドウは画面に出ず、入力も途切れなかった**) |
| UT10 | **別のデスクトップで、UIA が動くか:** UT9 の `mfc-uia3-tree.txt` / `mfc-uia2-tree.txt` / `wpf-uia3-tree.txt` を、通常のデスクトップ (UT2) と比べる | 要素の見え方 (AutomationId、Name) が同じ。`Invoke` / `Value` の操作が通る (`PASSED`) | ✔ (2026-10-20 実機: **UIA3 は、別のデスクトップで、WPF / MFC とも、要素の見え方が同じで、`Value` / `Invoke` の操作が通る**。**UIA2 は、別のデスクトップで、`Invoke` が失敗し、`LegacyIAccessible` も UIA2 では使えない (`NotSupportedByFrameworkException`) → UIA2 は、別のデスクトップでは、使わない。UIA3 を標準にする**) |
| UT11 | **別のデスクトップで、スクリーンショット:** UT9 の `ui-screenshots/*-window.png` を、Claude が Read で開く | **黒や空の画像でなく、ウィンドウの内容が写っている** (WPF の入力欄・挨拶・ボタン、MFC の OK / Cancel)。黒ければ、`Capture` (`CopyFromScreen`) が別のデスクトップで使えない = `PrintWindow` 方式に変える | ✔ (2026-10-20 実機、更新版: **WPF のクライアント領域に、入力欄 (太郎)、挨拶 (こんにちは、太郎 さん)、文字数: 2、クリア / 反転ボタンが写った** (ソフトウェアレンダリングで解消)。MFC (UIA3 / UIA2) も、ウィンドウの内容が写る。いずれも、Claude が Read で読める) |
| UT12 | **別のデスクトップで、失敗と時間切れ:** `UIPOC_FAIL=1` (UT5)、`UIPOC_HANG=1` + `-UiTestTimeoutSec 20` (UT7) | UT5: `FAILED` とスクリーンショット (UT11 と同じく、内容が写る)。UT7: **`TEST_TIMEOUT`** (`ENV_ERROR` でない)、約 20〜25 秒で返り、次の `build_once.sh` が `SUCCESS` | ✔ (2026-10-20 実機、別のデスクトップ: **UT12a (失敗)** `FAILED`、`Assert.Fail`、`wpf-failure-window.png` に WPF の内容が写った。**UT12b (時間切れ)** `-UiTestDesktop separate -UiTestTimeoutSec 20` で `TEST_TIMEOUT` (`=== UiPoc.UITests (dotnet test): TIMEOUT after 20s (killed) ===`)。**約 27 秒で返り、`ENV_ERROR` にならなかった** (UT7 の不具合の修正を確認)。直後の `build_once.sh` は `SUCCESS` (ウォッチャーは固まらない)。ユーザーの確認: `wpfsample.exe` は残っていない) |
| UT13 | **残ったアプリの後始末 (ジョブオブジェクト):** `UIPOC_LEAK=1` (アプリを終了せずに残す) で `uitest_once.sh` のあと、タスクマネージャーで `wpfsample.exe` / `MfcDlgLayers.exe` を探す | **プロセスが残っていない** (ジョブの終了で、すべて終了)。`UiPoc` のフォルダの外の exe でも、同様 | ✔ (2026-10-20 実機、別のデスクトップ、`UIPOC_LEAK=1` (アプリを終了せずに残す): `uitest_once.sh` が `PASSED`。ユーザーがタスクマネージャーで確認: **`wpfsample.exe` / `MfcDlgLayers.exe` が残っていない** (ジョブオブジェクトの終了で、`UiPoc` のフォルダの外の exe も、すべて終了)。直後の `build_once.sh` は `SUCCESS`。なお、WSL から `tasklist.exe` は、実行できない (WSL の相互運用のエラー)ので、ユーザーの確認による) |
| UT14 | **WPF の描画設定の復元:** (a) 通常の実行のあと `reg query "HKCU\Software\Microsoft\Avalon.Graphics"` と、`%LOCALAPPDATA%\claude-watcher\wpf-hwaccel-backup.txt` | (a) `DisableHWAcceleration` が、実行前の状態に戻っている (もともと無ければ、無い)。記録ファイルが無い。 | ✔ (2026-10-20 実機: UI テストを複数回実行したあと、`reg query "HKCU\Software\Microsoft\Avalon.Graphics"` に、`DisableHWAcceleration` は無い (もともと無かった。キーには `IgnoreDwmFlushErrors` が、もとからある) = 元に戻っている。`%LOCALAPPDATA%\claude-watcher\` は空 = 記録ファイルは消えている) |
| UT14b | **異常終了からの復旧:** `UIPOC_HANG=1` (固まる) で `uitest_once.sh` を実行中に、ウォッチャーのウィンドウを、**閉じる (強制終了)**。`reg query` で `DisableHWAcceleration = 1` と、記録ファイルが、残っていることを確認。ウォッチャーを起動し直す | 起動画面に `WPF rendering setting restored (...)`。`reg query` が、実行前の状態に戻り、記録ファイルが消える | ✗ |

#### UI テストのひな形と Skill (段階 2、`docs/DESIGN.md` 4.29)

| ID | 内容 | 期待 | 状況 |
|---|---|---|---|
| UT15 | **WPF: 生成と実行:** 使い捨てのフォルダで `new_solution.py <フォルダ> --type wpf --layers data,logic,viewmodel --tests mstest --ui-tests flaui` → ウォッチャーを起動 (既定の別のデスクトップ) → `build_once.sh` → `build_test_once.sh` → `uitest_once.sh` | ビルド `SUCCESS` (警告 0)。**`build_test_once.sh` は、通常のテストだけ** (8 件。UI テストは含まれない)。**`uitest_once.sh` は `PASSED` (3 件: `MainWindow_Opens_WithTitle`、`Greeting_NameEntered_ShowsGreeting`、`ClearButton_Invoked_ClearsName`)**。実行中、ユーザーの画面に、ウィンドウが出ない。**生成した C# が、コンパイルできる** (できなければ、ひな形を直す) | ✔ (2026-10-21 実機、`WpfUi15`: 生成 (7 プロジェクト) → ウォッチャーの起動画面 `desktop: separate` (既定。`run_watcher.cmd` で起動) → `build_once.sh` `SUCCESS` (警告 0、NuGet の復元 (MSTest / FlaUI) を含む。**生成した C# が、修正なしでコンパイルできた**) → `build_test_once.sh` `PASSED` (8 件: `DataLayer.Tests` 1 / `LogicLayer.Tests` 1 / `ViewModels.Tests` 6 = **通常のテストだけ。UI テストは含まれない**) → `uitest_once.sh` `PASSED` (3 件。trx で、3 つのテスト名とも Passed)。**ユーザーの確認: 実行中、ウィンドウは画面に出ず、入力も途切れなかった**) |
| UT16 | **WPF: 失敗時のスクリーンショット:** UT15 のテストの期待値をわざと変え (`こんにちは、太郎 さん` → `こんにちは、花子 さん`)、`uitest_once.sh` | `FAILED`。最後に `.claude-logs/ui-screenshots/Greeting_NameEntered_ShowsGreeting-window.png` が出る。Claude が Read で開くと、WPF のウィンドウ (入力 `太郎`、挨拶) が写っている。**成功したテストの画像は、出ない** | ✔ (2026-10-21 実機、`WpfUi15`: 期待値を `花子` に変えて `uitest_once.sh` → `FAILED`。**失敗したテスト (`Greeting_NameEntered_ShowsGreeting`) の画像だけが出た (成功したテストの画像は出ない)**。画像 (コンソールの Claude の説明): WPF のウィンドウが内容つきで写り、入力欄 `太郎`、挨拶 `こんにちは、太郎 さん` = 画面は正常で、テストの期待値だけが誤っている、と画像から分かった。元に戻して `PASSED` (3 件)) |
| UT17 | **後付け:** すでにある WPF のソリューション (例: `WpfSample`) に `new_solution.py <フォルダ> --ui-tests flaui` | `WpfSample.UITests` が足され、`.slnx` に登録される。View に AutomationId がなければ、NOTE が出て、一般のひな形 (ウィンドウが開くだけ) になる。`wpf-check` に UI002 が出る | ✔ (2026-10-21 実機、`WpfUi17`: UI テストなしで生成 (7 プロジェクト) → ベースライン `PASSED` (8 件) → `--ui-tests flaui --dry-run` (何も書かれない) → 後付け (`WpfUi17.UITests` 生成、`.slnx` に登録、`CLAUDE.md` に節追記) → 二度目は `すでに存在する` (終了コード 3) → `build_once.sh` `SUCCESS` (コンパイルエラーなし) → `build_test_once.sh` `PASSED` (8 件のまま。UI テストを含まない) → `uitest_once.sh` `PASSED` (3 件) → `wpf-check` 0 件。**UT17b: View から AutomationId を消すと、`wpf-check` UI002 (warning) が 2 件 (`TextBox` と `Button`。`TextBlock` は、操作しないので、対象外 = 仕様どおり。期待の「3 件」は、誤り)、`uitest_once.sh` は `FAILED` (2 件。`NameTextBox` の要素が見つからない)。スクリーンショットは、名前の入力前の初期状態** (要素の探索に失敗した時点で撮られるため)。元に戻すと `PASSED` (3 件)。**ウォッチャーの desktop が、最初 `default` だった** (ユーザーが `run_watcher.cmd` で起動し直して `separate`。環境変数 `WATCH_UI_DESKTOP` が、コマンドプロンプトのウィンドウに残っていた可能性) |
| UT18 | **MFC (C++) への UI テスト (混在):** `MfcDlgLayers` のコピー (または `new_solution.py <フォルダ> --type mfc-dialog --layers none --tests none --ui-tests flaui`) で、ウォッチャー → `build_once.sh` → `uitest_once.sh` | **C++ と .NET の混在のソリューションが、ビルドできる** (`.slnx` の構成の対応づけ。Platform x64 で、`.csproj` が、ビルドされる)。`uitest_once.sh` が `PASSED` (`MainWindow_Opens_WithTitle`。`AppLocator` が `x64\Debug\<アプリ>.exe` を見つける)。**混在で、ビルドや `dotnet test` の出力先が合わない場合 (`bin\x64\Debug`) は、`-DotnetTestArgs "-p:Platform=x64"` (U15) や、ウォッチャーの変更が要る** | ✔ (2026-10-21 実機、`MfcUi18` (mfc-dialog + `--ui-tests flaui`、**C++ と .NET の混在**): ウォッチャーの起動画面 `Solution : C++ + .NET (build features: cpp,restore)` / `Build : Debug|x64` / `desktop: separate`。`build_once.sh` **`SUCCESS`** (コンパイルエラーなし、`MSB4126` などの構成の対応づけのエラーなし)。成果物: C++ は `x64\Debug\MfcUi18.exe`、.NET は `MfcUi18.UITests\bin\Debug\net8.0-windows\MfcUi18.UITests.dll` (`bin\x64\Debug` ではない = **`dotnet test --no-build` が DLL を見つけられた**)。`build_test_once.sh` は `ENV_ERROR` (`no tests found` = 想定内)。`uitest_once.sh` `PASSED` (1 件)。**テストを 2 件足して `PASSED` (3 件): MFC のコントロール ID `1` (IDOK) / `2` (IDCANCEL) が AutomationId で、`Find("1").Name == "OK"`、`Find("2").AsButton().Invoke()` でダイアログが終了した。** `mfc-check` は 0 件。`ui-trace.txt`: `desktop: ClaudeUiTest...`、`MfcUi18.exe` の起動 (約 0.1 秒)、`find: 1` / `find: 2`。**混在のソリューションが、実機でビルド・UI テストの実行できた**。注: 生成の出力が、UI テストの足し込みが先、本体が後の順に出た (標準出力のバッファ。v2.5.1 で、フラッシュを追加)) |
| UT19 | **流れ: Green のあとに、UI テストを、追加で実行する:** UT15 のソリューション (`WpfUi15`) で、Claude Code に、画面を伴う変更 (例: 「挨拶を `こんにちは、○○ さん` から `ようこそ、○○ さん` に変えて」。ViewModel のテスト → 実装 → UI テストの期待値の更新が、要る) を、依頼する (`/add-feature` を使わない、直接の依頼) | `wpf-test-first` (Red) → 実装 → `build-test-loop` (`build_test_once.sh` が `PASSED`) → **続けて、UI テストのプロジェクトがあることを確かめ、`uitest_once.sh` を実行する** (`PASSED`、または失敗なら、スクリーンショットを Read で読む)。UI テストを先に書かない。ユーザーに「触らないで」と頼まない。マウス・キーボードの入力 (`Click()`) を使わない | ✔ (2026-10-21 実機、`WpfUi15`、Skill 再配布後: 「挨拶の文言を変えたい。…テスト先行で進めて」の依頼で、`wpf-test-first` を使い、Red (`Assert.AreEqual に失敗しました`、`[ran 8: passed 7 / failed 1]`) → Green (`PASSED`) → **Green のあと、ユーザーに確認せず、自分の判断で `uitest_once.sh` を実行した** (「UI テストプロジェクトがあるので、Green の後に 1 回、uitest_once.sh を実行します」) → UI テストが `FAILED` (`Greeting_NameEntered_ShowsGreeting`: `挨拶が、変わらない: いらっしゃいませ、太郎 さん`) → **スクリーンショットを Read で開き** (入力 `太郎`、挨拶 `いらっしゃいませ、太郎 さん`) → 期待値を、画面の実際の表示に合わせて直し (等値比較のまま。アサーションは弱めていない) → `PASSED`。ユーザーに「触らないで」とは頼んでいない。変更: `MainViewModel.cs` / `MainViewModelTests.cs` / `MainWindowUiTests.cs`。**要点: `CLAUDE.md` の命令形の指示と、再配布した `build-test-loop` で、UI テストが、Green のあとに、追加で実行された**) |

#### 目で確かめるモード (ユーザーのデスクトップ + スローモーション)

**準備:** `~/src/copy-host-tools.sh` で再配置 (`run_watcher_visible.cmd` が増える)。`WpfUi15` で、`add_ui_tests.py <フォルダ> --refresh-support-files` を実行 (`UiNative.cs` が増え、`UiTestBase.cs` / `Screenshots.cs` が更新される)。ウォッチャーを `run_watcher_visible.cmd C:\workspace\macsignee\source\repos\WpfUi15` で起動する。

| ID | 内容 | 期待 | 状況 |
|---|---|---|---|
| UT20 | **目で見える実行:** `uitest_once.sh "$PWD" 900` を、ユーザーが画面を見ながら | ウォッチャーの起動画面に `desktop: default`、`slow-motion: 800ms`。**ユーザーのデスクトップに、WPF のウィンドウが出て、入力欄に `太郎` が入り、挨拶が変わり、クリアで空になるのが、順番に見える** (操作の間に約 0.8 秒の待ち)。`PASSED` (3 件) | ✔ (2026-10-21 実機、`WpfUi15`、**`watch_and_build.ps1` の直接起動** (`-UiTestDesktop default -UiTestSlowMoMs 800`。バナー: `UI test : ... (desktop: default, timeout 600s, slow-motion: 800ms)`): `--refresh-support-files` で 4 つのファイルが更新され (テストの本体は不変)、`build_once.sh` `SUCCESS` (新しい C# がコンパイルできた)、`uitest_once.sh` `PASSED` (3 件)。**ユーザーの確認: ウィンドウが画面に出て、入力 → 挨拶の変化 → クリアが、順番に見えた。待ち (800ms) はちょうどよい** (1 回目は、始まりに気づかず「見えなかった」→ 2 回目で確認。始まる合図があると、確認しやすい)。**`run_watcher_visible.cmd` 経由の起動は、バナーに `slow-motion` が出ず、未解決** (ps1 の直接起動は、問題なし。原因は未特定。バッチの `[visible mode]` の行も、ユーザーの環境で、出なかった)) |
| UT21 | **操作の記録:** UT20 のあと、`uitest_once.sh` の最後の出力と、`.claude-logs/ui-screenshots/ui-trace.txt` | 最後に `ui-trace (N lines ...)` と、`=== MainWindow_Opens_WithTitle: Passed` など 3 つのテストの結果の行。ui-trace.txt に、`start (desktop: Default, slowmo: 800 ms)`、`launched: ...WpfUi15.exe`、`find: NameTextBox` / `GreetingText` / `ClearButton` が、順に残る | ✔ (2026-10-21 実機: `ui-trace.txt` に、テストごとの `=== <テスト名>: start (desktop: Default, slowmo: 800 ms)`、`launched: ...\WpfUi15.exe (title: WpfUi15)`、`find: NameTextBox` / `GreetingText` / `ClearButton`、`=== <テスト名>: Passed` が、時刻つきで、順に残った (15 行)。`MainWindow_Opens_WithTitle` は、要素を探さないので `find:` がない。`WaitFor` の中の `Find` も、待ちごとに記録され、待ちが重なる) |
| UT22 | **ユーザーのデスクトップでの、失敗時のスクリーンショット:** UT16 と同じく、期待値をわざと変えて `uitest_once.sh` | `FAILED`。`Greeting_NameEntered_ShowsGreeting-window.png` に、WPF のウィンドウの内容が写る (PrintWindow が空白なら、画面のコピーに切り替わる = トレースに `used a screen capture` が出ることがある)。**空白・真っ黒でない** | ✔ (2026-10-21 実機、`WpfUi15`、ユーザーのデスクトップ (`-UiTestDesktop default`): 期待値を `こんにちは、花子 さん` に変えて `uitest_once.sh` → `FAILED`。コンソールの Claude の報告: スクリーンショットと `ui-trace.txt` で、実際の画面 (`いらっしゃいませ、太郎 さん`) を確認でき、元に戻して `PASSED`。**未確認: どちらの方式で撮れたか (PrintWindow / 画面のコピーへの切り替え)。報告に、トレースの行が含まれていない** (復元後の `PASSED` の実行で、画像とトレースは消えている)) |

### 1-3. 起動まわり (`run_watcher.cmd`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| R1 | `run_watcher.cmd <dir>` | ヘッダー (`Project / Solution / Build`) が出る。`.slnx` → `.sln` の順で自動検出 | ✔ (`.sln`) |
| R2 | 末尾に `\` を付けて渡す | 同じく起動する (引数が壊れない) | ✗ |
| R3 | フォルダをドラッグ&ドロップ | 起動する | ✗ |
| R4 | スペースを含むパス | 起動する | ✗ |
| R5 | **引数なし**で `run_watcher.cmd` を起動 (`.sln` がない場所に、cmd を置いた場合) | `ERROR: no .sln / .slnx found in ...`、`NOTE: no ProjectDir argument was given ...`、`Usage` と `Example` が出て、キー入力待ち → 終了コード 2 | ✔ (v1.0.1) |
| R6 | 存在しないフォルダを渡す | `ERROR: project folder not found: ...` と `Usage` が出る | ✗ |

### 1-4. 二重起動の防止 (`watch_and_build.ps1`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| M1 | ウォッチャーを起動したまま、**同じフォルダ**で、もう 1 つ `run_watcher.cmd` を起動 | 2 つ目のウィンドウに `ERROR: a watcher is already running for this folder: ...` と `Use that window, or close it first.` が出て、`Watcher exited with code 3.` で、キー入力待ち。1 つ目は動き続け、フラグを処理できる | ✔ |
| M2 | 1 つ目のウィンドウを閉じてから、もう一度起動 | 二重起動と判定されず、起動できる (ミューテックスが解放されている) | ✔ |
| M3 | 1 つ目を、タスクマネージャーなどで、強制終了してから、起動 | 同上 (異常終了しても、古いロックが残らない) | ✗ |
| M4 | **別のフォルダ**のウォッチャーが動いている状態で、このフォルダのウォッチャーを起動 | 干渉せずに、起動できる (ミューテックスは、フォルダごと) | ✗ |
| M5 | ps1 を直接起動し、`-TargetDir` の、大文字小文字や、末尾の `\` だけを変える | 同じフォルダとして扱われ、2 つ目は拒否される | ✗ |

## 2. Skill 経由 (Claude Code)

依頼文 (共通):
```
build-test-loop のSkillを使って、テストが通るまで直してください。
```

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| S1 | 正常な状態 | `PASSED` を受けて、修正せずに、1〜2行で報告して止まる | ✔ |
| S2 | 本体のロジックにバグ (テストが落ちる) | `FAILED` → **ソース側を直す** (テストは変えない) → 再実行 → `PASSED` で止まる。共通の原因を 1 回で直す | ✔ |
| S3 | 構文エラー + (別の) テストが落ちるバグ | `BUILD_FAILED` → 構文エラーを直す → `FAILED` → バグを直す → `PASSED` | ✔ |
| S4 | **テストの期待値を誤った値にする** (ソースは正しい) | ソースを変えずに、**変更前にユーザーへ確認**する (根拠を添えて)。承認後に 1 か所だけ直して `PASSED` | ✔ |
| S5 | ウォッチャーを起動しない | 約 15 秒で `WATCHER_NOT_RUNNING`。ソースを触らず、起動を依頼して止まる。再試行しない | ✔ |
| S6 | `-TestExePattern 'NoSuch\.exe$'` でウォッチャーを起動 | `ENV_ERROR`。ソースもテストも触らず、環境の問題として報告して止まる | ✔ |
| S7 | `-TestTimeoutSec` を、全体の実行時間より短くする | `TEST_TIMEOUT`。直前にソースを変えていなければ、直さず報告して止まる (制限時間の確認を依頼) | ✗ (ホスト側 T4 のみ) |
| S8 | ユーザー Skill (`~/.claude/skills`) のみ配置 (プロジェクト側は退避) | S1 と同じ動き (ユーザー Skill が使われる) | ✔ (S1 のみ) |
| S9 | プロジェクトの `.claude/settings.json` に `permissions.ask` (`docs/RECOMMENDED-SETTINGS.md`) を設定し、Claude に、**テストファイルを編集**させる (例: S4 の流れ) | 編集の前に、**権限の確認ダイアログ**が出る。拒否すると、Claude が、別の方法 (別のツールやコマンド) で、同じ編集を、行わない | ✗ |
| S9a | S9 の続きで、**同じテストファイルを、もう一度、編集**させる | **2 回目も、確認が出る** (確認の単位は、ツール呼び出し 1 回ごと。公式の記載からの読み取り) | ✗ |
| S9b | S9 の確認ダイアログを、よく見る: 「**このセッションでは、許可**」のような選択肢が、あるか | **あるかどうかを、記録する** (公式に、明記されていない)。ある場合は、選んだあとに、同じファイルを編集させる | ✗ |
| S9c | S9b で、その選択肢を選んだあとの、編集 | **確認が止まるかを、記録する。** 止まる場合は、`ask` が事実上、無効になり、設定の目的が損なわれる。フックや `deny` との併用を、検討する (`docs/RECOMMENDED-SETTINGS.md` 4 章) | ✗ |
| S9d | `acceptEdits` (編集の自動承認) モードで、テストファイルを編集させる | **確認が出る** (公式: 明示的な `ask` ルールに一致するものは、どのモードでも、自動承認されない)。確認で「セッション許可」を選んだ場合の挙動は、記録する | ✗ |
| S9e | **本体のソース** (`DoubleBufferSample/` 配下) を、編集させる (例: S2) | **確認は、出ない。** テストプロジェクト以外の編集は、影響を受けない | ✗ |
| S9f | ビルドエラーの修正で、テストプロジェクトの `.vcxproj` を、編集させる | 確認が出る (`**/*Test/**` に一致するため)。ビルドの設定の修正でも、出ることを、把握しておく | ✗ |
| S10 | S2 (ソースのバグを直す) を実行する | 完了時の報告に、**変更ファイルの一覧**と、「テストファイルの変更なし」が、含まれる。`git commit` / `git push` は、実行されない。変更がない場合 (S1) は、「変更なし」で、`git status` を実行しない | ✗ |
| S11 | **同じ未宣言の識別子を、複数のファイルで使う** (例: ヘッダの宣言を消す)。`auto-build` で、ビルドさせる | `FAILED` の出力が、**要約形式**: 見出し `N errors (M unique) in K files`、同じエラーが `[1] ... xN` の 1 つにまとまり、場所が最大 3 つ。`build_error.log` は、生のまま残る。`.claude-logs/build_summary.json` ができる。Claude は、`[1]` から直し、1 回の再ビルドで、`SUCCESS` | ✗ |
| S12 | **リンクエラー**を起こす (例: 宣言だけで、定義がない関数を呼ぶ)。`auto-build` で、ビルドさせる | 見出しの内訳に `link N`。`LNK2019` と、続く `LNK1120` が、別の `[n]` として出る。場所が `Foo.obj` などの形でも、要約が崩れない。Claude は、宣言ではなく、定義 / ライブラリ指定を直す | ✗ |
| S13 | S3 の構文エラーを、`build-test-loop` で起こす | `BUILD_FAILED` の 2 行目以降が、S11 と同じ要約形式。直したあと、テストの段階 (`FAILED` / `PASSED`) に進む | ✗ |
| S14 | S11 の状態で、`PATH` から `python3` を外して (または、`summarize_build_log.py` を退避して) 実行する (WSL 側のみ) | 要約ではなく、**従来の生ログ** (最大 40 行) が出る。1 行目は `FAILED` のまま、rc=1 | ✗ |
| S15 | 同じ原因で、**複数のテストが落ちる**バグ (例: 共通の関数の計算ミス)。`build-test-loop` で実行 | `FAILED` の出力が**要約形式**: 見出し `N failed tests in K suites`、同じメッセージの失敗が `[1] xN` の 1 つにまとまり、`tests:` (最大 5) と `at:` (最大 3) が出る。Claude は、共通の原因を 1 回で直し、再実行で `PASSED` | ✗ |
| S16 | **値の違う失敗**を、2 種類以上 (例: 別の関数のバグも入れる) | 値 / メッセージの違う失敗が、別の `[n]` に分かれる。組の数だけ原因を探す動き | ✗ |
| S17 | テストの中で、**クラッシュ** (例: nullptr 参照) させる | 失敗したテスト名がなければ、要約ではなく**従来の表示** (`other` ではなく、生の報告) で、クラッシュが分かる。`Hung test` / `TEST_TIMEOUT` は、従来どおり | ✗ |
| S18 | S15 の状態で、`summarize_test_log.py` を退避して実行する (WSL 側のみ) | 従来の `Failed tests (N):` の一覧と詳細 (最大 60 行) が出る。1 行目は `FAILED`、rc=1 のまま | ✗ |
| S19 | **警告が出るコード** (例: `int x = 1.5;` の型の縮小 C4244) を、新しく足して、`auto-build` でビルドする (**全体を再ビルド**: `Rebuild` か、その `.cpp` を触る) | `SUCCESS` の次の行に、**1 行だけ** `warnings: N (M unique): C4244 xK ...`。Claude は、警告を直さず、報告に 1 行添え、自分が足した行由来なら、直すかを尋ねる。`.claude-logs/warnings_summary.json` ができ、場所が**相対パス** | ✗ |
| S20 | S19 の直後に、ソースを触らず、もう一度ビルド (差分ビルド) | `SUCCESS` だけ (警告の行は出ない。再コンパイルがないため)。Claude は「警告がない」と報告しない | ✗ |
| S21 | 警告がないコードで、`build-test-loop` を実行 | `PASSED` だけ (警告の行なし)。S1 と同じ動き | ✗ |
| S22 | ビルドエラーと警告が、同時に出るコードで実行 | `FAILED` のエラー要約だけ (警告の行は出ない。`warnings.log` は、エラーの出たビルドの分でも、`.claude-logs/` に残る) | ✗ |

### 2-0. `/brainstorm` と `/add-feature`

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| B1 | `/brainstorm 注文の税込み合計` | 質問が、**1 回に 1 つ**。具体例を先に聞く。コード・テスト・プロジェクト・**仕様書**を、作らない。決まらない項目は、「未決」として残す | ✔ (2026-10-14 実機: ClaudeProject) |
| B2 | B1 で、メモに残してよいと伝える | `docs/ideas/<名前>.md` (`整理: 未`) が保存される。未決の件数が示され、`/update-from-ideas docs/ideas/<名前>.md` を案内して、自動では、進まない | ✔ (2026-10-14 実機: ClaudeProject) |
| B3 | 未決を残したまま、`/update-from-ideas` で、確定したいと言う | 状態を `確定` にしない (未決事項の解消を、促す) | ✔ (2026-10-14 実機: ClaudeProject) |
| A1 | `/add-feature` (引数なし) で、`確定` の仕様書が 1 つ | 「これでよいか」を確認する | ✔ (2026-10-14 実機: ClaudeProject) |
| A2 | `下書き` の仕様書を渡す / メモだけで、仕様書がない | 実装に進まず、`/update-from-ideas` (メモだけなら、それで整理) を案内して止まる | ✗ |
| A3 | 確定した仕様書を渡す | 計画 (タスク、テストケースと仕様の対応、やらないこと) を示し、**承認を待つ。承認前に、ファイルを、何も作らない** | ✔ (2026-10-14 実機: ClaudeProject) |
| A4 | A3 で、計画の修正を依頼 | 計画を直して、再び見せる | ✗ |
| A5 | 承認後、DLL / テスト exe がない状態 | セットアップ → ベースラインが緑 → タスク 1 へ | ✗ |
| A6 | タスクの Red のあと | **テストの確認のゲートで止まる** (計画の承認があっても、飛ばさない)。承認後に、Green に進む | ✔ (2026-10-14 実機: ClaudeProject) |
| A7 | 実装中に、計画にない変更が必要になる状況 | 止まって、ユーザーに確認する (計画を直す) | ✗ |
| A8 | 完了 | 全体のビルド + 全テスト `PASSED`、**仕様書の例・境界値・異常系と、テストの対応表**、未確認のこと、テストファイルの一覧が、報告される。`git commit` は、しない | ✔ (2026-10-14 実機: ClaudeProject) |
| A9 | 実装中に、仕様の変更を依頼する | 実装を止めて、仕様書を直す (`/brainstorm`) ことを促す | ✗ |

### 2-0c. `/new-solution`

空のフォルダ (例: `C:\...\MFCTDDTest`) を作り、そこで Claude Code を起動して試す。**手書きのプロジェクトが、Visual Studio / ウォッチャーでビルドできるかの、最初の実機確認。**

| # | 指定 | 期待する動き | 状況 |
|---|---|---|---|
| N0 | `/new-solution` (引数なし) | メインの種類、層、テストを**質問する** (`--tests` は、必ず質問)。案 (dry-run の内容) を示して了承を求める | ✗ |
| N1 | `--type mfc --layers none --tests none` | `MFCTDDTest.slnx` と `MFCTDDTest/` (MFC SDI) だけ。テストなし。**ビルドが `SUCCESS`** (`auto-build`) | ✗ |
| N2 | `--type mfc --layers logic,data --tests none` | メイン + `DataLayer` + `LogicLayer` (DLL)。テストなし。ビルドが `SUCCESS` | ✔ (2026-10-14 実機: ClaudeProject) |
| N3 | `--type mfc --layers logic,data --tests gtest` | N2 + `DataLayerTest` / `LogicLayerTest`。GoogleTest が `packages\` にコピーされる。**ビルドとテストが `PASSED`** (2 つのテスト exe) | ✗ |
| N4 | N3 で、フォルダ名が `MFCTDDTest` (`Test` で終わる) | メインに `_Main` の `TargetName` が付く。**`MFCTDDTest_Main.exe` が、テストとして起動されない** (`PASSED`) | ✗ |
| N5 | `--type dll --layers none --tests gtest` | メイン DLL + `<名前>Test`。`PASSED` | ✗ |
| N6 | `--type win32 ...` / `--type console ...` | それぞれ、ビルドが通る | ✗ |
| N3s | N3 の `--gtest source` 版 (`/new-solution --type mfc --layers logic,data --tests gtest --gtest source`) | `gtest` プロジェクトが入る。作成後、ウォッチャーを起動して、`gtest_once.sh` で取得 → `PASSED`。**初回は、`gtest` のコンパイルで、少し長い** | △ (2026-10-14 実機: 後付け経由で `PASSED`。新規作成 + `gtest_once.sh` での取得は、未確認 (取得自体は G1〜G5 で確認)) |
| N3a | コピー元のない環境で `--gtest auto` | `GTEST_MODE: source` / `to-fetch`。ウォッチャーの起動後に、取得 → ベースライン → `PASSED` | ✗ |
| N3b | 取得が `FAILED` (ネットワーク遮断) | 報告して止まり、手動のコピーか、`nuget` 方式への切り替えを案内する | ✗ |
| N13 | `--layer-kind lib` (層を静的ライブラリ) | 層が静的ライブラリ。テストが、リンクできて、`PASSED` | ✗ |
| N14 | `--layers logic:OrderLogic,data:OrderData` | 指定した名前で作成される。ビルドとテストが通る | ✗ |
| N15 | `/new-solution --spec docs/specs/<名前>.md` (構成案あり) | 構成案の内容が、案に反映される (未定の項目は、質問する)。案を見せて、了承を得てから作成 | ✗ |
| N16 | 新規作成のあと、`.gitattributes` を確認し、`git init` → Visual Studio でファイルを編集・保存 → `git status` / `git diff` (WSL の git と Windows の Git の、両方で) | `.gitattributes` ができている (最小版)。**どちらの git でも、改行だけの差分が出ない**。`git ls-files --eol` で、保存が `i/lf` | ✔ (2026-10-15 実機: ClaudeProject / ClaudeProjectCopy。0a. を明示した版で再確認) |
| N17 | **既存の** C++ ソリューション (`.gitattributes` なし、CRLF のファイルあり) のフォルダで、`/add-feature` を開始 | 最初の読み取り確認で、**1 回だけ**、提案が出る (件数、最小版、導入の手順)。作業は止まらない。「追加する」→ ファイルができ、**git のステージ・コミットはされない**。`git add --renormalize .` を、自分で実行して、改行だけの変更であることを確認 | ✔ (2026-10-15 実機: ClaudeProject / ClaudeProjectCopy。0a. を明示した版で再確認) |
| N18 | N17 で「今後も見送る」 | `CLAUDE.md` に `- 改行コードの提案: 見送り` が足される。次の `/add-feature` では、提案が出ない | ✗ |
| N19 | LF のみのリポジトリ / git でないフォルダ / `.gitattributes` のあるリポジトリで `/add-feature` | 提案は、出ない (`lf-only` / `not-a-repo` / `ok`) | ✗ |
| N6b | `--type lib --layers none --tests gtest` | 静的ライブラリ + `<名前>Test`。**ビルドとテストが `PASSED`** (テスト exe が、`.lib` をリンクできる) | ✗ |
| N7 | `--type console --layers none --tests gtest` | 矛盾として、エラー (何も書かれない) | ✗ |
| N8 | N2 の後、`/new-solution --tests gtest` (後付け) | `DataLayerTest` / `LogicLayerTest` が増える。`CLAUDE.md` が `テスト: あり` に更新される。`PASSED` | ✔ (2026-10-14 実機: ClaudeProject。source 方式) |
| N9 | すでにソリューションがあるフォルダで、`--tests gtest` なしの `/new-solution` | 何も書かずに、「後付けだけできる」と案内して止まる | ✗ |
| N10 | GoogleTest のコピー元がない環境で、`--tests gtest` | `GTEST_PACKAGE: missing`。コピー元の指定か、Visual Studio での復元を依頼して待つ | ✗ |
| N11 | 作成した `.slnx` を、Visual Studio 2026 で開く | エラーなく開く。プロジェクト構成 (x64 の Debug / Release) が正しい | ✔ (2026-10-14 実機: ClaudeProject) |
| N12 | N1〜N2 (テストなし) のあと `/brainstorm` → `/update-from-ideas` → `/add-feature` | テストなしの流れ (計画 → 承認 → 実装 → ビルド確認 → 手動確認)。Red / Green は、出てこない | ✗ |

### 2-0b. `/update-from-ideas`

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| U8 | **メモ** (B2 の出力) を渡す: `/update-from-ideas docs/ideas/<名前>.md` | メモを仕分け (取り込む / 保留 / 別機能 / 却下)、**仕様書の草案の全文**と、「テストに落とせる具体さか」の点検結果を示す。**承認前に、ファイルを作らない** | ✔ (2026-10-14 実機: ClaudeProject) |
| U9 | U8 を承認 | `docs/specs/<名前>.md` ができる (未決が 0 件で、「確定」と言えば `確定`。残れば `下書き`)。メモの `整理:` が `済 (→ ...)` になる。メモは、残る | ✔ (2026-10-14 実機: ClaudeProject) |
| U10 | U8 で、メモの内容が矛盾している / 足りない | 推測で埋めず、**1 回に 1 つ**質問する | ✗ |
| U11 | ソリューションがない状態で U9 | **構成案** (メインの種類・層・テスト・名前空間と根拠) と、`/new-solution ...` のコマンドを示す。テストは、ユーザーに確認する (`gtest` を勧める)。**自動で、作成しない** | ✗ |
| U12 | ソリューションがある状態で U9 | 構成案は、出さない。`/add-feature docs/specs/<名前>.md` を案内する | ✔ (2026-10-14 実機: ClaudeProject) |
| U13 | `整理: 済` のメモを渡す | 対象にしない (ユーザーが明示した場合を除く) | ✗ |


| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| U1 | 確定した仕様書 + `/update-from-ideas docs/specs/xxx.md 端数は切り上げにしたい` | アイデアを仕分けて (理由つき)、変更案を示し、**承認を待つ。承認前に、ファイルを変えない** | ✗ |
| U2 | `docs/ideas.md` に 3 件 (この機能の変更 / 別機能 / 矛盾するもの) | 取り込む・別機能に分かれる。矛盾するものは、どちらを採るか確認する。別機能は、`docs/ideas.md` に残る | ✗ |
| U3 | 承認後 | 該当する節だけが変わる。`変更履歴` に 1 行。**状態が `変更あり (要再確定)` になる**。再確定の確認が出る | ✗ |
| U4 | U3 のまま `/add-feature` | 実装に進まず、再確定を促して止まる | ✗ |
| U5 | 実装済みの仕様で、期待値が変わるアイデアを取り込む | 影響を受けるテスト・実装を一覧にし、`/add-feature` を案内する。**コードとテストは、変えない** | ✗ |
| U6 | `/add-feature` の実装中に、思いつきを伝える | 実装せずに、`docs/ideas.md` に書き留めて、タスクを続ける | ✗ |
| U7 | アイデアが何もない状態で実行 | 「反映するアイデアがありません」と伝えて終わる | ✗ |

### 2-1. `cpp-test-first` (テストを先に書く)

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| F0 | **セットアップ:** Visual Studio で、空の MFC SDI ソリューション (`ThreeLayerSample`) を作る。そのフォルダで Claude Code を起動し、「データ層とロジック層の DLL と、それぞれのテストを作って」と依頼 | 案 (名前・名前空間) を示して了承を求める → `add_layer.py` で、`DataLayer` / `DataLayerTest`、`LogicLayer` / `LogicLayerTest` を作る → (必要なら) NuGet 復元を依頼 → **ビルドが通り、`PASSED`** (2 つのテスト exe の、ベースラインの各 1 件)。MFC アプリへの配線は、しない。**この F0 が、手書きの `.vcxproj` の、最初の実機の確認** | ✗ |
| F1 | 本体にまだない、簡単な関数 (例: 税込み計算) の追加を、「先にテストを書いて」と依頼 | テストケースの一覧を示す → スタブ (期待値と異なる値を返す) とテストを書く → `FAILED` を、アサーションの失敗 (`Expected` / `Which is`) で確認 → 報告して、確認を待つ。**本物のロジックは、書かない** | ✔ (2026-10-14 実機: ClaudeProject) |
| F2 | F1 の続きで、「実装まで続けて」と依頼 | 確認を待たずに、`build-test-loop` の手順で `PASSED` にする。**テストを変えない** | ✗ |
| F3 | 期待値が、スタブの値と同じになるテストを、混ぜる | `PASSED` (または、そのテストだけが通る) を、**異常として報告**し、実装に進まない | ✗ |
| F4 | 新しい `Test*.cpp` を作らせる (`.vcxproj` への追加が必要) | `.vcxproj` に追加している。追加漏れで、テストが走らないまま `PASSED` にならない | ✗ |
| F5 | 対象を、ダイアログのハンドラ (UI 層) にする | テストを書かずに止まり、ロジックの切り出し案を、示す | ✗ |
| F6 | バグ修正を依頼する | そのバグを再現するテストを、最初の1件にして、`FAILED` を確認してから、直す | ✗ |
| F7 | `permissions.ask` を設定した状態で、F1 | テストファイルの編集で確認が出る。拒否されたら、別の方法で、書かない | ✗ |
| F8 | **データ DLL** に、機能を追加する (例: `FileOrderRepository` に、id で検索する `FindById`) | `DataLayerTest` に書く (`LogicLayerTest` に書かない)。実ファイルは一時フォルダで、`TearDown` で削除する。`=== DataLayerTest.exe ===` の失敗で Red を確認する | ✗ |
| F9 | ロジック DLL に、データ層を使う機能を追加する | `LogicLayerTest` で、**フェイク**を使う (実の `FileOrderRepository` を使わない) | ✗ |
| F10 | F1 のスタブで、**公開マクロを付け忘れる** (誘導する) | `BUILD_FAILED` (`LNK2019`)。**Red とは呼ばず**、マクロを付けて、やり直す | ✗ |
| F11 | ロジックとデータの、両方にまたがる依頼 (例: 保存項目を増やし、その合計も出す) | **層ごとに、順番に**、Red → 確認 → Green を回す。まとめて Red にしない | ✗ |
| F12 | データ層のインターフェース (`IOrderRepository`) に、メソッドを追加する依頼 | 両方のテスト exe に影響が出る (フェイクと実装の両方)。**書いていない層の失敗を、「層をまたぐ影響」として報告する** | ✗ |
| F13 | ソリューションに、データのテスト exe がない状態で、データ層の機能を依頼 | テストを書かずに止まり、テスト exe の作成を、ユーザーに確認する。了承後に、規約どおりに作り、ベースラインが緑になってから Red に進む | ✗ |

**観察する点 (すべての Skill 経由のテスト共通):**
- `build_test_once.sh` を、探し回らずに、`run_in_background: true` (または `timeout` 付き) で実行している。
- 完了通知が来るまで、ファイルを読まない・コマンドを追加しない。
- テストファイル (`Test*.cpp`) を、許可なしに変更していない。
- 報告が短い (成功: 1〜2行)。経過の説明が、少ない。
- 実行後の `git status` / `git diff` で、意図しない変更がない。

### 2-2. `mfc-check` (MFC の静的検査。ウォッチャー不要)

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| K1 | 実プロジェクト (MFC の SDI 等) で、`python3 -I <Skill>/scripts/mfc_check.py <フォルダ>` を実行 | クラッシュしない。ウィザード生成の素のプロジェクトでは、error が出ない。出た指摘は、実際の不整合か、誤検出かを、記録する | ✔ (`cppsamples` の 4 プロジェクトと `DoubleBufferSample`。最初は、誤検出で error が 7 件出たが、4 種類を修正し、error 0 になった。残った指摘は、本物: `IDR_HELP_MENU` の名前付きリソース、`OnFilePrintPreview` の宣言の残骸、`IDD_LINESTYLE` の `&W` の重複) |
| K2 | `DoubleBufferSample` の `DrawingStylesDialog.h` で、`afx_msg void OnUpdatePenWidth();` を消して、実行 | MAP001 (error)。VS でビルドすると、コンパイルエラー (`C2039` など) になることも、確認する | 検出: ✔ (実プロジェクトで確認。2026-10-16)。ビルド: ✔ **失敗** — 最初のエラーは、チェッカーの指摘と**同じ行** (`DrawingStylesDialog.cpp(62,5)`): `C2039` ('OnUpdatePenWidth': 'LineStyleDialog' のメンバーではありません)、`C2065`、`C2737` (cpp(56,1): `_messageEntries` を初期化する必要がある。マップ全体が壊れた副次エラー)、`C2039` (cpp(228,23): 定義側)。**予想の `C2509` は外れ、定義側も `C2039` だった。** 実行時: なし (ビルドが通らない) |
| K3 | `Resource.h` の `IDC_PENWIDTH` (1002) を、`1001` (`IDC_PENSTYLE` と同じ) にして、実行 | RES003 (error)。ダイアログを開いて、線種と線幅の欄が、正しく動かないことを、確認する | 検出: ✔ (実プロジェクトで確認。2026-10-16)。実行時: ✔ **ASSERT** — `wincore.cpp` の 350 行目、`CWnd::Attach` の `ASSERT(FromHandlePermanent(hWndNew) == NULL)` (must not already be in permanent map)。ID が重複したため、`GetDlgItem` が、2 つの `DDX_Control` に、同じコントロールを返し、同じウィンドウを、2 つの `CWnd` に接続しようとした (予想どおり)。Release では、アサートなしで、2 つ目のメンバーが、別のコントロールを指すはず (未確認) |
| K4 | ロジックの DLL に、`#include <afxwin.h>` と `CWnd` の使用を足して、実行 (`DoubleBufferSample` にはライブラリがないので、`/new-solution` で作った層の構成 `NewClaudeProject` で行う) | LAY001 (error) と LAY002 (warning) | ✗ |
| K5 | Claude Code で、`mfc-check` を起動する依頼 (「ボタンが反応しない原因を調べて」) | Skill が起動し、`mfc_check.py` を実行し、error から直し、再実行して、error が減ることを確認する。warning は、自分が触った箇所だけ。3 回で、止まる | ✗ |
| K6 | ウィザード生成の `.rc` (UTF-16) を、Skill の手順 (Python のバイト列) で編集 | 文字化けせず、保存後も、UTF-16 (BOM 付き) のまま。VS で、リソースビューが開く | ✗ |
| K7 | `DrawingStylesDialog.cpp` の `LineStyleDialog::DoDataExchange` で、`DDX_Text(pDX, IDC_PENWIDTH, penWidth);` の次の行に、`DDX_Text(pDX, IDC_UNDERLINE2, penWidth);` を足して実行 (`IDC_UNDERLINE2` は、`Resource.h` にあるが、`IDD_LINESTYLE` にない。**`DDX_Control` で、接続済みのメンバー (`boldStyle` など) を使うと、MFC はコントロールを探さないので、何も起きない。必ず `DDX_Text` を使う**) | DLG001 (error)。Debug で起動すると、出力ウィンドウに `Error: no data exchange control with ID 0x03F3.` が出て、ASSERT になる | 検出: ✔ (`DoubleBufferSample` のコピーで確認。2026-10-16)。実行時の確認: ✗ (1 回目は、接続済みの `boldStyle` で行い、何も起きなかった。MFC の `DDX_Control` は、`m_hWnd == NULL` のときだけ `PrepareCtrl` を呼ぶため。`wincore2.cpp` で確認済み。実験の設計の誤りで、チェッカーの誤りではない) |
| K8 | `DrawingStylesDialog.h` の `CEdit penWidthEdit;` を `CListCtrl penWidthEdit;` にして実行 (`IDC_PENWIDTH` は `EDITTEXT`) | DLG003 (error)。コンパイルが通れば、Debug でダイアログを開き、**症状を観察して、ここに記録する** (アサートか、欄が動かないか。種類による)。`CEdit` 固有の呼び出しで、コンパイルエラーになる場合は、検出の確認だけで、よい | 検出: ✔ (実プロジェクトで確認。2026-10-16)。ビルド: ✔ 成功 (`penWidthEdit` は `CWnd` のメソッドしか使わないため)。実行時: **出力ウィンドウに、アサートも警告も出なかった。型の不一致は、型固有のメソッドを呼ぶまで、症状が出ない、潜在的な誤り** (`SubclassWindow` は、コントロールの種類を検査しない)。ダイアログの表示と線幅欄の操作は、未報告 |
| K9 | `LineStyleDialog::OnInitDialog` の `CDialogEx::OnInitDialog();` を、コメントアウトして実行 | DLG006 (warning)。Debug でダイアログを開くと、基底の `OnInitDialog` が `DoDataExchange` を呼ばないため、`DDX_Control` の接続が行われず、コントロールのメンバーが未接続のまま (最初の使用でアサート) になることを確認する | 検出: ✔ (実プロジェクトで確認。2026-10-16)。実行時: ✔ **ASSERT** — `afxwin2.inl` の 795 行目、`CComboBox::AddString` の `ASSERT(::IsWindow(m_hWnd))`。基底の `OnInitDialog` を呼ばないと、`DDX_Control` が実行されず、メンバーが未接続のまま使われる (予想どおり)。Release では、アサートなしで、コンボボックスが空になるはず (未確認) |
| K10 | VS のリソースエディタで、`IDD_LINESTYLE` にボタン (`IDC_BUTTON1`) を足し、ハンドラを付けずに、実行。次に、ボタンをダブルクリックして、ハンドラを足し、再実行 | 1 回目は DLG004 (warning)。ハンドラを足すと、消える。`.rc` (UTF-16) と `Resource.h` の更新は、VS に任せる | 検出: ✔ (K10-b: 実プロジェクトで確認。2026-10-16。ハンドラを足した後は、DLG004 も MAP の指摘も出ず、error 0 / warning 1)。K10-a (ハンドラなし) の、実プロジェクトでの出力は、未報告 (疑似プロジェクトと、コピーでは、確認済み)。**発見:** (1) VS のウィザードが足したハンドラは、保存するまで、ヘッダーに書かれない (保存前に実行すると MAP001 が出る。ディスクを読むため、正しい挙動)。(2) `.rc` は、VS の保存後も、UTF-16 (BOM) のまま。(3) VS が、`Resource.h` を `resource.h` に、名前を変えて保存した (git は、`M` と `??` の両方を表示する)。いずれも、`SKILL.md` に、注意として記載。実行時の確認: ✗ (ボタンを押しても、何も起きないことは、未報告) |
| K11 | `DrawingStylesDialog.cpp` の `LineStyleDialog::DoDataExchange` で、`DDX_Control(pDX, IDC_BRUSHCOLOR, brushColorPicker);` の `brushColorPicker` を `penColorPicker` に直して (コピー&ペーストの誤りの再現)、実行 | DLG010 (warning)。Debug で起動すると、**`OnInitDialog` が、未接続の `brushColorPicker` を、すぐ使う (`InitializeColorPicker(brushColorPicker, ...)`) ので、ASSERT になる可能性が高い** (予想)。出たら、ファイルと行を記録する。出なければ、ブラシ色のボタンが、機能しないことを、確認する | 検出: ✔ (実プロジェクトで確認。2026-10-17)。実行時: ✔ **アサートなしで、ダイアログが表示された** (予想の ASSERT は外れた)。**「塗りつぶしの設定」の「色(B)」だけが、`.rc` の素の `Picker` ボタンのまま** (他の 2 つの色指定は、`CMFCColorButton` の、見本とドロップダウンの付いた表示)。`brushColorPicker` が、未接続のまま、`InitializeColorPicker` に渡されたが、アサートにならなかった。**コピー&ペーストの誤りは、Debug でも、警告なしで、見た目が違うだけで済む。他の検査 (DLG001 / DLG003) では、見つからない** (スクリーンショットで確認) |

### 2-3. `wpf-check` (WPF の静的検査。ウォッチャー不要)

**v2.1.0 で追加。疑似プロジェクト (`tests/wpf_check_test.sh`) でのみ検証済み。実プロジェクトでの確認 (W1) が、最初に必要。** 準備: WPF の実プロジェクト (CommunityToolkit.Mvvm の ViewModel、`DataTemplate`、NuGet のテーマ、結合した辞書を含むもの。`WpfSample` など)。

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| W1 | **実プロジェクトで、`python3 -I <Skill>/scripts/wpf_check.py <フォルダ> --all` を実行** (まだ、何も変えない) | クラッシュしない。正常に動いているプロジェクトで、**error が出ない**。出た指摘は、実際の不整合か、誤検出かを、記録する。**誤検出の、コードと書き方を記録して、`wpf_check.py` と `tests/wpf_check_test.sh` に、反映する** (`mfc-check` では、実プロジェクトで、誤検出が 4 種類見つかった) | ✔ (2026-10-19 実機: WpfSample で error 0 / warning 0 / info 0。クラッシュなし。**ただし XAML 3 ファイル・バインディング 3 件の小さなサンプルで、誤検出の検証としては弱い。規模の大きい実プロジェクトで、再確認が望ましい**) |
| W2 | XAML の `{Binding Name}` を、`{Binding Nam}` に直して、実行。**実際に、アプリを起動して、Name の表示が、空になることを、確認する** | BND001 (error)、「もしかして: Name」、行は、その属性の行。起動して、出力ウィンドウに `BindingExpression path error: 'Nam' property not found` が出る | 検出: ✔ (疑似プロジェクト)。実行時: ✔ (2026-10-19 実機: BindingExpression path error: 'Nam' property not found) |
| W3 | ViewModel の `public string Name { get; set; }` を、`public string Name;` (フィールド) にして、実行 | BND002 (error)。起動して、表示が空になる (ビルドは、通る) | 検出: ✔ (疑似プロジェクト)。実行時: ✔ (2026-10-19 実機: BindingExpression path error (フィールドは標準のバインドで解決されない)) |
| W4 | 読み取り専用のプロパティ (`public string Full => ...;`) を、`<TextBox Text="{Binding Full}"/>` にバインドして、実行 | BND003 (**error** (v2.4.2 で、warning から引き上げ。実機で、起動時の例外を確認)。`TextBox.Text` は既定で TwoWay)。**起動時 (またはその画面を開いたとき) に、`InvalidOperationException` になる**ことを、確認する。`Mode=TwoWay` を明示しても、error | 検出: ✔ (疑似プロジェクト)。実行時: ✔ (2026-10-19 実機: 起動時に InvalidOperationException (読み取り専用プロパティへの TwoWay)。Window.Show() 内、App.OnStartup から) (**例外になるかの確認が、必要。ならない場合は、BND003 の重大度を、見直す**) |
| W5 | ViewModel の基底クラス (`ObservableObject`) を外して、`INotifyPropertyChanged` を実装しない通常のクラスにして、実行 | BND004 (warning)。起動して、プロパティの値を変えても、画面が更新されない | 検出: ✔ (疑似プロジェクト)。実行時: ✔ (2026-10-19 実機: 起動後、値を変えても画面が更新されず、エラーなし) |
| W6 | `MainWindow.xaml.cs` の `InitializeComponent();` を消して、実行 | UI001 (error)。ビルドは、通る。起動すると、ウィンドウが、空 (例外も出ない) | 検出: ✔ (疑似プロジェクト)。実行時: ✔ (2026-10-19 実機: 起動後、ウィンドウが空 (例外なし)) |
| W7 | XAML の `{StaticResource Xxx}` のキーを、存在しない綴りに直して、実行 | RES001 (error。外部のテーマの辞書があれば warning)。起動時に `XamlParseException` (`Cannot find resource named ...`) | 検出: ✔ (疑似プロジェクト)。実行時: ✔ (2026-10-19 実機: 起動時に XamlParseException) |
| W8 | 同じ辞書の中で、`StaticResource` で参照される項目を、**参照する項目より後ろに**移して、実行 | RES002 (warning)。**起動して、`XamlParseException` になるかを、確認し、ここに記録する** (ならないなら、RES002 の説明を、直す) | 検出: ✔ (疑似プロジェクト)。実行時: ✔ (2026-10-19 実機: 起動時に InvalidOperationException。RES002 の説明を訂正) |
| W9 | `App.xaml` の `StartupUri` と、結合した辞書の `Source` を、存在しないパスに直して、実行 | APP001 / RES005 (error)。起動時に例外 | 検出: ✔ (疑似プロジェクト)。実行時: ✔ (2026-10-19 実機: 起動時に XamlParseException (RES005 error)) |
| W10 | ロジックのプロジェクトに、`UseWPF` と `System.Windows` の参照を足して、実行 | LAY001 (error) | 検出: ✔ (疑似プロジェクト)。実プロジェクト: ✔ (2026-10-19 実機: LAY001 (error)。ビルドも NETSDK1136 で FAILED (二重の歯止め)) |
| W11 | Claude Code で、`wpf-check` を起動する依頼 (「画面に何も表示されない原因を調べて」) | Skill が起動し、`wpf_check.py` を実行し、error から直し、再実行して、error が減ることを確認する。warning は、自分が触った箇所だけ。3 回で、止まる。**検査を通すために、バインディングを消さない** | ✗ |
| W12 | 実プロジェクトで、`--json` を付けて実行し、`stats` を見る | `xaml` / `bindings` / `resources` の数が、プロジェクトの実態と、大きくずれていない (0 件なら、検査が、空振りしている) | ✔ (2026-10-19 実機: stats は xaml 3 / bindings 3 / resources 4。XAML 3 ファイル、`{Binding` 3 件と一致 (grep で照合)。空振りなし) |

### 2-4. WPF の生成とテスト先行 (`new-solution --type wpf` / `wpf-test-first`、`docs/DESIGN.md` 4.27)

**v2.3.0 で追加。Windows 側は、すべて未確認 (状況 ✗)。** 準備: ウォッチャーが起動できる WPF 用のフォルダ (`C:\work\WpfSample` など。**フォルダは、ユーザーが作る**)。ホスト側ツールと、Skill と、規約 (`install.sh`) を、配り直す。**WS6 → WS2 → WS3 の順に、確認する** (生成物が、ビルドできる前提の項目から)。
WSL で `python3 <new-solution>/scripts/new_solution.py "$PWD" --type wpf --layers data,logic,viewmodel --tests mstest` (または、Claude Code で `/new-solution`)。

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| WS6 | **既定の MSTest の版が、実在するか:** `add-package` で `nuget versions MSTest.TestFramework` / `MSTest.TestAdapter` / `Microsoft.NET.Test.Sdk` | `3.6.4` (MSTest) と `17.12.0` (Test.Sdk) が、一覧にある。**ない場合は、`add_project.py` の `MSTEST_VER` / `TESTSDK_VER` を、実在する版に直す** | ✔ (2026-10-18 17:19 実機。NuGet のキャッシュに `mstest.testframework\3.6.4` / `mstest.testadapter\3.6.4` / `microsoft.net.test.sdk\17.12.0` があり、ビルドの復元で取得できた = nuget.org に実在する。ユーザーの実行の成果物を、読み取りで確認。ほかに MSTest 3.9.3 / 4.0.2、Test.Sdk 18.x も、取得できる) |
| WS1 | 生成して、Visual Studio で `.slnx` を開く | 7 つのプロジェクトが、読み込める。スタートアッププロジェクトが、WPF アプリ。エラーの警告が出ない。`.editorconfig` が、読まれる | ✔ (2026-10-18 実機。ユーザーの報告: 期待どおり) |
| WS2 | ウォッチャーを起動 (Platform 省略) → `trigger_build.flag` | ヘッダーが `Solution : .NET`、`Build : Debug\|AnyCPU`。**`/p:Platform="Any CPU"` が、構成を持たない `.slnx` で通る** (`MSB4126` などの警告が出ない)。NuGet の復元 (MSTest) が走り、`SUCCESS`。**C# / XAML のコンパイルエラーがない** (あれば、生成のテンプレートの誤り。`add_project.py` を直す) | ✔ (2026-10-18 17:19 実機。`build_result.txt` = `SUCCESS`、`errors.log` / `warnings.log` は空、`build.log` は 0 エラー・0 警告。**生成した C# / XAML の、コンパイルに成功**。出力は `bin\Debug\net8.0` と `net8.0-windows` (AnyCPU)。構成を持たない `.slnx` で、`/p:Platform="Any CPU"` が通った。ヘッダーの表示 (`Solution : .NET`) は、画面で未確認) |
| WS3 | `trigger_test.flag` | `PASSED`。`.claude-logs\test-results\` に、3 つの trx。**実行されたテストは、8 件** (`DataLayer.Tests` 1、`LogicLayer.Tests` 1、`ViewModels.Tests` 6) | ✔ (2026-10-18 17:34 実機。`PASSED`。trx は `DataLayer.Tests` 1 件 / `LogicLayer.Tests` 1 件 / `ViewModels.Tests` 6 件、合計 8 件が、すべて合格 (成果物で確認)。`dotnet test --no-build` の出力先は `bin\Debug\net8.0`) |
| WS4 | Visual Studio で F5 | ウィンドウが開く。入力欄に名前を入れると、`こんにちは、○○ さん` に変わる。ボタンで、クリアされる。出力ウィンドウに、**バインディングのエラー (`BindingExpression path error`) が出ない** | ✔ (2026-10-18 実機。ユーザーの報告: 期待どおり) |
| WS17 | **composition root:** 生成直後の F5 (`StartupUri` なし。`App.OnStartup` が、`new MainWindow { DataContext = new MainViewModel() }` を `Show()` する) | ウィンドウが 1 つだけ開き、閉じるとアプリが終了する (`ShutdownMode`)。**`DataContext` が効いている** (WS4 と同じ操作が動く)。`MainWindow` のコードビハインドに `DataContext` がなくても、動く | ✔ (2026-10-18 実機。ユーザーの報告: 期待どおり。composition root (`App.OnStartup`) で、画面が開き、`DataContext` が効く) |
| WS18 | **共通リソース:** `Resources/Styles.xaml` を `App.xaml` で結合している | 起動時に `XamlParseException` が出ない (`DefaultControlMargin` / `PrimaryButtonStyle` が、解決される)。ボタンに余白と最小幅が、効いている。`Styles.xaml` の `DefaultControlMargin` のキーを、わざと変えると、起動時に `Cannot find resource named 'DefaultControlMargin'` で落ちる (`wpf-check` の RES001 と一致) | ✔ (2026-10-18 実機。ユーザーの報告: 期待どおり。`Resources/Styles.xaml` の結合で、起動時に例外が出ない) |
| WS19 | **規約の構成 (3.2) の名前:** `--layers data:Std.Domain,logic:Std.Application,viewmodel:Std.Presentation` で生成 → ビルドとテスト | ビルドが通り、`PASSED`。**`.` を含む名前でも、`Std.Domain.Tests` などが検出される** (名前が `.Tests` で終わる)。`xmlns:vm="clr-namespace:Std.Presentation;assembly=Std.Presentation"` で、画面が動く | ✔ (2026-10-20 実機、修正版で `WpfStd2` をやり直し: `using Std.Presentation;` と `clr-namespace:Std.Presentation;assembly=Std.Presentation` が正しく出る。ビルド `SUCCESS` (警告 0)、`PASSED` (8 件: `Std.Domain.Tests` 1 / `Std.Application.Tests` 1 / `Std.Presentation.Tests` 6)。`wpf-check` 0 件。F5 で、挨拶が変わる (ユーザー確認)。`.` を含む名前でも、`.Tests` が検出された) |
| WS20 | **MVVM Toolkit への切り替え (規約 8.2):** `add-package` で `CommunityToolkit.Mvvm` を足し、`ObservableObject` / `RelayCommand` を、置き換える | ビルドが通る。`wpf-check` の指摘が出ない (`[ObservableProperty]` / `[RelayCommand]` を知っている)。**自前の `ObservableObject` を消さないと、名前が衝突するかを、記録する** | ✔ (2026-10-20 実機、`WpfToolkit`: 8.4.2 を追加。自前の基底クラスを残したままでは、パッケージの追加だけなら `SUCCESS`、`[ObservableProperty]` に書き換えると `MVVMTK0019` / `CS0103` で失敗 (**名前が衝突する**)。自前の `ObservableObject.cs` を消して `PASSED` (8 件)。`wpf-check --all` は 0 件 (誤検出なし)) |
| WS5 | 生成物に `wpf-check --all` | 指摘 0 件 (疑似では確認済み)。**実プロジェクトの誤検出の確認 (2-3 の W1) も、兼ねる** | ✔ (2026-10-19 実機。コンソールの Claude の報告: `error 0 / warning 0 / info 0`) |
| WS7 | WS2 のビルドの警告 (`warnings.log`) | **警告の件数と内容を記録する** (`CS8618` などの、null 許容の警告が出ないこと)。出れば、テンプレートを直す | ✔ (2026-10-18 17:19 実機。0 個の警告 (`warnings.log` は空)) |
| WS8 | **別の TFM (`net10.0`) での生成とビルド・テスト:** (1) ホストで `dotnet --list-sdks` を実行し、**SDK 10 が入っていること**を確認する (無ければ、この項目は「SDK なし」で保留)。(2) WSL で、別のフォルダ (例: `WpfSample10`) に、`python3 -I <Skill>/scripts/new_solution.py <フォルダ> --type wpf --layers data,logic,viewmodel --tests mstest --tfm net10.0` (引数は SKILL.md の書式のとおり) で生成する。(3) そのフォルダで、ウォッチャーを起動し、`trigger_build.flag` → `trigger_test.flag`。(4) 生成物の `*.csproj` の `TargetFramework` と、`CLAUDE.md` の表を確認する | 生成: アプリが `net10.0-windows`、ライブラリとテストが `net10.0` (`CLAUDE.md` の表も同じ)。**ビルドが `SUCCESS` で、C# / XAML のコンパイルエラー・警告 (`warnings.log`) が 0** (テンプレートが、net8.0 前提の記述 (古い API、`LangVersion` など) を含んでいれば、ここで出る)。テスト: `PASSED`、**8 件** (WS3 と同じ内訳)、trx の出力先は `bin\Debug\net10.0`。`wpf-check --all` は 0 件。**既定の MSTest / Test SDK の版が、net10.0 で動くか**を、記録する (動かなければ `--mstest-version` / `--testsdk-version` の既定を見直す)。F5 で起動して、WS4 と同じ操作が動く (任意) | ✗ |
| WS9 | `--layers data,logic,viewmodel --tests none` で生成し、ビルド → `--tests mstest` (後付け) → ビルドとテスト | 後付けで、3 つのテストプロジェクトが追加され、`.slnx` が壊れず、`PASSED`。`CLAUDE.md` の `テスト:` が `あり (MSTest)` | ✔ (2026-10-20 実機、`WpfRetro`: 生成 (`--tests none`) → ビルド `SUCCESS` → `--tests mstest` で後付け (3 つのテストプロジェクト、`CLAUDE.md` 更新) → **初回は `ENV_ERROR` (`no tests found`)。ウォッチャーを再起動すると `PASSED` (8 件)**。原因: ウォッチャーがプロジェクトの一覧を、起動時に 1 回だけ読んでいた (WS8 / WS9 などで 4 回再現)。v2.4.2 で、トリガーごとに読み直すよう修正 → WS21 (2026-10-20 実機) で、再起動なしで通ることを確認済み) |
| WS21 | **再起動なしの後付け (v2.4.2 の修正の確認):** 再配置したウォッチャーを起動したまま、`--tests none` で生成したソリューション (ウォッチャーは、そのフォルダで起動) に、`new_solution.py <フォルダ> --tests mstest` で、テストを後付けし、`build_test_once.sh` | **ウォッチャーを再起動しなくても `PASSED`** (`no tests found` にならない)。`ホストの再配置 (~/src/copy-host-tools.sh)` が前提 | ✔ (2026-10-20 実機、`WpfLate`: 更新版のウォッチャーを 1 回だけ起動 → `--tests none` で生成、ビルド `SUCCESS` → `--tests mstest` で後付け (**再起動なし**) → `PASSED` (8 件)。`no tests found` は出ない。4 回再現した不具合は、解消) |
| WS10 | Visual Studio で作った **`.sln`** (WPF アプリ + クラスライブラリ) に、`add_project.py` で、ライブラリ + テストを追加 → VS で開く | プロジェクトが、ソリューションエクスプローラーに出る。構成マネージャーで、Any CPU に対応づいている。ビルドとテストが通る | 保留 (VS で、WPF アプリ + クラスライブラリの `.sln` を作ってからでないと、実施できない) |
| WS11 | **`wpf-test-first` を、端から端まで:** 仕様 (例: 名前の前後の空白を、取り除いて、挨拶する) を、`/add-feature` か直接の依頼で | Skill が起動し、テストケースの一覧 → スタブ (`Greeting` が、固定値) → テスト → **`FAILED` (`Assert.AreEqual failed. Expected:<...>. Actual:<...>.`)、例外でなく** → 確認 → 実装 → `PASSED`。要約が、`WpfSample.ViewModels.MainViewModelTests.…` の形で出る | ✔ (2026-10-20 実機、`WpfSample` で実施 (`WpfTdd` ではない)。**`wpf-test-first` が起動** (「テスト先行で進めて」の依頼から、Claude が Skill を選んだ)。**テストケースの一覧を提示** (トリム 2 ケース + 既存は変更なし + スコープの確認)。**Red: `FAILED`、`[ran 25: passed 23 / failed 2 / skipped 0]`、失敗は `Assert.AreEqual に失敗しました。<期待> が必要ですが、<実際> が指定されました` (例外ではない)** = 正しい Red。スタブは不要 (既存の実装が、仕様を満たさない仮の実装として働いた)。実装後 `PASSED` (25 件。**`PASSED` の出力は 1 行目だけで、件数・テスト名は出ない** (要約は、失敗のときだけ))。途中で `WATCHER_NOT_RUNNING` と、ファイルロックによる一時的な `ENV_ERROR` があり、再実行で解消 (実際の Red ではない)) |
| WS12 | **正しくない Red:** スタブを `NotImplementedException` にして、同じことをする | 例外で落ちるので、Skill が、「正しい Red ではない」と判断する (条件 2) | ✔ (2026-10-20 実機、`WpfSample`: 依頼に `NotImplementedException` のスタブを指定 → Skill は**実行する前に断った** (規約: 例外で落ちるので正しい Red にならない) うえで `AskUserQuestion` で確認し、ユーザーが「規約どおり、値を返すスタブ」を選択。`NotImplementedException` は、一度も作成・実行していない。**Red: `FAILED`、`[ran 27: passed 25 / failed 2 / skipped 0]`、失敗は `Assert.AreEqual に失敗しました` (わざと 19 文字で切り詰めるスタブ。例外ではない)。境界値 (ちょうど 20 文字 / 20 文字超) の 2 ケース**。期待は「実行して例外で落ち、条件 2 で気づく」だったが、**事前に防いだ** (より良い動き)) |
| WS13 | ViewModel に `MessageBox.Show` を足して、ライブラリをビルド | **ビルドエラー (`CS0103` / `CS0234`)**。層が、型で守られている。ライブラリに `UseWPF` を足すと、`wpf-check` の LAY001 が出る | ✔ (2026-10-20 実機: `MessageBox.Show` を、`using` なしで足す → `CS0103` (型で守られている)。`using System.Windows;` を足しても **`CS0103` のまま** (期待の `CS0234` ではない: `System.Windows` の名前空間自体は、`UseWPF` なしでも、BCL の型 (`System.Windows.Input.ICommand` など) があるため存在する。`MessageBox` という型だけが、見つからない)。`UseWPF` を足すと、ビルドは `NETSDK1136` で `FAILED`。**`wpf-check` の `LAY001` は、ViewModel 層の `UseWPF` を検査していなかった** (ロジック・データ層だけ) → v2.4.2 で、ViewModel 層も対象にした (テスト追加)) |
| WS14 | `dotnet format --verify-no-changes` を、生成物に (ホストで) | 差分が出ない。**出れば、`.editorconfig` と生成コードの、どちらかを直す** (書式の規約と、生成物が、ずれている) | ✗ |
| WS15 | 規約が読み込まれること: 新しいセッションで、`.cs` を開く | `~/.claude/rules/wpf-csharp.md` が、読み込まれる (`install.sh` で配られている) | ✗ |
| WS16 | Claude Code で、`/new-solution --type wpf ...` を、引数なしと、`--spec` つきで | 質問が出る (`--tests` は、必ず)。dry-run を見せて、了承を得てから、作る。`--spec` は、`メインの種類: wpf` / `テスト: mstest` / `層: data,logic,viewmodel` を、読み取る | ✗ |

## 3. 疑似ウォッチャー (Windows 不要)

`tests/fake_watcher_test.sh` が、`build_test_once.sh` の結果の分岐を、ファイルを書くだけの偽のウォッチャーで検証する。
Skill のスクリプトを変えたときは、Windows に配る前に、これを実行する。

`tests/gtest_once_test.sh` が、`gtest_once.sh` (GoogleTest の取得) の結果の分岐を、同様に検証する。

`tests/fake_watcher_test.sh` は、構造化された結果 (`.claude-logs/test-results/` の XML + trx) がある `FAILED` の経路と、前回の結果が消されることも検証する。**ただし、Windows 側の `watch_and_build.ps1` / `build-windows.cmd` は、これでは検証できない** (1-5 の U 系を、実機で)。

`tests/wpf_check_test.sh` が、`wpf_check.py` を、疑似の WPF プロジェクトで検証する (72 項目。**WPF プログラミング規約の項目 (DI001 / ASY001 / ASY002 / EXC001 / EXC002 / NAM001 / UI003 / LAY002 の拡張) と、標準の層 (Presentation / Application / Domain / Infrastructure) を含む。****正常なプロジェクト (CommunityToolkit.Mvvm・`DataTemplate`・外部の辞書・結合した辞書・`d:DataContext`) に指摘が出ないこと**、BND / CMD / RES / CNV / UI / APP / LAY / XAML の各コードが、不具合を 1 か所ずつ入れたときに出ること、外部の基底クラスで検査しないこと、`d:DataContext` だけなら warning、コードから足すキー、`this(...)` で委譲するコンストラクター、BOM + CRLF の行番号、出力の上限、終了コード、読み取り専用。実機の WPF プロジェクトでは、2-3 の W 系で確認する。

`tests/add_project_test.sh` (24 項目) が、`add_project.py` を、疑似ソリューション (`.slnx` と、Visual Studio 形式の `.sln`) で検証する (追加するファイル、名前空間、依存、BOM と CRLF、`.sln` の構成の対応付け、既存の保護 (rc=3)、`--tests-only`、ひな形と生成の定数の一致)。`tests/new_solution_wpf_test.sh` (59 項目) が、`new_solution.py` の WPF を検証する (4 つの形の生成、依存の連鎖、`CLAUDE.md` の記録、引数の検証、テストの後付け、`--spec`、**生成物が `wpf-check` で指摘 0 件であること**)。**生成した C# は、ここでは、コンパイルできない** (2-4 の WS2 を、実機で)。

`tests/package_once_test.sh` (41 項目) が、`package_once.sh` を、疑似ウォッチャーで検証する (操作の形の検証: コマンド注入・`..`・絶対パス・`-` 始まりのバージョンなど 17 種類を、フラグを置く前に拒否すること、正しい形の受理、結果の分岐 (`OK` / `FAILED` / `ENV_ERROR` / `TIMEOUT` / `WATCHER_NOT_RUNNING`)、古い結果の除去、`--file`、出力の上限)。`tests/cpp_pkg_test.sh` (35 項目) が、`cpp_pkg.py` を、疑似の `.vcxproj` で検証する (`setup` の冪等、BOM と CRLF の保持、gtest を除くこと、`add` / `remove` / `list`、`include-dir` の全構成への追加、`record-fetch`)。**ホスト側 (`Invoke-PackageOps`、vcpkg との連携) は、これでは検証できない** (1-6 の P 系を、実機で)。

`tests/summarize_build_log_test.sh` が、`summarize_build_log.py` (ビルドエラーの要約) を検証する (11 項目)。同じエラーの集約と件数、最初に出た順、重複する場所の除去、BOM / CR / `N>` の除去、JSON、100 件でも最大 40 行、解釈できないログは rc=3 で何も出さない (生ログへの切り替え)、2 つの Skill のコピーが同一。実機の MSBuild のログでは、S11 / S12 で確認する。

`tests/summarize_test_log_test.sh` が、`summarize_test_log.py` (テスト失敗の要約) を検証する (34 項目)。同じメッセージの集約、場所、パラメータ化テスト名、Linux 形式、`listed below` の再掲の除外、上限と JSON、クラッシュ時のフォールバック (rc=3)。**加えて、構造化された結果:** GoogleTest の XML と MSTest の trx (`tests/fixtures/`) を、共通の形式に変換して、フレームワークをまたいで集約すること、スキップを失敗に数えないこと、データ行つきのテスト名、日本語 OS のスタックトレース、壊れた XML、クラッシュの報告の併記、JSON (schema 2 と、従来のキー)。実機の GoogleTest の出力では、S15〜S17 で確認する。

警告の項目 (`--severity warning` / `--root` / `--oneline`) と、.NET の診断コード (`CS` / `MC` / `XDG` / `NETSDK` / `NU` / `MSTEST`) は、`tests/summarize_build_log_test.sh` (計 26 項目) と、`tests/fake_watcher_test.sh` の「PASSED with warnings」が検証する。実機の `warnings.log` (フルパス) では、S19〜S22 で確認する。

期待する結果 (rc): `PASSED` 0 / `FAILED` 1 (失敗テスト名が先頭) / `BUILD_FAILED` 6 / ビルド環境エラー `ENV_ERROR` 4 /
`TEST_TIMEOUT` 7 / テスト環境エラー `ENV_ERROR` 4 / 失敗が多数 1 (名前 50 件 + `and N more`、詳細は上限あり) /
古いマーカーが消される 0 / `WATCHER_NOT_RUNNING` 3 / `TIMEOUT` 5 / `BAD_ARGS` 2。

## 4. 変更したときの、最低限の確認

| 変更したもの | 最低限、やること |
|---|---|
| `add_project.py` / `new_solution.py` の WPF の部分 / `rules/wpf-csharp.md` / `templates/dotnet/` | `tools/check-formats.sh`、`tests/add_project_test.sh`、`tests/new_solution_wpf_test.sh`。**テンプレート (C# / XAML) を変えたら、生成物を、`wpf-check` にかけ、2-4 の WS2 / WS3 を、実機で。** `.editorconfig` を変えたら、ひな形と定数の両方 |
| `package_once.sh` / `cpp_pkg.py` | `tools/check-formats.sh`、`tests/package_once_test.sh`、`tests/cpp_pkg_test.sh`。操作を足したら、WSL 側と、ウォッチャーの、**両方**の検証規則を、同じにして、`package_once_test.sh` に、拒否のケースを足す |
| `watch_and_build.ps1` のパッケージの操作 | 1-6 の P1 / P3 / P10 / P11 / P16 / P20 を、実機で |
| `wpf_check.py` | `tools/check-formats.sh`、`tests/wpf_check_test.sh`。検査を足したら、疑似プロジェクトに、そのケースを足す (正常なプロジェクトに、指摘が出ないことも)。実プロジェクトで、誤検出が増えていないかも、見る (2-3 の W1) |
| `mfc_check.py` | `tools/check-formats.sh`、`tests/mfc_check_test.sh`。検査を足したら、疑似プロジェクトに、そのケースを足す。実プロジェクトで、誤検出が増えていないかも、見る (2-2 の K1) |
| `build_once.sh` / `build_test_once.sh` | `tools/check-formats.sh`、`tests/fake_watcher_test.sh` |
| `summarize_build_log.py` の警告 (`--severity warning`) / `show_warnings_line` | `tests/summarize_build_log_test.sh`、`tests/fake_watcher_test.sh`。実機の `warnings.log` で、2 の S19〜S22 |
| `summarize_test_log.py` | `tests/summarize_test_log_test.sh`、`tests/fake_watcher_test.sh`。出力の形式を変えたら、2 の S15〜S17 を、実機で (`SKILL.md` の読み方も)。XML / trx の読み方を変えたら、1-5 の U8 (実物のファイルで) |
| `summarize_build_log.py` | 2 つの Skill のコピーを、同一にして、`tests/summarize_build_log_test.sh`、`tests/fake_watcher_test.sh`。出力の形式を変えたら、2 の S11 / S12 を、実機で (`SKILL.md` の読み方も) |
| `gtest_once.sh` / `watch_and_build.ps1` の gtest 部分 | `tools/check-formats.sh`、`tests/gtest_once_test.sh`。ps1 は、1-2b の G1 / G2 / G4 を、実機で |
| `new_solution.py` | `tools/check-formats.sh`、`tests/new_solution_test.sh`。生成するプロジェクトを変えたら、2-0c の N1〜N3 を、実機で |
| `add_layer.py` | `tools/check-formats.sh`、`tests/add_layer_test.sh`。生成する `.vcxproj` を変えたら、2-1 の F0 を、実機で |
| `watch_and_build.ps1` | 1-2 の T1 / T2 / T4 を、実機で。二重起動の防止を変えたときは 1-4 の M1 / M2 も。**.NET / 統合の部分を変えたら、1-5 の U1〜U15** |
| `build-windows.cmd` / `run_watcher.cmd` | 1-1 の H1 と、R1 を、実機で。CP932 のまま保存されているか (`check-formats.sh`)。`Features` の解釈を変えたら、1-5 の U1 (C++ の回帰) と U3 |
| `SKILL.md` | 新しいセッションで、2 の S1 と、変更に関係する項目 (例: 方針を変えたなら S4)。`cpp-test-first` なら、2-1 の F1 / F3 |
| 契約 (ファイル名・結果の値・終了コード) | ホスト側ツールと Skill の両方、1-2 と 2 の全項目 |
