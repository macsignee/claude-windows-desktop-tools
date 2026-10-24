# 次の作業 (再開用メモ)

2026-10-24 時点。C++ と WPF の統合 (v2.4.x〜v2.5.6) の実機の確認は、**WS10 (保留) を除いて、完了した**。
各項目の状況は `docs/REMAINING-CHECKS.md`、手順と結果は `docs/TEST-PLAN.md` (「状況の一覧」)。以前の版の、手順と依頼文は、git の履歴 (`docs/NEXT-STEPS.md`、2026-10-21 まで) にある。

## 残り

1. **WS10 (保留):** VS で、WPF アプリ + クラスライブラリの `.sln` を作り、`add_project.py` でライブラリ + テストを追加して、VS で開く。
2. **省略した項目 (任意):** U14c の (a)、U16 の C++ 側、WS8 の F5。
3. **以前の版 (v2.0.0〜v2.3.0) の、未確認の項目:** C++ / MFC の、GoogleTest のソース取得 (G3 / G6 / G7 / G8) と、Skill (S / A / N / U / F / K 系)。ホスト側ツール (H4、T8、T9、R 系、M 系) は、2026-10-24 に確認済み。`docs/REMAINING-CHECKS.md` の 3.。

## main へのマージの前に

- push は、ユーザーが行う (`git push -u origin unify-dotnet`)。マージも、ユーザーが決める。
- 変更の一覧は、`CHANGELOG.md` の 2.4.x〜2.5.6 (ブランチ `unify-dotnet`、main から 20 コミット先)。
- 配置: `./install/install.sh` (Skill・規約。`--skills-only` / `--rules-only` / `--host-only`)、`~/src/copy-host-tools.sh` (ホスト側ツール)。**Skill やスクリプトを変えたら、再配置を忘れない** (確認のやり直しの、最大の原因だった)。

## 前提 (docs/DESIGN.md 1.)

デバッグは VS で行う。ビルドする PC には、C++ ワークロード入りの VS がある。C++ / .NET のツールがない環境では、「Visual Studio Installer で、手で追加」と案内する (自動では追加できない)。
