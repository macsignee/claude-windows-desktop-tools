# 残りの実機確認 (手順と期待値)

2026-10-19 作成。`docs/TEST-PLAN.md` の、未完了の項目 (U6c / U7 / U8〜U16、P1〜P7 / P14〜P21、WS8〜WS16 / WS19 / WS20) の、**手順・期待値・実施者**を、ここに集めた。
各行の元の記述は、`docs/TEST-PLAN.md` にある (結果は、そちらに記録する)。**コンソールの Claude の記録 (`wpfsample/docs/TEST-PLAN.md`) の「内容未記録」の行は、この表で置き換える。**

**実施者:** 「Claude」= コンソールの Claude が、ウォッチャーのフラグで実行できる。「ユーザー」= ホストの操作 (ウォッチャーの再起動、PowerShell、VS、ネットワークの切断) が要る。
**共通の注意:** 失敗の出力は、そのまま報告 (推測で直さない)。ファイルを変える項目は、先にバックアップを取る (`WpfSample` は git 管理外)。commit / push はしない。

## 1. すぐ実施できるもの (Claude)

| ID | 内容 | 手順 | 期待値 | 状況 |
|---|---|---|---|---|
| P1 | nuget の参照系 | `package_once.sh "$PWD" "nuget versions Newtonsoft.Json" "nuget search json"` | `OK`。バージョンの一覧 (stable 10 件 + prerelease)、検索結果 (ID・version・downloads・verified・authors)。`package_result.txt` が、`package_output.txt` より後に書かれる | ✔ (2026-10-20 実機: 86 バージョン (stable 10 件)、検索結果あり。`package_result.txt` が `package_output.txt` の約 17ms 後) |
| P2 | 存在しない名前 | `"nuget versions No.Such.Pkg.Xyz"` | `FAILED`。`package_error.log` に `not found (HTTP 404)`。先頭が `[ENVIRONMENT ERROR` でない | ✔ (2026-10-20 実機: `FAILED`、`not found (HTTP 404). Check the spelling with 'nuget search'.`) |
| P3 | 追加 | `"nuget add WpfSample/WpfSample.csproj CommunityToolkit.Mvvm 8.4.0"` → `build_once.sh` | `OK`、`added CommunityToolkit.Mvvm 8.4.0`。`.csproj` に `PackageReference`。ビルド `SUCCESS` | ✔ (2026-10-20 実機: `OK`、`PackageReference` が増え、ビルド `SUCCESS`) |
| P4 | 中央管理 | `Directory.Packages.props` (`ManagePackageVersionsCentrally`) を持つソリューションで、同様に `nuget add` | `OK`。バージョンは `Directory.Packages.props` に入り、`(Directory.Packages.props)` と出る (使い捨てのコピーで行う) | ✗ |
| P5 | 存在しないパッケージの追加 | `"nuget add WpfSample/WpfSample.csproj Nope.Pkg.Xyz"` | `FAILED` (`NU1101`)。環境エラーにならない | ✔ (2026-10-20 実機: `FAILED` (`パッケージ 'Nope.Pkg.Xyz' に使用できるバージョンがありません`)、`.csproj` は不変。**`NU1101` のコードは、出力に出ない** (メッセージは、NU1101 と同じ内容。期待値の「(`NU1101`)」は、「版がない旨のメッセージ」と読み替える)) |
| P7 | 削除 | P3 のあと `"nuget remove WpfSample/WpfSample.csproj CommunityToolkit.Mvvm"` → ビルド | `OK`。`PackageReference` が消え、ビルド `SUCCESS` | ✔ (2026-10-20 実機: `OK`、`.csproj` が元と完全一致、ビルド `SUCCESS`) |
| P16 | ソースの取り込み (fetch) | C++ のソリューションで `"fetch nlohmann/json v3.11.3 json single_include"`。もう一度、同じ操作 | `OK`。`ThirdParty\json\nlohmann\json.hpp`、`VERSION.txt` = `nlohmann/json@v3.11.3#single_include`、LICENSE。2 回目は `already present` | ✔ (2026-10-19 実機、`wpfsample` で実施: `OK`。`ThirdParty/json/nlohmann/json.hpp` と `json_fwd.hpp`、`VERSION.txt` = `nlohmann/json@v3.11.3#single_include`、`LICENSE.MIT`。2 回目は `already present`。**`fetch` は C++ 限定ではなく、.NET / WPF のソリューションでも動く**) |
| P17 | include パスの追加 | P16 のあと `cpp_pkg.py include-dir <vcxproj> '$(SolutionDir)ThirdParty\json'` → `#include <nlohmann/json.hpp>` でビルド | `SUCCESS`。VS の「追加のインクルード ディレクトリ」にパスがある (ユーザーが確認) | ✔ (2026-10-20 実機、`MfcSdiLayers`: `fetch` → `include-dir` (2 構成とも反映) → `#include <nlohmann/json.hpp>` でビルド `SUCCESS`。戻して差分なし。**VS を開いたままだと、プロパティページに、すぐには反映されない** (VS の再読み込みが要る。SKILL.md に注記)) |
| P18 | fetch の失敗 | `"fetch nlohmann/json no-such-tag json"`、`"fetch no-such-owner/no-such-repo v1 x"` | `ENV_ERROR` (`git clone` と zip の両方の失敗)。タグの誤りとネットワークの問題は区別できない (既知の限界) | ✔ (2026-10-19 実機: 両方とも `ENV_ERROR` (`git clone failed` → zip も失敗)。タグの誤りとネットワークの問題は区別できない (既知の限界)) |
| P19 | 取り込みの再現 | `cpp_pkg.py record-fetch ...` → 別フォルダにクローン → `package_once.sh --file ThirdParty.manifest` | `ThirdParty\json\` が再現される | ✔ (2026-10-20 実機、`MfcSdiLayers`: `record-fetch` → `ThirdParty/json` を退避 → `--file ThirdParty.manifest` で再作成。`diff -r` 差分なし) |
| P20 | 注入の拒否 | フラグを手で書く: `nuget add WpfSample/WpfSample.csproj Foo;calc`、`vcpkg install --triplet evil`、`fetch a/b v1 ..\x` | すべて `FAILED` (`invalid ...` / `usage: ...`)。コマンドは実行されない | ✔ (2026-10-20 実機: 手書きのフラグ `vcpkg install --triplet evil` → `FAILED` (`ERROR: usage: vcpkg install`)。`package_output.txt` に vcpkg の出力なし = 実行されない。nuget / fetch の拒否は、2026-10-19 に確認済み) |
| P21 | Skill の起動 | 「CommunityToolkit.Mvvm を追加して」「fmt を使いたい」と依頼 | `add-package` が起動し、`versions` / `search` → `add` → ビルドの順。名前を推測しない。確認 (`ask`) が出る。報告に、バージョンと変更したファイル | ✔ (2026-10-20 実機、後半: 「fmt を使いたい」で Skill の手順どおり (search → add → install → build)、`SUCCESS`。`FMT_UNICODE=0` が自動で入り、`remove` で消えた。bak との差分は、意図した 2 件のみ。前半の NuGet は 2026-10-19 に確認済み) |
| U11 | テスト 0 件 | `[TestMethod]` をすべて外して `build_test_once.sh` (後で戻す) | `ENV_ERROR` (`no tests were executed`)。`PASSED` にならない | ✔ (2026-10-20 実機: `ViewModels.Tests` だけ 0 件にして `build_test_once.sh` → **全体が `ENV_ERROR`** (`ViewModels.Tests.dll で使用できるテストはありません`)。ほかのテストプロジェクトが成功していても、0 件のプロジェクトが 1 つあれば、止まる (安全側)。**発見: 前回の `test_summary.json` が残った** → v2.4.2 で、実行の最初に消すよう修正。**元に戻すときは、`cp -p` を使わない** (古い日時で、MSBuild が再ビルドしない。`touch` が要る)) |
| U7 | 現行版での、失敗の実行 | `Assert.AreEqual` を、わざと失敗させて `build_test_once.sh` (`~/.claude/skills/build-test-loop/scripts/` の現行版だけ) | `FAILED`。`test_error.log` に `FAILED <クラス名.メソッド名>`、`at ...cs:line N`。要約に `[ran N: ...]`、同じメッセージの `xN`、`test_summary.json` | △ (現行版での実機の失敗は、未実施) |
| WS15 | 規約の読み込み | 新しいセッションで `.cs` を開き、`~/.claude/rules/wpf-csharp.md` が読み込まれているかを、Claude に答えさせる (`install.sh` で配られている) | 規約の内容 (例: 命名、DI) に、沿った回答になる。ファイルが無ければ、`install.sh --rules-only` | ✗ |
| WS9 | 後付けのテスト | 使い捨てのフォルダで `--layers data,logic,viewmodel --tests none` → ビルド → `--tests mstest` で後付け → ビルドとテスト | 3 つのテストプロジェクトが追加され、`.slnx` が壊れず `PASSED`。`CLAUDE.md` の `テスト:` が `あり (MSTest)` | ✔ (2026-10-20 実機、`WpfRetro`: 生成 (`--tests none`) → ビルド `SUCCESS` → `--tests mstest` で後付け (3 つのテストプロジェクト、`CLAUDE.md` 更新) → **初回は `ENV_ERROR` (`no tests found`)。ウォッチャーを再起動すると `PASSED` (8 件)**。原因: ウォッチャーがプロジェクトの一覧を、起動時に 1 回だけ読んでいた (WS8 / WS9 などで 4 回再現)。v2.4.2 で、トリガーごとに読み直すよう修正 → **WS21 で、再起動なしで通ることを確認する**) |
| WS19 | 規約の構成 (3.2) の名前 | `--layers data:Std.Domain,logic:Std.Application,viewmodel:Std.Presentation` で生成 → ビルドとテスト | `PASSED`。`.` を含む名前でも `Std.Domain.Tests` などが検出される。`xmlns:vm="clr-namespace:Std.Presentation;assembly=Std.Presentation"` で、画面が動く (F5 はユーザー) | ✔ (2026-10-20 実機、修正版で `WpfStd2` をやり直し: `using Std.Presentation;` と `clr-namespace:Std.Presentation;assembly=Std.Presentation` が正しく出る。ビルド `SUCCESS` (警告 0)、`PASSED` (8 件: `Std.Domain.Tests` 1 / `Std.Application.Tests` 1 / `Std.Presentation.Tests` 6)。`wpf-check` 0 件。F5 で、挨拶が変わる (ユーザー確認)。`.` を含む名前でも、`.Tests` が検出された) |
| WS20 | MVVM Toolkit への切り替え | `add-package` で `CommunityToolkit.Mvvm` を足し、`ObservableObject` / `RelayCommand` を置き換える (使い捨てのコピー) | ビルドが通る。`wpf-check` の指摘が出ない (`[ObservableProperty]` / `[RelayCommand]` を知っている)。**自前の `ObservableObject` を消さないと名前が衝突するか**を記録 | ✔ (2026-10-20 実機、`WpfToolkit`: 8.4.2 を追加。自前の基底クラスを残したままでは、パッケージの追加だけなら `SUCCESS`、`[ObservableProperty]` に書き換えると `MVVMTK0019` / `CS0103` で失敗 (**名前が衝突する**)。自前の `ObservableObject.cs` を消して `PASSED` (8 件)。`wpf-check --all` は 0 件 (誤検出なし)) |

## 2. ホストの操作が要るもの (ユーザー)

| ID | 内容 | 手順 | 期待値 | 状況 |
|---|---|---|---|---|
| U6c | 環境変数 `Platform` の漏れ | PowerShell で `$env:Platform = "auto"` を設定してから、ウォッチャーを起動し、`trigger_test.flag` | テストの DLL が見つかる (`bin\Debug\net8.0\`)。`test.log` に `bin\auto` が出ない | △ (わざと設定した再現は、未実施) |
| U8 | 実機の gtest XML / 失敗の trx | C++ のテストの結果の XML と、日本語 OS の失敗の trx (`.claude-logs\test-results\`) を、WSL に持ってきて `summarize_test_log.py --results-dir` に渡す | 要約が出る。形が違えば、`summarize_test_log.py` と `tests/fixtures/` を直す | △ (MSTest の成功の trx は確認済み。gtest XML と、失敗の trx は未確認) |
| U9 | 混在のテスト | C++ と .NET の両方に失敗を入れて `trigger_test.flag` | 両方のテストが実行される。要約が 1 つで `sources` に `gtest` と `mstest`。`[ran N: ...]` が両方の合計 | ✗ |
| U10 | 混在のヘッダー | 混在のソリューションでウォッチャーを起動 | `Solution : C++ + .NET (build features: cpp,restore)`、`Build : Debug\|x64`。ビルドが通る | ✗ |
| U12 | 存在しない dotnet | `-DotnetExe NoSuchDotnet` で起動し、`WpfSample` で `trigger_test.flag` | `ENV_ERROR` (`'NoSuchDotnet' was not found`) | ✗ (2026-10-14 の `ClaudeProject` の表では ✔ だが、この WPF 版は未実施) |
| U13 | 存在しない SDK | `global.json` に存在しない SDK を指定して `trigger_build.flag` (後で戻す) | `FAILED`。`build_error.log` の先頭が `[ENVIRONMENT ERROR` (`NETSDK1141`) | ✗ |
| U14 | C++ ワークロードなしの VS | MSBuild だけの環境で `WpfSample` の `trigger_build.flag` | ビルドが通る (`cpp` を要求しない) | ✗ (この環境がなければ、△ のまま) |
| U15 | x64 出力の WPF | `bin\x64\Debug` に出す構成で `-DotnetTestArgs "-p:Platform=x64"`。指定なしの場合も確認 | 指定ありはテストが走る。指定なしは見つからず `FAILED` (`no test results ...`) | ✗ |
| U16 | Skill の競合 | 新しいセッションで `auto-build` / `build-test-loop` を使う (旧名の `cpp-*` が残っていないこと) | description が競合せず、WPF でも C++ でも、同じ手順で動く | ✗ |
| P6 | ネットワークなし | ネットワークを切る (または、プロキシを誤設定) して `nuget add ...` と `nuget versions ...` | `ENV_ERROR` (`NU1301` / `could not reach nuget.org`)。先頭が `[ENVIRONMENT ERROR` | ✗ |
| P14 | vcpkg が見つからない | `-VcpkgExe C:\nosuch\vcpkg.exe` を `VCPKG_ROOT` なしで。ただし、存在しないときは、次の候補 (VS 同梱) に進むため、VS からも見つからない状態が要る | `ENV_ERROR` (`vcpkg.exe was not found`) | ✗ (再現できなければ △) |
| P15 | vcpkg のタイムアウト | `-PackageTimeoutSec 5` で起動し、ポートが多い状態から `vcpkg install`。その後、通常の制限時間で再実行 | `ENV_ERROR` (`vcpkg timed out`)。再実行は、キャッシュで続きから進む | ✗ |
| WS8 | `net10.0` | `docs/TEST-PLAN.md` の WS8 のとおり (先に `dotnet --list-sdks`) | ビルドとテストが通る | ✗ (SDK 10 の有無が未確認) |
| WS10 | VS で作った `.sln` に追加 | **保留** (VS で、WPF アプリ + クラスライブラリの `.sln` を作ってからでないと、実施できない)。作ったら `add_project.py` で、ライブラリ + テストを追加し、VS で開く | エクスプローラーにプロジェクトが出る。構成マネージャーで `Any CPU` に対応づく。ビルドとテストが通る | 保留 |
| WS14 | 書式 | ホストで、生成物のフォルダで `dotnet format --verify-no-changes` (ウォッチャーには、この操作がない。**PowerShell で、手で実行する**) | 差分が出ない。出れば `.editorconfig` と生成コードの、どちらかを直す | ✗ |
| WS11〜WS13、WS16 | `wpf-test-first` の端から端まで、Red の判定、層の型の守り、Skill の起動 | `docs/TEST-PLAN.md` の各行のとおり (Claude が実行。F5 や VS の確認は、ユーザー) | 各行のとおり | ✔ (2026-10-20 実機、`WpfSample` で実施 (`WpfTdd` ではない)。**`wpf-test-first` が起動** (「テスト先行で進めて」の依頼から、Claude が Skill を選んだ)。**テストケースの一覧を提示** (トリム 2 ケース + 既存は変更なし + スコープの確認)。**Red: `FAILED`、`[ran 25: passed 23 / failed 2 / skipped 0]`、失敗は `Assert.AreEqual に失敗しました。<期待> が必要ですが、<実際> が指定されました` (例外ではない)** = 正しい Red。スタブは不要 (既存の実装が、仕様を満たさない仮の実装として働いた)。実装後 `PASSED` (25 件。**`PASSED` の出力は 1 行目だけで、件数・テスト名は出ない** (要約は、失敗のときだけ))。途中で `WATCHER_NOT_RUNNING` と、ファイルロックによる一時的な `ENV_ERROR` があり、再実行で解消 (実際の Red ではない)) |

## 3. 実施の順序 (案)

1. Claude: P1 → P2 → P3 → P5 → P7、U11、WS9、WS19、WS20、P16 → P17 → P18、P20、P21、WS15 (まとまりごとに、依頼文を示してから)。
2. ユーザー: U6c、U9、U10、U12、U13、U15、P6、P15、WS14。
3. 環境が整ったとき: WS8 (SDK 10)、WS10 (VS の `.sln`)、U14 (MSBuild だけの環境)、P14。
