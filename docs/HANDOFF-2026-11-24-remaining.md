# 引き継ぎ: 残作業 (2026-11-24 夜。別セッションで行う)

> **最新の引き継ぎは `docs/HANDOFF-2026-11-25.md`** (2026-11-25 に、R2〜R6 が済み、main は v2.105.6)。この文書は、残作業の一覧 (R1〜R20) として、使う。

リポジトリ: `macsignee/claude-windows-desktop-tools` (WSL: `~/src/claude-windows-desktop-tools`)。**main は v2.105.0** (配布済み)。
**この文書は、残作業だけを、詳しく並べたもの。** 作業の経緯と、マージしたものは `docs/HANDOFF-2026-11-24-evening.md`、約束事 (作業の進め方) は `docs/HANDOFF-2026-11-24.md` の第 1 節と、`docs/HANDOFF-2026-11-18.md` の第 1 節。

## 0. 次のセッションの、最初の依頼文
```
~/src/claude-windows-desktop-tools の docs/HANDOFF-2026-11-24-remaining.md を読んで、引き継いで。
まず git switch main && git pull (allowed_domains に github.com) で最新にして、cat VERSION を確認して (2.105.0 以上)。
そのあと、第 2 節の残作業から、どれに着手するかを聞いて (勝手に始めないで)。
```

## 1. 前提
- **勝手に始めない。** 着手する項目を、ユーザーに聞く。コミット・push・PR は、ユーザーが頼んだときだけ (これまでの慣例: 作業が済んだら、「コミットして PR にしますか」と聞く。承認されたら、コミット → push (WSL の `git push`。ウォッチャー不要) → `gh pr create`)。
- 作る前に、ブランチを切る (`git switch -c <名前>`)。ブランチを切る前に `cat VERSION` で、main が古くないか確認する。
- 新しい機能・不具合の修正は、**テストを先に書く (Red) → 実装 (Green)**。ホスト側 (`host-tools/`) を変えたら、`HOST_VERSION` を `VERSION` に合わせ、最初の実機の確認は「ウォッチャーが起動して `--status` が返る」。
- 実機の確認は、**確認用フォルダ (`ClaudePlayground` の下) で、ユーザーが Claude Code を起動して、依頼文を貼る**。依頼文は、コピーできる形で渡し、結果の出力を、貼ってもらう。
- サンドボックスは、`git stash`、`rm -rf` を含む Bash、`powershell.exe` を拒否する。一時ファイルは `$TMPDIR`。

## 2. 残作業の一覧
**凡例:** 規模 = 小 (1 セッションの前半) / 中 / 大。

### 2-1. 判断待ち (大きい。ユーザーの決定が要る)
| ID | 項目 | 内容 | ユーザーに聞くこと |
|---|---|---|---|
| R1 | 仕様の逆生成 Skill | 既存の MFC・WPF のコードから、仕様書 (`docs/specs/<機能名>.md`) を作る新しい Skill。`claude-spec-workflow` と組み合わせる | 既存のプロジェクトを、仕様駆動へ移す予定があるか。対象 (MFC・WPF・両方)。作るなら大 |
| R2 | 混在ソリューションの正式な作成 | WPF + C++ の層などを、`/new-solution` で作れるようにする。いまは `add_layer.py` で足す即席の形 (v2.98.2 で、`.slnx` に `x64` がなく `MSB4126` になる不具合を直した) | 正式にするか、「即席」と明記し続けるか |

