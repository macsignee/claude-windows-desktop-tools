# 次の確認 (再開用メモ)

2026-10-18 の終わりの時点の、実機の確認の状況と、再開の手順。**確認が済んだら、このファイルは、消してよい** (本来の記録は、`docs/TEST-PLAN.md` の「状況」列)。

## 確認済み (2026-10-18 実機)
- U1 (C++ の回帰: H1〜H3、T1 / T2 / T4 / T5)、U2 (起動のヘッダー)、U3、U6
- WS1、WS2、WS3、WS4、WS6、WS7、WS17、WS18 (生成した WPF + MSTest が、ビルド・テスト (8 件)・起動できる)
- **直した不具合 (v2.4.1):** `dotnet test` の出力の文字化け (UTF-8 を ANSI として読んでいた)、環境変数 `Platform` の漏れ (`bin\auto` で、テストの DLL が見つからなかった)
- △ (一部): U6b (`test.log` の日本語は、化けない。**失敗メッセージの日本語は、未確認**)、U6c (修正版で動いた。**環境変数をわざと設定した再現は、未実施**)

## 解決済み (2026-10-19)
- **「フォルダは `WpfSample` なのに、生成物が小文字の `wpfsample` になる」件:** 実際のフォルダ名が、そもそも小文字の `wpfsample` だった (`ls` で確認)。`new_solution.py` は、実際のフォルダ名を使うので、**正しい動作** (不具合ではない)。Windows のパスは、大文字小文字を区別しないので、`WpfSample` と書いても開け、誤解した。大文字の名前にしたいときは、フォルダの名前を変えてから、生成する。
- 配布状況 (2026-10-19 09:20 時点): ホスト側ツール、Skill、規約 (`wpf-csharp.md`) は、すべて最新。最後の実行 (10/18 17:46) は、`SUCCESS` / `PASSED` (確認のために変えたファイルは、元に戻っている)。

## 残り (TEST-PLAN の ID)
| 区分 | 残り | 件数 |
|---|---|---|
| 1-5 統合 | U4 U5 U7 U8 U9 U10 U11 U12 U13 U14 U15 U16 (と、U6b / U6c の残り) | 12 |
| 1-6 パッケージ | P1〜P21 | 21 |
| 2-3 wpf-check | W1〜W12 | 12 |
| 2-4 WPF の生成とテスト先行 | WS5 WS8 WS9 WS10 WS11 WS12 WS13 WS14 WS15 WS16 WS19 WS20 | 12 |

## 再開の準備
1. ホスト側ツールが最新か (`~/src/copy-host-tools.sh` を実行済みか)。
2. ウォッチャーを、`C:\workspace\macsignee\source\repos\WpfSample` で起動 (`C:\tools\cpp-watcher\run_watcher.cmd <フォルダ>`)。
3. **コンソールの Claude は、このリポジトリの会話を、知らない。** 下の依頼文を、**そのまま**貼る。
4. 結果は、表で報告してもらい、この会話 (または、新しい会話) に貼る。ログは、読み取りだけで、こちらから見られる (フォルダのパスを伝える)。

## 推奨の順序
1. **下の依頼文 (U4 / U5 / U7 + U6b / WS5)** — 生成したソリューションの、エラーの検出と要約。
2. **P (パッケージ)**: P8 → P10 → P11 (vcpkg と MSBuild の連携。外れると、C++ の標準方式が動かない)。次に P1〜P7 (NuGet)。
3. **W1 (`wpf-check` の誤検出)**: 実在の WPF プロジェクトで `--all`。
4. WS9 / WS10 / WS11 / WS12 / WS13 / WS16 (後付け、`.sln`、`wpf-test-first` の端から端まで、Skill の起動)。
5. U8〜U16 (混在、環境エラーの分岐)、WS14 / WS15 / WS19 / WS20、残りの P。

## コンソールの Claude に貼る依頼文 (U4 / U5 / U7 / U6b / WS5)

