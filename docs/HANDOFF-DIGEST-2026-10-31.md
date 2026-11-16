# 引き継ぎ (ダイジェスト) 2026-10-31 — 統合版

`~/src/cpp-claude-build-tools` の作業を、別のセッションに引き継ぐための要約。**2 つのセッションの内容を、統合した**: (A) ビルド・テスト・ウォッチャー側の作業 (v2.24.0〜v2.25.0。もう一方のセッション)、(B) UI デザインガイドラインの作成と取り込み (v2.26.0〜v2.28.0 など。このダイジェストを統合したセッション)。**2026-10-31 の夜に、v2.31.0 + REMAINING-CHECKS.md の整理 (PR #39。マージ済み) の時点へ更新した** (別セッションへの引き継ぎ用)。**詳細は、`docs/HANDOFF-2026-10-28.md` (未追跡。10-28 時点)、`docs/DESIGN.md`、`docs/TEST-PLAN.md`、`CHANGELOG.md`、`docs/NEXT-STEPS.md`。** このファイルは未追跡。コミットは、ユーザーが指示したときだけ。

## 1. これは何か

Windows のウォッチャー (ps1 / cmd) と、WSL の Skill で、C++ / MFC / WPF / WinForms / C# のビルド・テスト・UI テストを、自動で直して繰り返す仕組み。Claude は WSL のサンドボックスで動き、`trigger_*.flag` を書いて、Windows 側のウォッチャーに、ビルド・テストをさせる。

加えて、**UI デザインガイドライン (v2.10) を、Skill として取り込んである** (`/ui-design-review`)。画面を作る前の計画と、作った画面のレビューに使う。

## 2. いまの状態 (2026-10-31)

- `main` = **v2.31.0** (`24a0259`。**PR #39 までマージ済み**。`origin/main` と一致)。VERSION = 2.31.0。**開いている PR はない。進行中の作業もない。**
- **配布先は、v2.31.0 で配置済み** (ホスト側の `/mnt/c/tools/cpp-watcher` も、Skill の `~/.claude/skills` も。実機の出力に `watcher=2.31.0` が出ている)。
- 未追跡 (どれも、コミットしない): `.claude/`、`.mcp.json`、`docs/HANDOFF-2026-10-28.md`、`docs/HANDOFF-DIGEST-2026-10-31.md` (このファイル)、`poc/`。
- 不要なブランチが多数 (ローカルに 34 本。うち `main` に含まれるものが、ほとんど。未 push の `list`・`record-ns1-v2231`・`record-tg5`・`record-tp-v2270`・`record-ug4c` も、`main` に含まれていて、消してよい)。確認は `git branch --merged main`。消してよい: `record-*`、`*-v22xx`、`templates-ui-guideline-v2270`、`mfc-*`、`self-describing-results`、`gtest-nuget-removal` など (ユーザーが行う)。
- `.git/config.lock` (0 バイト、読み取り専用) が、残っていることがある (§6)。

## 3. 直近の版 (10-30 〜 10-31)

| 版 | 内容 |
|---|---|
| 2.24.0〜2.24.3 | 入口の分割: `/new-solution` = 1 つ、`/new-solutions` = 作業フォルダ (`solutions.md`) の複数の候補 (DLL も選べる)。`create` は検証してから作る。vcpkg の仕上げを `/new-solutions` に直接書いた |
| 2.24.4 | **起動したフォルダの綴りに合わせて、フラグを書く** (`align_to_launch_case`) |
| 2.24.5 | `test_guard_note.sh`: `build_test_once.sh` / `uitest_once.sh` の末尾に `TEST_GUARD: OK / REVIEW / ERROR` |
| 2.25.0 | `host-tools/run_watchers.cmd`: 候補ごとに、Windows ターミナルのタブ (`wt.exe`)。`/windows`、`/list` |
| 2.26.0 | **`/ui-design-review` を追加:** `skills/ui-design-review/` (`SKILL.md`、`references/UI-Design-Guidelines.md` = ガイドライン v2.10 の写し、`scripts/ui_guideline_check.py` = 静的検査 15 コード)。`ui-test-first` / `add-feature` の計画に、ガイドラインを参照させ、`wpf-check` / `winforms-check` / `mfc-check` に案内の節を足した |
| 2.26.1 | 実機の確認 (UG1〜UG5) の結果の反映: `UIG-LOC001` / `UIG-TYP001` / `UIG-CTL003T` を、info から warning に (必須の規則への指摘は warning。例外は `UIG-CTL101` だけ)。付録 F.2 の報告様式を `SKILL.md` に埋め込み。WPF の DPI の既定の注記 |
| 2.26.2 | UG4b の結果の反映: `ui-test-first` の計画の 2 つの表の定義に、列「守る規則 ID」。必須の指摘のすべてについて、質問に含める。F.2 の「適用した付録」の注記 |
| 2.26.3 | UG3c の結果の反映: 「画面の確認」の使い分け、「OS に追従するか」は色指定の有無では判定できない、の注記 |
| 2.27.0 (PR #30) | **生成するソリューションを、ガイドラインに合わせた:** UI-DPI-002 (WPF: `app.manifest` + `ApplicationManifest`、WinForms: `ApplicationHighDpiMode` = SystemAware)、UI-CTL-100 (MFC: `pch.h` に Common Controls の指令)、UI-ACC-001 / UI-CTL-020 (WPF: 見える `Label`)。DESIGN 4.46。TP1〜TP5 ✔ |
| 2.27.1 (PR #31) | WPF の名前欄に `LabeledBy` を付ける。`UIG-ACC001` は、`Label` の `Target` を認めない (Narrator で「名前、編集、改行」と読まれることを実機で確認) |
| 2.28.0 (PR #32・#33) | MFC ダイアログのひな形に、名前の入力欄・挨拶・クリアを入れる。UI テスト生成にも反映。MD1〜MD6 ✔ |
| 2.29.0 (PR #34) | **結果の自己記述と、版の不一致の検出** (警告のみ)。`install.sh` が配布先に `VERSION` を置く。ウォッチャーは、起動バナーに版を出し、`run_id.txt` に `watcher=` / `kind=` / `input=` / `finished=` を足す。Skill は、出力の末尾に `RESULT_INFO:` と、不一致の `NOTE:`。`harness_note.sh`。HV1〜HV8 ✔ (DESIGN 4.48) |
| (記録 PR #35) | **UI-LOC-001 (表示文字列のリソース化) は、ひな形の既定にしない、と決定** |
| 2.30.0 (PR #36) | MFC の DPI 認識を、`SetProcessDPIAware()` から、マニフェスト (`.vcxproj` の `EnableDpiAwareness` = `true`) に移す。MF1〜MF5 ✔ (DESIGN 4.49) |
| (記録 PR #37) | HV4 の未確認点 (テストが通るソリューションでの `kind=test`) を記録 |
| (整理 PR #39。マージ済み) | **`docs/REMAINING-CHECKS.md` を作り直した** (2026-10-31 時点。未了の項目を、廃止 / 小さく確認 / 一部のみ確認 / 保留に分け、保留に再開条件を付けた)。TEST-PLAN: N3・N10 = 廃止、H9 = ✔、N0 = △、N4 に注記 |
| 2.31.0 (PR #38) | **旧 NuGet 方式の GoogleTest を廃止** (`--gtest nuget` / `--gtest-from` は、終了コード 2 のエラー。**契約の変更**)。`source` は残す。`auto` = 既存の `gtest` プロジェクトなら source、それ以外は vcpkg。既存の旧方式のソリューションは壊さない。GN1〜GN4 ✔ (DESIGN 4.50)。PR #37 は、HV4 の未確認点 (kind=test) の記録 |

## 4. ガイドラインの、経緯と決定 (B のセッション)

- **ガイドライン本体:** `/home/shigene_makoto/Windows_Desktop_UI_Design_Guidelines_v2.10.md` (リポジトリの外。v2 → v2.10 まで、批判的レビューを繰り返して改訂した)。リポジトリの正本は、`skills/ui-design-review/references/UI-Design-Guidelines.md` (v2.10 の写し)。更新は、置き換え + `GUIDELINE_VERSION` を合わせる (規則 ID の対応は、テストが確かめる)。
- **決定事項:**
  - **v3 (共通規則と技術別付録の全面分割、4 文書の責任分担) は、見送り** (`Windows_Desktop_UI_Design_Guidelines_v3_Proposal.md` は、提案書として、そのまま残す)。再検討の兆候: 同じ規則の解釈がレビューで繰り返される / 判定の差が実際に出る / 技術別の記述が本文より長い / アーキテクチャ・実装規約の所管者が決まる / 外部監査で全規則の受入条件を求められる。
  - **ガイドラインのコンパクト化は、見送り** (案 A: 章を選んで読む運用のまま)。
  - **epx と DIP は、同値 (1 epx = 1 DIP) とみなす** (資料は同一とは明記していない。本ガイドラインの取り決め)。
  - **文書管理の「(記入)」(文書 ID、承認者など) は、意図的に空欄** (他部署の承認後に設定される。埋めない)。
  - テスト手法やテスト用識別子は、ガイドラインに入れない (別文書)。
  - `ui_guideline_check.py` の方針: 必須の規則への指摘は warning、推奨は info。error は出さない (推測による検出)。
- **ガイドラインの構造:** 規則 ID (`UI-XXX-nnn`)、強さ (必須 / 推奨 / 任意 / 廃止)、適用除外、受入条件 (AC-n。判定が分かれやすい必須 16 規則)、付録 E (仕様書テンプレート)、付録 F (レビュー用チェックリスト。本文から生成)。

## 4b. このセッションで決めたこと (ユーザーの決定。覆さない)

- **版の不一致は、警告 (NOTE) にとどめる** (v2.29.0)。ブロックにすると、古いウォッチャーで動いていた運用が止まるため。
- **UI-LOC-001 (表示文字列のリソース化) は、ひな形の既定にしない** (不要)。生成直後の WPF の `UIG-LOC001` (1 件) は、既知の指摘 (`ui-design-review` の SKILL.md に記載済み)。
- **旧 NuGet 方式の GoogleTest だけを廃止** (v2.31.0)。**`source` は残す。** 「`source` も外して vcpkg だけ」は、**見送り**: (1) 実ソリューション `ClaudeProject` が source 方式 (後付けで、同じ方式を使う `auto` が壊れる)、(2) vcpkg が使えない環境の逃げ道が、なくなる (ウォッチャーが vcpkg を探す方法は、未確認)。再検討するなら、先に `ClaudeProject` を vcpkg に移行できるかを試す。
- **MFC の DPI は、マニフェスト (`EnableDpiAwareness` = `true`) で宣言** (v2.30.0)。Per-Monitor は、ひな形の既定にしない (再レイアウトへの対応が要る)。
- **MFC ダイアログのひな形は、WPF・WinForms と同じ画面・動作** (入力 → あいさつ → クリア。v2.28.0)。
- **`REMAINING-CHECKS.md` の保留の項目は、再開条件がそろったときだけ確認する。確認していない項目を、✔ にしない** (他の確認で、同じ点が実機で確認できた場合だけ、根拠の行を書いて ✔ にする)。

## 5. 実機の確認の状況

- NS1〜NS11: すべて ✔ (NS4 の単一の衝突のみ未確認)。
- **`docs/REMAINING-CHECKS.md` (2026-10-31 に整理。PR #39 でマージ済み) が、未了の項目の一覧と、扱い・再開条件の正本。** 確認済みの区分、廃止、小さく確認、一部のみ確認 (△)、保留に分けてある。
- TG: TG2・TG4・TG5 ✔、TG1・TG3 △ (TG1 = テストが小さい。TG3 = Claude が、弱める依頼を断るので、誘導 → 検出の通しは不可)。
- **UG1〜UG5 と再確認 (UG3b・UG3c・UG3d・UG4b・UG4c): すべて完了** (TEST-PLAN 2-9)。得られた知見: (1) 自動起動は、依頼文の言い回しだけで動く (`ui-design-review`)。(2) `ui-test-first` は、スラッシュなしでは起動しない。(3) 報告の様式・計画の表は、指示を「表の定義」の中に書かないと、守られない (v2.26.1 → v2.26.2 で修正)。(4) 実行ごとに、指摘は揺れる (判断を要する規則)。(5) 承認の質問に「承認」を選ぶと、実プロジェクトにファイルが作られる (UG4b で `wpfsample.UITests` の作成と `AutomationProperties.Name` の追加が、実際に起きた)。
- **v2.27.0〜v2.31.0 の実機の確認: すべて ✔** (TP1〜TP5、MD1〜MD6、HV1〜HV8、MF1〜MF5、GN1〜GN4。TEST-PLAN 2-10〜2-14)。HV 系は、v2.29.0 の環境で行ったが、その後、ホスト側・Skill とも 2.31.0 に再配置済み (MF・GN の実機の出力で、`watcher=2.31.0` を確認)。

## 6. 運用のルール (重要)

- **コミットは、ユーザーが明示したときだけ** (1 コミットにまとめる指示が多い。`poc/` と HANDOFF は含めない)。push・PR・マージ・`git pull` は、ユーザー。サンドボックスの `gh` は、`allowed_domains: ["api.github.com"]` を付けると、読み取りができる (PR の状態の確認に使える)。
- **新しい作業は、新しいブランチで。** 前のブランチがマージされるまで待つのが原則 (CHANGELOG・VERSION・README・DESIGN・TEST-PLAN が衝突する)。**記録だけの変更 (TEST-PLAN) は、マージ前でも、積んだブランチ (stacked) にできる** (今回、`skill-notes-v2263` を `record-ug4c` の上に積み、PR 1 本で取り込めた)。未コミットがあると、`git checkout main` が止まる → 先にコミット。`git push` が「Everything up-to-date」でも、すでに push 済みのことが多い (`git for-each-ref refs/remotes` で確かめる)。
- **`git push -u` が、`.git/config.lock` (0 バイト、読み取り専用、実行中の git なし) で、upstream の設定だけ失敗することがある** (push 自体は成功。原因は、Claude のサンドボックスの疑い。未確認)。`-u` を付けないか、ユーザーが自分の端末でロックを消す。
- Skill / スクリプト / ホスト側を変えたら、**再配置を案内する** (`install.sh --skills-only`、`copy-host-tools.sh`)。確認の途中で、再配置しない。
- 疑似ウォッチャーの検証と、実機の確認は別。**cmd / ps1 は WSL で実行できない。** 実機の確認は、1 つずつ、結果の**原文**を貼ってもらう (Claude の言い換えは、あてにならない)。UI の確認は、新しいセッションで (Skill の一覧は、起動時に読み込まれる)。
- 作業フォルダーに `.claude` フォルダーがないと、サンドボックスで、すべての Bash が失敗する。消さない。Claude Code を起動するフォルダーの綴りは、書き込み許可の判定に使われる (2.24.4 以降は、綴りが違っても動く)。
- ファイルの形式: `.ps1` は UTF-8 (BOM 付き) + CRLF。`.cmd` は ASCII + CRLF (または CP932)。`.md` / `.sh` / `.py` は UTF-8、LF、BOM なし。`tools/check-formats.sh` で検証できる。
- **(今回の反省) 実機の確認が残る変更は、確認の記録まで終えてから、push を案内する。** v2.28.0 で、コミット直後に push を案内したため、確認の記録が、別の PR (#33) になった。確認 → 記録 → 1 コミット → push の順にする。
- **このセッションのサンドボックスは、`/mnt/c/...` と、メモリのフォルダ (`~/.claude/projects/.../memory/`) に、書き込めない** (`Read-only file system`)。実機のフォルダに、生成物を置くときは、サンドボックス内 (`$TMPDIR`、`/tmp/claude-1000/...`) に作り、ユーザーが `cp` する。**メモリは、更新できないため、古いまま** (「v2.27.0 は PR 待ち」など)。このダイジェストが、正本。
- **`install.sh` (オプションなし) は、Skill とホスト側の両方を配る。** ホスト側のファイル (`watch_and_build.ps1`) を戻しただけでは、**動作中のウォッチャーは、古い版のまま** (起動時に読み込むため)。再配置のあとは、ウォッチャーを再起動する。ホスト側の `VERSION` を書き換えると、`NOTE: 版の不一致` の確認ができる (終わったら `install.sh` で戻す)。
- `package_once.sh` は、`bash` を付けて実行する (v2.29.0 で、実行権限も付けた。SKILL.md の手順は、`bash` 付き)。
- **Markdown の表のセルに `|` を書かない** (`Debug|x64` など)。列が崩れる。`awk` で、各行の `|` の数を数えると、検出できる。
- **`rsync --exclude x64` は、どの階層の `x64` も除外する** (`packages\…\x64` まで)。ソリューション直下だけなら、`--exclude /x64` と、先頭を固定する。
- `git pull` を、サンドボックスで実行すると、ssh の接続が拒否される (`github.com:22`)。`git fetch` / `gh` の読み取りは、`allowed_domains` を付ける。
- 全テスト: `tests/*_test.sh` (26 本)。**2 分を超える。バックグラウンドの実行は、`run_in_background` で、ループを、そのまま (内側に `&` を付けない。付けると、途中で終わる)。** Python の置換には `assert s.count(a)==1`。サンドボックスは、`rm -rf` / `powershell.exe` / `cmd.exe` を実行できない。

## 7. 注意

- `/new-solution` `/new-solutions` `/brainstorm` `/update-from-ideas` `/add-feature` `/ui-test-first` は、`disable-model-invocation: true` (スラッシュコマンドだけを入力して始める)。`ui-design-review` は、自動起動する。
- 実機の候補フォルダー: `c:\Workspace\macsignee\source\repos\ToDo` の `TodoWpf` / `TodoCore` / `TodoMfc` (使い捨てではない)。`wpfsample` は、UG の確認の相手 (UG4b で、`wpfsample.UITests` が作られ、`MainWindow.xaml` の `NameTextBox` に `AutomationProperties.Name="名前"` が入った)。
- `/ui-design-review` の報告は、実行ごとに揺れる。「画面の確認」は、画面を操作したときだけ。OS への追従 (UI-CLR-005 など) は、色指定の有無では判定しない。

## 8. 残作業 (優先順は未決。ユーザーが決める)

**片付いたもの:** 結果の自己記述と版の不一致の検出 (v2.29.0)、v2.27.0 のマージ・再配置・実機確認、UI-LOC-001 の判断 (既定にしない)、MFC の DPI のマニフェスト化 (v2.30.0)、旧 NuGet 方式の廃止 (v2.31.0)、`REMAINING-CHECKS.md` の整理 (PR #39。マージ済み)、HV4 の未確認点の記録。

**未実施 (このセッションで、ユーザーが「また後で指示」とした):**
1. **MFC 拡張 DLL の対応** (未決定。まず、何が問題かを整理して、方針を決める)。関連: `mfc-check` の K4・K5・K6 (REMAINING-CHECKS の保留。「MFC の DLL を、実際に扱うとき、まとめて」と書いてある)、UI-CTL-101 (MFC の DLL のダイアログは、マニフェストをリソース ID 2 で組み込む。静的検査 `UIG-CTL101` は info)。
2. **TG1:** 大きめのテスト (C++ / WPF) での `test_guard` の誤検出の確認。実プロジェクトで、Red の直後に `snapshot` → 何も変えずに `check`。実装側の細工の検査は、見送り (DESIGN 4.43)。
3. **小さく確認** (実機の操作は小さい): **H8** (存在しない `-SolutionPath` で、ウォッチャーを起動)、**WF3** (生成した WinForms を F5 で実行)、**N4** (名前が `Test` で終わるメインの `_Main`。N3 が廃止のため、N3v (vcpkg) の組み合わせに読み替える)。
4. **保留の項目** (`REMAINING-CHECKS.md` の 2-4): G 系・N3a・N3b (source 方式を使うとき)、S 系・A 系・U 系・F 系 (その機能を、実際に使うとき)、K4〜K6 (MFC の DLL を扱うとき)、WC3・WF5・H7・N の各種類 (疑似フォルダでは確認済み)。
5. **「既知の指摘」の質問を、指摘ごとにする** (`ui-test-first`。運用して不都合があれば)。
6. (任意) `/new-solution` が作る `CLAUDE.md` への案内、静的検査の追加。

**確認が要るもの:** 実機で未確認が残る点: NS4 の単一の衝突、TG1・TG3 (△)。

**後始末 (ユーザー):** マージ済みのブランチの削除 (`git branch --merged main`。`tidy-remaining-checks` を含む)。

## 9. 最初にすること (新しいセッション)

1. `git status -sb` と `git log --oneline -3` で、状態を確かめる (この文書は、10-31 の v2.31.0 + PR #39 マージ後の時点。`main` = `24a0259`、VERSION = 2.31.0)。
2. このファイルと、**`docs/REMAINING-CHECKS.md` (未了の項目と、扱い・再開条件の正本)**、`docs/NEXT-STEPS.md` (古い部分がある。最新は、CHANGELOG と TEST-PLAN) を読む。**メモリ (`MEMORY.md`) は、古い** (このセッションでは、書き込めなかった。このファイルを、優先する)。
3. `gh pr list --state all --limit 5` (`allowed_domains: ["api.github.com"]`) で、マージの状況を確かめる。
4. ユーザーに、どれから進めるかを聞く (§8)。