### 2-2. 軽く進められるもの (おすすめの最初)
| ID | 項目 | 規模 | 手順・メモ |
|---|---|---|---|
| R3 | 文書の整理 | 小 | (1) `docs/NEXT-STEPS.md` の冒頭 (3 行目) が、「2026-11-24 時点 (v2.102.7。最新の引き継ぎは `HANDOFF-2026-11-24.md`...)」のまま。v2.105.0・最新の引き継ぎ (この文書) に合わせる。第 1 節に、SDI・MDI の実機確認の済みと、`vs-debug` の改善 (v2.104.1〜v2.104.3) の済みが、反映されているかを確かめる。(2) `docs/REMAINING-CHECKS.md` の見出し・日付を、現状に合わせる。(3) `docs/HANDOFF-2026-11-17.md` (未追跡。古く不要と、NEXT-STEPS に書いてある) は、ユーザーが削除するか決める。文書だけの変更で、バージョンは上げない |
| R4 | IM4: 最適化された C++ のモジュールでの `(unavailable)` の確認 | 小 | C# の Release では、変数が普通に読めて、再現しなかった (TEST-PLAN 2-67)。**C++ (Release、最適化あり) の確認用ソリューション (`MfcScope` など) に、一時的なコード (`// SP-TEMP`) を足し、Release x64 で、`--debug --inspect`。** 最適化で消えた変数が `NAME = (unavailable)  (型)` の 1 行になれば合格。終わったら、一時的なコードを消す。結果を TEST-PLAN 2-67 の IM4 に記録 |
| R5 | `ExtLayerApi.h` の注意書き (v2.97.0) の実機確認 | 小 | MFC 拡張 DLL (`mfc-ext-dll`) の公開ヘッダーのひな形に、「公開ヘッダーは、自分で `<afxwin.h>` を include する」と書いてある。確認用ソリューションで、公開ヘッダーを使う側の `.cpp` が、`<afxwin.h>` なしでも、ビルドが通るかを確かめ、注意書きが正しい (または不要) か判断する。REMAINING-CHECKS の行に結果を記録 |
| R6 | `token_report.py` を、リポジトリへ入れるか | 小 | セッションのログ (`~/.claude/projects/<フォルダ>/*.jsonl`) の、ターンごとの `usage` を集計するスクリプト。**いまは、前のセッションの一時的な場所にしかなく、消える。** 必要なら、`tools/token_report.py` として作り直す。集計項目: (a) 合計 (input / cache_creation / cache_read / output)、(b) 1 ターンの文脈の大きさ (input + cache_read + cache_creation) の、最初・最後・最大、(c) Skill の読み込み (ユーザー側のメッセージで `Base directory for this skill` で始まるテキストの文字数と、その時点の文脈の大きさ)、(d) ツールの結果の文字数と回数 (ツール名ごと)、(e) `--timeline` (ターンごとの文脈の増減とツール名)。**assistant のメッセージは、`message.id` が同じ行に、分割されて並ぶので、`id` で重複を除く。** 規約の読み込みは、`attachment.type == nested_memory` の行で分かる。テストは、小さな疑似のログで行う。USAGE 4 に、使い方を足す |

### 2-3. 任意の実機確認 (すべて任意。必要になったとき)
| ID | 項目 | 備考 |
|---|---|---|
| R7 | WL8: ウィザードの実物と、並べての全体比較 | `ClaudePlayground\MFCSDITemplate` と `MfcSdiLook` を、並べて目視する。TEST-PLAN 2-65 の WL8 は、「一部」(メニュー バーの出方、メニュー、右クリックは、実物と同じと確認) |
| R8 | ST5 | `UiDialogs.SetText` の、読み戻しが合わない部品のフォールバック (TEST-PLAN 2-46) |
| R9 | UJ5 | VS のリソース ビューで、日本語の `.rc` を開く (文字コードの確認の画面が出るか。TEST-PLAN 2-59) |
| R10 | GR6・GR7 | `git-remote`。リモートが手に入ったとき (TEST-PLAN 2-64) |
| R11 | DLL008 の実行時、`AFX_MANAGE_STATE` の実行時 | DLL008: MFC の状態を使う関数 (`CString`・ダイアログ・リソース) を、MFC なしの exe から呼ぶと、実行時に壊れるか。`AFX_MANAGE_STATE`: 外して、ダイアログを使う関数を動かす。Claude が、確認用ソリューションで行う (ウォッチャーが要る) **(済み 2026-11-28。TEST-PLAN 2-76)** |
| R12 | VS での目視 (ユーザーの作業) | MX・SD のプロパティページ、UH4 (画面を持つ DLL の見た目)、AR (「参照」の画面)、RN (Windows のショートカットが、旧い配布先を指していないか) |

### 2-4. 任意の機能・改善 (優先度は低い。必要になったとき)
| ID | 項目 | 着手の条件 |
|---|---|---|
| R13 | `mfc-check` の `APP001`: `CWinApp` 派生クラスのメッセージマップが、`.rc` のメニューの標準 ID (`ID_FILE_NEW`・`ID_FILE_OPEN`・`ID_FILE_PRINT_SETUP` ほか) を、結びつけているかの検査 | 優先度は低い (SDI の「開く」の不具合の再発防止)。標準 ID を接頭辞で「見つかった」扱いにする設計が、見逃しの原因 |
| R14 | `--project` で、本体とテストの MSBuild を 1 回にまとめる | 遅くて困る例が出てから (小さいソリューションでは、差がなかった) |
| R15 | アプリが、決まった場所にログのファイルを書く規約 (`vs-debug` の案 B) | UI テストなど、VS を使わない実行でも、解析したくなったとき。ひな形と規約を、WPF・WinForms・MFC に足す。大 |
| R16 | UI-KEY-003 (タブ停止) の静的検出 | 誤検出が増えやすい。必要になったとき |
| R17 | 「既知の指摘」の質問を、指摘ごとにする (`ui-test-first`) | 運用して、不都合が出たとき |
| R18 | 「ウォッチャーが起動済みか」を、質問ツールで尋ねない (`WATCHER_NOT_RUNNING` のときだけ依頼) | 再び出たら (W5 の `console` で 1 回) |
| R19 | 国際化 (リソースへの移行、`APP_CULTURE`、Satellite DLL)、非同期 `Commit()`、`switch (nID)` の `mfc-check` 検査、C# で複数プロパティの変更をまとめる必要、MFC の `Observable` の継続的な検証 | 低優先・保留。実装がないので、確認する対象もない |
| R20 | UI ガイドラインの更新 | 新しい版が出たら、`skills/ui-design-review/references/UI-Design-Guidelines.md` を置き換え、`GUIDELINE_VERSION` (`ui_guideline_check.py`) を合わせる。規則 ID の対応は、テストが確かめる |

