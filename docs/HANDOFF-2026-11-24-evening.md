# 引き継ぎ (2026-11-24 夜。`HANDOFF-2026-11-24.md` の続き)

> **残作業だけを、詳しく並べた引き継ぎは、`docs/HANDOFF-2026-11-24-remaining.md`** (別セッションは、こちらから始める)。この文書は、今日の経緯と、非自明なことの記録。

リポジトリ: `macsignee/claude-windows-desktop-tools` (WSL: `~/src/claude-windows-desktop-tools`)。**main は v2.105.0** (PR #257 のマージ後)。
**この文書は、`docs/HANDOFF-2026-11-24.md` の続き (差分)。** 第 1 節の約束事 (作業の進め方) と、技術メモは、`HANDOFF-2026-11-24.md` と `HANDOFF-2026-11-18.md` のままで、今も有効。この文書は、その後 (2026-11-24 の午後から夜) の、マージしたもの・状態・決定事項・残りだけを書く。

## 0. 最初にやること (新しいセッション)
1. `git switch main && git pull` (`allowed_domains` に `github.com`)。**`cat VERSION` が `2.105.0` 以上なら最新。** ブランチを切る前に確認する。
2. 読む順: この文書 → `docs/HANDOFF-2026-11-24.md` の第 1 節 (約束事) → `docs/NEXT-STEPS.md` → `docs/REMAINING-CHECKS.md`。
3. 配布 (`./install/install.sh`) は、ユーザーが、各 PR のマージ後に、済ませている (v2.105.0 まで)。ウォッチャーの再起動は、ホスト側が変わった v2.104.3 まで。
4. **第 4 節 (残り) から、ユーザーに、着手する項目を聞く。勝手に始めない。**

## 1. この期間にマージしたもの (すべて配布済み)
| PR | 版 | 内容 |
|---|---|---|
| #249 | v2.103.0 | `/new-solution --type mfc` (SDI) の初期状態を、VS のウィザードの見た目と操作に寄せた (`CWinAppEx`・`CFrameWndEx`・メニュー バー・ツール バー・ステータス バー・MRU・`AboutDlg` ほか。DESIGN 4.98) |
| #250 | v2.104.0 | 同じく MDI (`--type mfc-mdi`)。`CMDIFrameWndEx`・タブ付き MDI・ウィンドウ ダイアログ。`OnCreateClient` の上書きをやめた。`ID_FILE_OPEN` も結びつけた (DESIGN 4.99) |
| #251 | (文書) | SDI・MDI の実機確認の記録 (TEST-PLAN 2-65・2-66) |
| #252 | v2.104.1 | `vs-debug` の (b) 読めない値は `(unavailable)`、(c) 値は 10 進 (`HexDisplayMode` を一時的にオフ)、(d) `STOPPED:` の場所をフレームから (最大 3 秒待つ) |
| #253 | v2.104.2 | (a) `--debug --inspect` が、20 秒で break に届かないとき、さらに最大 40 秒、待つ |
| #254 | v2.104.3 | (a) の待ちが、break 直前の `unknown` で終わる不具合を直した (実機の IM7 で発見) |
| #255 | (文書) | `vs-debug` の改善の実機確認の記録 (TEST-PLAN 2-67) |
| #256 | v2.105.0 | `/new-solution` が作る `CLAUDE.md` を短くした (UI テストの節・MSBuild の節。WPF + UI テストで 7,034 → 4,498 文字) |
| #257 | (文書) | `docs/USAGE.md` に「4. Token を使いすぎるとき」を足した |

## 2. 現在の状態 (実機の確認)
- **SDI・MDI の寄せ (2-65・2-66):** WL1〜WL7、WM1〜WM8 は合格。**WL8 (ウィザードの実物と並べての全体比較) は一部** (メニュー バーの出方、メニュー、右クリックは、実物と同じと確認)。SDI のメニュー バーが、最初は隠れていて Alt で現れるのは、**ウィザードの実物と同じ動き** (不具合ではない)。
- **`vs-debug` の改善 (2-67):** IM1〜IM3、IM5〜IM7 は合格。**IM4 (最適化されたモジュールの `(unavailable)`) は、C# (WPF) の Release で再現せず。C++ の最適化されたモジュールでの確認は、保留。**
- 全テストは通る (`for t in tests/*.sh`。`fake_watcher_test.sh` の `FAILED` の表示は、疑似の失敗テストの想定出力)。

## 3. Token 削減の結論 (2026-11-24 に測った。USAGE 4 に、まとめた)
- **費用の中心は、「文脈の大きさ × ターン数」。** 毎ターン、これまでの全部を読み直す。1 つのセッションに、いくつも作業を詰めると、後半ほど重い (この開発のセッションは、219 ターンで、文脈が 30 万まで伸びた)。
- **新しいセッションの直後は、約 45〜49k。** うち約 31k は、Claude Code 本体で、削れない。
- **Red までの作業 (WPF の TDD、14 ターン) の増加 +22.8k のうち、約 77% は、固定の読み込み:** `csharp-test-first` の本文 +11.6k、`csharp-common.md` の規約 +5.9k。実際の作業は約 5k。
- **やったこと:** `CLAUDE.md` の生成物を短くした (約 −1.8k/ターン、v2.105.0)。確認用フォルダで、使わないプラグインを止めた (49.3k → 45.1k。**ユーザーの設定で、リポジトリの変更ではない**)。USAGE に、運用 (作業ごとに新しいセッション、プラグインの停止) を書いた。
- **見送った (決定。蒸し返さない):** Skill の本文と規約の分割 (効果は、費用の約 3〜5%。`csharp-test-first` は、すでに `PROJECT-LAYOUT.md`・`references/` に分けてある。手間と、TDD の実機確認のやり直しに、見合わない)。`/new-solution` が `.claude/settings.json` (プラグインの停止) を生成する案 (止めるものは、ユーザーごとに違うので、不向き)。ターン数を減らす案 (14 ターンのうち 4 ターンは、ウォッチャーが未起動だったための、やり直し。通常は約 10 ターンで、細切れは、ほぼ無い)。
- **測り方:** `/context` (新しいセッションの直後と、作業のあと)。Claude が、1 回の依頼で自動で進んでいる最中は、`/context` を打てないので、**セッションのログ (`~/.claude/projects/<フォルダ>/*.jsonl`) の、ターンごとの `usage` を集計する**。集計スクリプト (`token_report.py`) は、セッションの一時的な場所に作ったもので、**リポジトリには、入っていない** (必要なら `tools/` へ入れる。判断待ち)。

## 4. 残り (ユーザーに、着手する項目を聞く)
1. **判断待ち (大きい):** 既存コードから仕様を逆生成する新 Skill (`claude-spec-workflow`)。混在のソリューション (WPF + C++ の層など) を `/new-solution` が正式に作れるようにするか。
2. **任意:** `NEXT-STEPS` の候補 E(2) (`mfc-check` に `APP001`)、`mfc-ext-dll` の `ExtLayerApi.h` の注意書きの実機確認 (A7)、ST5・UJ5、git-remote の GR6・GR7 (リモートなし)、IM4 の C++ での確認。
3. **ユーザーの作業 (私は触れない):** (a) PS5 の確認用コード (`// SP-TEMP`) の削除と、VS の設定 (構成を Debug に、「モジュールの読み込み時に JIT 最適化を抑制する」を戻す。**2026-11-25 訂正: このチェックは、もともと設定されていない。戻す作業は、要らない**)。(b) 確認用フォルダ `ClaudePlayground\PS5_run_A`・`PS5_run_a` の削除。(c) `HANDOFF-2026-11-24.md` の第 5 節 5 の項目 (`ImageSampleApp` のブランチと空ファイル、リモートの約 200 ブランチ、未追跡のファイル)。

## 5. 技術メモ (今回、分かった非自明なもの)
- **`/mnt/c` の大きなフォルダの複製に、WSL の `cp -r` を使わない。** 非常に遅く (応答がなくなったように見える)、VS が使用中のファイル (`.vs/`) で `Permission denied` になる。**Windows 側の `robocopy` を使う** (`/XD .vs x64 obj bin .claude-logs .remember` で、生成物を除く)。**先に、複製先が存在しないことを確かめる** (途中の `cp` が、フォルダを作っていると、次の `cp` が、その中に、サブフォルダとして、全体をコピーし、ビルドが多重定義 (CS0101) で壊れる)。
- **ウォッチャーは、起動時に指定した、1 つのプロジェクト フォルダだけを見る。** 複製したフォルダで測るときは、そのフォルダ用に、`run_watcher.cmd` を起動する。
- **確認用フォルダのセッションのログの置き場:** `~/.claude/projects/` の、フォルダ名を `-` でつないだ名前。**`_` は `-` になり、大文字・小文字の違うフォルダ (`PS5-run-A` と `PS5-run-a`) が、別々にできることがある。**
- **push・PR は、WSL の `git push` と `gh` で通る (ウォッチャー不要)。** `git-remote` の Skill を、先に呼ぶと、ウォッチャーの未起動で `WATCHER_NOT_RUNNING` になる。`gh pr edit` は、Projects(classic) の GraphQL エラーで失敗するので、REST (`gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f base=main`) を使う。
- **ホスト側 (`vs-ide.ps1`) を変えたら、最初の実機の確認は「ウォッチャーが起動して、`--status` が返る」** (PowerShell の構文の誤りは、WSL では見つからない。`powershell.exe` はサンドボックスで動かない)。
- **`vs-debug` の `unknown`:** break の直前に、モードが一瞬 `unknown` になる。待ちの処理は、`run` と `unknown` の両方を待つ。
- **サンドボックスが拒否するコマンド:** `git stash`、`rm -rf` を含む Bash。一時フォルダは `$TMPDIR` を使い、消さずに残す。
- **MFC のウィザードの実物 (`ClaudePlayground\MFCSDITemplate`・`MFCMdiTemplate`) の `.rc` は UTF-16。** 読むときは、変換する。

## 6. 次のセッションの、最初の依頼文 (案)
```
~/src/claude-windows-desktop-tools の docs/HANDOFF-2026-11-24-evening.md を読んで、引き継いで。
まず git switch main && git pull (allowed_domains に github.com) で最新にして、cat VERSION を確認して (2.105.0 以上)。
そのあと、第 4 節の残りから、どれに着手するかを聞いて (勝手に始めないで)。
```
