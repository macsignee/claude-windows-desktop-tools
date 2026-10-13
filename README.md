# cpp-claude-build-tools

Claude Code (WSL) が、Windows 側の Visual Studio (C++) で、**ビルドと GoogleTest を実行し、エラーや失敗を自分で直す**ためのツール一式。
テストを先に書いて Red を確認し (`cpp-test-first`)、実装して Green にする (`cpp-build-test-loop`) という、TDD の流れにも使える。

Claude Code のサンドボックスからは、Windows 側の MSBuild やテスト exe を直接実行できない。
そこで、Windows 側にウォッチャーを常駐させ、Claude は、フラグファイルを置いて結果ファイルを読むだけにしている。

```
Claude Code (WSL)  ──trigger_*.flag──▶  Windows: watch_and_build.ps1 ─▶ MSBuild / テスト exe
                   ◀──*_result.txt / *_error.log──
```

## 構成

| フォルダ | 内容 | 配布先 |
|---|---|---|
| [`host-tools/`](host-tools/) | ウォッチャー (`watch_and_build.ps1`)、起動用 (`run_watcher.cmd`)、ビルド用 (`build-windows.cmd`)。**3 ファイルは同じフォルダに置く** | Windows 側の任意のフォルダ (例: `C:\tools\cpp-watcher\`) |
| [`skills/`](skills/) | Claude Code の Skill: `cpp-auto-build` (ビルドのみ)、`cpp-build-test-loop` (ビルド + テスト、Green)、`cpp-test-first` (テストを先に書き、Red を確認)、`brainstorm` (`/brainstorm`: 壁打ちで仕様を固める)、`add-feature` (`/add-feature`: 計画 → 承認 → テスト先行 → 実装 → 検証)、`update-from-ideas` (`/update-from-ideas`: アイデアを正式な仕様書へ反映) | `~/.claude/skills/` (WSL) |
| [`docs/`](docs/) | [設計メモ](docs/DESIGN.md) (契約・設計判断・取り下げた案)、[テスト手順書](docs/TEST-PLAN.md)、[推奨する Claude Code の設定](docs/RECOMMENDED-SETTINGS.md) (テストファイルの編集と `git commit` に、確認を付ける) | |
| [`tools/`](tools/) | `check-formats.sh`: 文字コード・改行・BOM の検証 | |
| [`tests/`](tests/) | `fake_watcher_test.sh`: Skill のスクリプトを、疑似ウォッチャーで検証。`add_layer_test.sh`: `cpp-test-first` のプロジェクト生成を、疑似ソリューションで検証 (どちらも Windows 不要) | |
| [`install/`](install/) | `install.sh`: 配布先へコピーする (バイトを変えない) | |

使い方 (ウォッチャーの起動、引数、トラブルシューティング) は、[`host-tools/README.md`](host-tools/README.md)。

## 配布 (インストール)

WSL のターミナルで、リポジトリのルートから実行する。

```bash
install/install.sh --dry-run        # 何をコピーするかだけ表示する
install/install.sh                  # Skill -> ~/.claude/skills、ホスト側ツール -> /mnt/c/tools/cpp-watcher
```

- コピー前に、`tools/check-formats.sh` で形式を検証し、違反があれば中止する。コピー後に、`cmp` で同一性を確認する。
- 配布先は、**コピー先であって、編集する場所ではない。** 直すときは、このリポジトリを直して、配り直す。
- Skill を読み込ませるには、Claude Code のセッションを、新しく起動する。
- 配布先を変えるには、`--skills-dir DIR` / `--host-dir DIR`。

## ファイル形式 (重要)

文字コードと改行が崩れると、動かなくなる。`.gitattributes` で、git の自動変換を無効にしている。

| ファイル | 文字コード | 改行 |
|---|---|---|
| `*.cmd` | **CP932 (Shift_JIS)**、BOM なし | CRLF |
| `*.ps1` | UTF-8、**BOM あり** | CRLF |
| `*.sh` / `*.md` | UTF-8、BOM なし | **LF** |

- `.cmd` を、UTF-8 のエディタで開いて保存し直さない。編集するときは、CP932 を扱えるエディタを使う。
- 変更したら、必ず `tools/check-formats.sh` を実行する。
- `.cmd` の差分を読めるようにする (クローンごとに、1回):
  ```bash
  git config diff.cp932.textconv "iconv -f cp932 -t utf-8"
  ```

## 開発の進め方

- **このリポジトリが原本。** 作業コピーは、1 つの OS の git だけで扱う (WSL 側に置く)。同じフォルダを、Windows の git と WSL の git の両方で操作しない。
- 契約 (ファイル名・結果の値・終了コード) を変えるときは、ホスト側ツールと Skill を、**同じコミット**で直す。[`docs/DESIGN.md`](docs/DESIGN.md) の「契約」も更新する。
- 変更したときの、最低限の確認は、[`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の「変更したときの、最低限の確認」。
- 変更したら、`VERSION` と `CHANGELOG.md` を更新する。

## 対応範囲

- テスト: **GoogleTest のみ** (MSTest などは未対応)。
- 検証済み: VS 2026 Enterprise、x64 / Debug。詳細は [`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の「状況」列。
- 1 つのウォッチャーは、1 つのプロジェクトと 1 つの Platform/Configuration 専用。