```text
このフォルダ (WpfSample) は WPF (MVVM) + MSTest のソリューションで、ウォッチャーが起動済みです。
ビルド (auto-build の build_once.sh) とテスト (build-test-loop の build_test_once.sh) は、すでに SUCCESS / PASSED (8 件) を確認済みです。
次の確認を、番号の順に実行して、結果を表 (項目 / 期待 / 実際 / OK か NG か) で報告してください。
各項目のあとは、必ず、元に戻してください (最後に、ビルドとテストが、PASSED に戻ることを確認)。git commit / git push は、しないでください。

1. U4: XAML のエラーの検出
   wpfsample/Views/MainWindow.xaml の Window の中に <local:NoSuch /> を 1 行足して (xmlns:local が、なければ、未定義の名前空間でもよい)、
   build_once.sh を実行する。期待: FAILED。要約に、MC または XDG のエラーと、.xaml の相対パスが出る。元に戻す。

2. U5: C# の構文エラーの検出
   ViewModels/MainViewModel.cs の、行末の ; を 1 つ消して、build_once.sh を実行する。
   期待: FAILED。要約に、CS で始まるエラーと、ViewModels/MainViewModel.cs(行) が出る。元に戻す。

3. U7 と U6b: テスト失敗の要約と、日本語
   ViewModels.Tests/MainViewModelTests.cs の、期待値の "名前を入力してください" と "こんにちは、太郎 さん" を、どちらも、別の文字列に変えて (日本語を含めてよい)、
   build_test_once.sh を実行する。期待: FAILED。要約に、失敗したテスト名 (ViewModels.MainViewModelTests.…) と、
   Assert.AreEqual failed. Expected:<...>. Actual:<...>. が、日本語が化けずに出る (.claude-logs/test_summary.json と test_error.log も、文字化けがないこと)。
   [ran 8: passed 6 / failed 2 / skipped 0] のような件数が出ること。元に戻す。

4. WS5: wpf-check
   python3 -I ~/.claude/skills/wpf-check/scripts/wpf_check.py "$PWD" --all
   期待: error 0 / warning 0 / info 0。
```

---

## P8 → P13 (vcpkg と MSBuild の連携。2026-10-19 追加。**使うプロジェクト: `MfcSdiLayers`**)

**目的:** C++ のパッケージ追加の標準方式 (vcpkg のマニフェストモード) が、実機で動くこと。**外れると、C++ の標準方式が動かない**ので、最優先。

**対象:** `C:\Workspace\macsignee\source\repos\MfcSdiLayers` (MFC SDI + `LogicLayer` + `DataLayer` の DLL。`/new-solution` で作った、テストなしのサンプル)。
- **作業フォルダは、外側の `...\repos\MfcSdiLayers`** (`MfcSdiLayers.slnx` がある所)。内側の `...\MfcSdiLayers\MfcSdiLayers` は、メインの MFC アプリのプロジェクトのフォルダ。ウォッチャーも、Claude Code も、**外側**で動かす。
- `setup` は、**3 つの `.vcxproj` (`MfcSdiLayers` / `LogicLayer` / `DataLayer`) を、書き換える。** そのため、ビルド中に、3 つのプロジェクトが、同じ `vcpkg.json` に対して、**並列に** `vcpkg install` を呼ぶ形になり、**並列ビルドの競合の確認 (DESIGN 4.26 の懸念) も、兼ねる** (P10 で、先に `vcpkg install` を済ませるので、通常は、起きないはず)。

### 準備 (ご自身で)
1. **バックアップを取る** (git 管理されていない。`setup` が `.vcxproj` を書き換える)。WSL のターミナルで:
   ```bash
   cp -r /mnt/c/Workspace/macsignee/source/repos/MfcSdiLayers /mnt/c/Workspace/macsignee/source/repos/MfcSdiLayers.bak
   ```
2. **ウォッチャーを、外側のフォルダで起動する:** `C:\tools\cpp-watcher\run_watcher.cmd C:\Workspace\macsignee\source\repos\MfcSdiLayers`
   (起動画面が `Solution : C++`、`Build : Debug|x64` であること)
3. **Claude Code を、同じ外側のフォルダで起動する。**
4. ホスト側ツールと Skill が最新であること (`~/src/copy-host-tools.sh`、`install/install.sh --skills-only`)。

### コンソールの Claude に貼る依頼文