### 2-5. 条件がそろうまで保留
T6、N0、N3s、TG1、TG3 (条件を作れない)、UG3・UG4・UG4b、WC4、WS10 (VS で `.sln` を作ってから)。理由と再開条件は、`docs/REMAINING-CHECKS.md` の「2-3」「2-4」。

### 2-6. ユーザーの作業 (Claude は触れない)
1. PS5 の `// SP-TEMP` の行を消す (確認用コード)。
2. VS の設定を戻す (構成を Debug に)。**(2026-11-25 訂正: 「モジュールの読み込み時に JIT 最適化を抑制する」のチェックは、もともと設定されていない。戻す作業は、要らない。)**
3. 確認用フォルダ `ClaudePlayground\PS5_run_A`・`PS5_run_a` を削除する。
4. `ImageSampleApp`: `gr-test` から `gr-test5` までのブランチ (ローカルとリモート) を削除する。コミット `74e5b0a` の空ファイル 23 件 (`.bashrc`・`.gitconfig`・`.mcp.json`・`.vscode`・`.idea`・`.claude/*`) を削除して、`.git/info/exclude` と `.gitignore` に `git_result.txt`・`git_error.log`・`git_output.txt` を足す。
5. このリポジトリの、リモートの約 200 ブランチと、未追跡のファイル (`.claude/`、`.mcp.json`、`docs/HANDOFF-2026-11-17.md`、`poc/`、`q`) を整理する。
6. `PS5` の古い `CLAUDE.md` の UI テストの節を、新しい版にしたいときは、`add_ui_tests.py --refresh-claude-md` (v2.105.0 で、生成物が短くなった)。

## 3. 決定済み (蒸し返さない)
- **SDI・MDI の寄せ (v2.103.0・v2.104.0):** 印刷・プレビュー・OLE・`SHARED_HANDLERS`・Win32 構成・`C` 接頭辞・`l.JPN` の `afxres.rc` は、寄せない。SDI のメニュー バーが、最初は隠れていて Alt で現れるのは、ウィザードの実物と同じ動き。
- **Token 削減:** Skill 本文・規約の分割は、見送り (効果は費用の約 3〜5%)。`.claude/settings.json` (プラグインの停止) を `/new-solution` が生成する案も、見送り。運用 (作業ごとに新しいセッション、確認用フォルダで使わないプラグインを止める) は、USAGE 4。
- **画面モデル:** 名前は `ScreenModel` のまま。規約の `paths` から Presenter を外した。`brainstormF` に検査・失敗の観点を足さない。VO2 (英語の VS) は確認しない。SK1 は確認しない。
- **`git-remote`:** pull は含めない (ユーザーが VS で行う)。push・PR は、WSL の `git push` と `gh` で通る (ウォッチャー不要)。`gh pr edit` は、Projects(classic) の GraphQL エラーで失敗するので、REST (`gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f base=main`) を使う。

## 4. おすすめの順
1. **R3 (文書の整理)**: 10 分程度。最初に済ませると、以降の文書が現状と合う。
2. **R4 (IM4 の C++ での確認)** と **R5 (`ExtLayerApi.h`)**: 実機で 1 回ずつ。
3. **R6 (`token_report.py`)**: 今後も Token を測るなら。
4. 判断が付いたら、**R1・R2** (大きい作業)。
5. R7 以降の任意の項目は、必要になったときに。

## 5. 技術メモ (主なもの。全体は `HANDOFF-2026-11-24-evening.md` の第 5 節と、`HANDOFF-2026-11-24.md` の第 6 節)
- `/mnt/c` の大きなフォルダの複製は、`robocopy` (WSL の `cp -r` は、遅く、VS 使用中の `.vs/` で失敗する)。複製先が既にあると、中にサブフォルダとして全体がコピーされ、ビルドが壊れる。
- ウォッチャーは、起動時に指定した 1 つのフォルダだけを見る。複製したフォルダには、そのフォルダ用に、`run_watcher.cmd` を起動する。
- PowerShell (`vs-ide.ps1` など) は、WSL で動かせない。静的テストで形を固め、**実機の最初の確認は `--status`** (構文の誤りの検出)。
- `vs-debug`: break の直前に、モードが一瞬 `unknown` になる。待ちは `run` と `unknown` の両方を待つ。DTE のモードは 1=design、2=break、3=run。
- 全テストの実行: `for t in tests/*.sh; do bash $t; done` (`fake_watcher_test.sh` の `FAILED` の表示は、疑似の失敗テストの想定出力)。