```text
このフォルダ (MfcSdiLayers。MfcSdiLayers.slnx がある外側のフォルダ) は、/new-solution で作った、MFC SDI + LogicLayer + DataLayer (DLL) の、C++ のソリューションです。
ウォッチャーは、このフォルダで起動済みです (Visual Studio 同梱の vcpkg を使う)。バックアップは、取ってあります。
add-package Skill の、C++ (vcpkg) の手順が、実機で動くかを、次の順に確認して、結果を表 (項目 / 期待 / 実際 / OK か NG か) で報告してください。
失敗したときは、出力を、省略せずに、そのまま報告してください (原因を推測して直さない。git commit / git push は、しない)。
スクリプトは、~/.claude/skills/add-package/scripts/ と、~/.claude/skills/auto-build/scripts/ のものだけを使ってください。
vcpkg install は長い (数分以上) ので、run_in_background: true で実行し、完了通知が来るまで、ほかのコマンドを実行しないでください。

事前: まず、ビルドが通ることを確認してください (bash ~/.claude/skills/auto-build/scripts/build_once.sh "$PWD" 300 が SUCCESS)。通らなければ、そこで止めて報告。

P8: セットアップ
  python3 -I ~/.claude/skills/add-package/scripts/cpp_pkg.py setup "$PWD"
  期待: vcpkg.json ができ、MfcSdiLayers / LogicLayer / DataLayer の 3 つの .vcxproj に <PropertyGroup Label="Vcpkg"> が入る (出力を、そのまま報告)。
  vcpkg.json の内容と、LogicLayer/LogicLayer.vcxproj の Vcpkg のグループ (差分の部分) を、示してください。
  そのあと、「Visual Studio で MfcSdiLayers.slnx を開いて、3 つのプロジェクトが読み込めるか (プロパティページの vcpkg で、マニフェストが有効になっているか)」を、ユーザーに確認して、答えを待ってください。

P9: vcpkg search
  bash ~/.claude/skills/add-package/scripts/package_once.sh "$PWD" "vcpkg search fmt"
  期待: OK と、ポートの一覧。FAILED / ENV_ERROR のときは、出力を、そのまま報告 (これは、実機で、初めて分かること)。

P10: 追加と取得
  python3 -I ~/.claude/skills/add-package/scripts/cpp_pkg.py add "$PWD" fmt
  bash ~/.claude/skills/add-package/scripts/package_once.sh "$PWD" --timeout 1800 "vcpkg baseline" "vcpkg install"
  期待: OK。vcpkg.json に builtin-baseline が入る (python3 -I ~/.claude/skills/add-package/scripts/cpp_pkg.py list "$PWD" で確認)。vcpkg_installed\x64-windows-static-md\ ができる。
  かかった時間も、報告してください。

P11: ビルドの連携 (最重要)
  LogicLayer/LogicLayerModuleInfo.cpp を、fmt を使う形に、変える (戻り値は、同じ "LogicLayer" のまま):
    #include <fmt/core.h> と #include <string> を足し、LogicLayerModuleName() を、
    static const std::string name = fmt::format("{}", "LogicLayer"); return name.c_str(); にする。
  bash ~/.claude/skills/auto-build/scripts/build_once.sh "$PWD" 600
  期待: SUCCESS (LogicLayer が、fmt をインクルードしてリンクできる。MfcSdiLayers と DataLayer も、ビルドが通る。ビルド中の vcpkg install が、何もしないので、速い)。
  失敗したときは、要約を、そのまま報告し、さらに、次を調べて報告してください (直さない):
   (a) .claude-logs/build.log に、vcpkg に関する行があるか (grep -a -i vcpkg)
   (b) vcpkg.json が、見つかっているか
   (c) vcpkg_installed の下に、triplet のフォルダがあるか
   (d) 3 つのプロジェクトが、並列に vcpkg install を呼んで、競合しているように見えるか (build.log の、vcpkg のエラー)

P13: 存在しないポート
  python3 -I ~/.claude/skills/add-package/scripts/cpp_pkg.py add "$PWD" no-such-port-xyz
  bash ~/.claude/skills/add-package/scripts/package_once.sh "$PWD" --timeout 1800 "vcpkg install"
  期待: FAILED (ポートが見つからない。ENV_ERROR ではない)。
  確認したら、必ず、python3 -I ~/.claude/skills/add-package/scripts/cpp_pkg.py remove "$PWD" no-such-port-xyz で、元に戻し、
  もう一度 build_once.sh が SUCCESS になることを、確認してください。
```

### 報告のあと
- 私は、`C:\Workspace\macsignee\source\repos\MfcSdiLayers` を、読み取りで見られる (ログ、`vcpkg.json`、`.vcxproj`、`vcpkg_installed`)。「ログを見て」と言ってもらえれば、読む。
- **PackageReference (P22〜P24) は、見送り** (2026-10-19、ユーザーの決定。C++ の NuGet は、Experimental のため)。C++ のライブラリは、vcpkg だけ。
- **P12 (Release の CRT の整合)** は、ウォッチャーを `-Configuration Release` で起動し直す必要がある。P11 のあとで、別に行う。
- P9 (`vcpkg search`) が、VS 同梱の vcpkg では、動かない可能性がある (ポート一覧が、同梱されていない)。その場合の対応は、結果を見てから決める。
- **元に戻したいとき:** バックアップ (`MfcSdiLayers.bak`) から、戻す (`vcpkg.json`、`vcpkg_installed`、`.vcxproj` の変更が、すべて消える)。


## 残りの実機確認 (2026-10-19)
手順・期待値・実施者は、`docs/REMAINING-CHECKS.md` に集めた (U6c / U7〜U16、P1〜P7 / P14〜P21、WS8〜WS16 / WS19 / WS20)。結果は `docs/TEST-PLAN.md` に記録する。
