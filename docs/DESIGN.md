# 設計メモ

このリポジトリの成果物 (ホスト側ツールと Skill) が「なぜこの形か」を残す。
ファイルを読めば分かることは書かず、**判断の理由・取り下げた案・守るべき約束 (契約)** を中心に書く。

## 1. 目的と前提

**目的:** Claude Code (WSL) が、C++ (Visual Studio / MSBuild) のコードを修正し、ビルドとテストを行い、
エラーや失敗を読んで自分で直す、というループを、人手を介さずに回せるようにする。

**制約:** Claude Code は、サンドボックスで動いており、Windows 側の `msbuild.exe` やテスト exe、
開発者用環境変数 (`vcvarsall.bat` など) に直接アクセスできない。

**解決策:** Windows 側に、フラグファイルを監視するウォッチャーを常駐させる。
Claude は、ファイルを置いて、ファイルを読むだけ。ファイルが、両者の唯一の接点になる。

```
Claude Code (WSL)                              Windows
  trigger_build.flag / trigger_test.flag  ──▶  watch_and_build.ps1 (ウォッチャー)
                                               ├─ build-windows.cmd ─▶ MSBuild
                                               └─ (テスト時) xxxTest.exe (GoogleTest)
  build_result.txt / test_result.txt      ◀──  完了マーカー (最後に書く)
  build_error.log  / test_error.log       ◀──  失敗時のみ
```

## 2. 構成と責務

| 部品 | 場所 | 責務 |
|---|---|---|
| `run_watcher.cmd` | host-tools | 入口。引数を整え、ps1 を起動する |
| `watch_and_build.ps1` | host-tools | フラグ監視、ビルド/テスト実行、結果ファイルの書き出し |
| `build-windows.cmd` | host-tools | VS (C++) の環境を読み込み、MSBuild を実行する (単体でも使える) |
| `cpp-auto-build` | skills | ビルドのみのループ (`trigger_build.flag`) |
| `cpp-build-test-loop` | skills | ビルド + GoogleTest のループ (`trigger_test.flag`) |
| `build_once.sh` / `build_test_once.sh` | skills/*/scripts | フラグを置き、完了マーカーを待ち、結果を1行目と終了コードで返す |

ウォッチャーは、`build-windows.cmd` を**毎回別プロセスで**呼ぶ。VS の環境変数が持ち越されず、
Platform や Configuration を変えても環境が汚れない (起動時に1回だけ読み込む方式は、環境が固定されるため不採用)。

## 3. 契約 (ホスト側ツール ⇔ Skill)

すべて `<ソリューションフォルダ>` に置かれる。**これを変えるときは、ホスト側ツールと Skill を同じコミットで直す。**

### ファイル

| ファイル | 作る人 | 内容 |
|---|---|---|
| `trigger_build.flag` | Claude | 空。ビルドのみを依頼 |
| `trigger_test.flag` | Claude | 空。ビルド + テストを依頼 (両方あればこちらが優先) |
| `build_result.txt` | ウォッチャー | `SUCCESS` / `FAILED` (ビルドのみの完了マーカー) |
| `build_error.log` | ウォッチャー | ビルド失敗時のみ。エラー行 |
| `test_result.txt` | ウォッチャー | テストの完了マーカー (後述の値) |
| `test_error.log` | ウォッチャー | テスト失敗・タイムアウト・環境エラー時のみ |
| `.claude-logs/` | ウォッチャー | `build.log` `errors.log` `warnings.log` `test.log` (フルパスのまま) |

### `test_result.txt` の値

| 値 | 意味 | 詳細の場所 |
|---|---|---|
| `PASSED` | ビルド成功・全テスト成功 | |
| `FAILED` | テスト失敗 (または異常終了) | `test_error.log` |
| `TIMEOUT` | テストが制限時間内に終わらない | `test_error.log` (`Hung test ...`) |
| `BUILD_FAILED` | ビルド失敗でテスト未実行 | `build_error.log` |
| `ENV_ERROR` | テスト exe が見つからない、`[  PASSED  ]` が出力にない等 | `test_error.log` |

環境エラーのログの先頭は、必ず `[ENVIRONMENT ERROR - not a source code problem]`。
Skill は、これを見て「ソースもテストも直さずに、報告して止まる」。

### Skill のスクリプトの出力 (1行目と終了コード)

| 1行目 | rc | 意味 |
|---|---|---|
| `PASSED` / `SUCCESS` | 0 | 成功 |
| `FAILED` | 1 | テスト失敗 (`build_once.sh` ではビルド失敗) |
| `BAD_ARGS` | 2 | 引数不正 |
| `WATCHER_NOT_RUNNING` | 3 | フラグが 15 秒回収されない = ウォッチャー未起動 |
| `ENV_ERROR` | 4 | 環境エラー |
| `TIMEOUT` | 5 | 完了マーカーが出ない (既定: ビルド 180 秒、ビルド+テスト 300 秒) |
| `BUILD_FAILED` | 6 | ビルド失敗 (`build_test_once.sh` のみ) |
| `TEST_TIMEOUT` | 7 | ホスト側のテストの制限時間超過 (`build_test_once.sh` のみ) |

### `build-windows.cmd` の終了コード
`0` 成功 / `1` ビルド失敗 / `2` 引数不正 / `10` vswhere なし / `11` VS (C++) なし /
`12` VsDevCmd なし / `13` VsDevCmd 失敗 / `14` cl.exe か MSBuild.exe が PATH にない

## 4. 設計判断とその理由

### 4.1 フラグファイル方式
Claude が、Windows 側のコマンドを直接実行できない以上、「共有フォルダ上のファイルを介する」以外の
手段は、実質的にない。ホストから Claude へ通知を送る標準の仕組みもない。
そのため、Claude 側が、完了マーカーの出現を待つ (ポーリング) 方式にした。

### 4.2 完了マーカーを別に用意した
「フラグが消えた」は「ビルドを開始した」だけで、終わったとは限らない。
「`build_error.log` がない」は、成功か、まだ実行中かの区別がつかない。
そこで、ウォッチャーが、**結果ファイルとエラーログを書いた後に、最後にマーカーを書く**。
マーカーが現れた時点で、ログは必ず読める状態にある。

### 4.3 待機で、トークンを消費しない
待機は、`build_once.sh` / `build_test_once.sh` の中の `sleep` ループで行う (1回のコマンド)。
Claude 側から、何度もファイルを読みに行く方式は、ターンとトークンを消費するため不採用。
Bash ツールの既定タイムアウト (120 秒) より長く待つため、`run_in_background: true` で実行する。
**待機中は、ファイルを読まない・再実行しない** (前回の古い結果を読んで誤判断したため。Skill に明記)。

### 4.4 結果ファイルは、毎回、実行の開始時に消す
古い結果の誤読を防ぐ。スクリプト側 (Claude の実行前) と、ウォッチャー側 (ビルド開始時) の両方で消す。
ただし、実行が重なると (前の実行が終わる前に、次のフラグを置く) 古い結果を拾う可能性が残る。
→ **未対策。** フラグに一意の ID を書き、ウォッチャーが結果に書き戻す案があるが、実装していない。
Skill で「実行中に再起動しない」と規定して、回避している。

### 4.5 `PASSED` の判定を厳しくした
古い GoogleTest は `--gtest_brief` を知らず、ヘルプだけを表示して**終了コード 0** で終わる。
テストが1件も走らないのに `PASSED` になった実例がある。
→ 終了コード 0 **かつ** 出力に `[  PASSED  ]` の行がある場合だけ成功とみなす。
なければ `ENV_ERROR`。`-TestArgs` の既定は `--gtest_color=no` のみ。

### 4.6 エラーログのパスを、相対パスにする
MSBuild と GoogleTest は、絶対パス (`C:\...`) で出力する。WSL の Claude は、そのままでは開けず、
変換にトークンと誤りの余地がある。ウォッチャーが、ソリューションフォルダ以下を、
`xxx/yyy.cpp(49)` の形 (相対・`/` 区切り) に変換して、`build_error.log` / `test_error.log` に書く。
フルパスの詳細ログは `.claude-logs/` に残る。

### 4.7 テスト失敗の扱い (Skill の方針)
テストは、仕様の表明として扱う。
- 原則として、**ソース (xxx) 側を直す。**
- テストの期待値が誤りと思われる場合は、**変更前にユーザーに確認する** (根拠を添える)。
- テストの削除、`DISABLED_` 化、`GTEST_SKIP()`、アサーションを弱める、許容誤差を広げる、
  期待値を実装の出力に合わせる、は、許可なしにしない。
- 複数の失敗は、共通の原因を先に探す (1つの不具合が、複数のテストを落とすことが多い)。
- `ENV_ERROR` では、ソースもテストも触らない。

### 4.8 テストのタイムアウト
テスト exe は、制限時間 (既定 120 秒) で、子プロセスごと強制終了する (`taskkill /T /F` + `Process.Kill()`)。
待ち時間にも上限を付けた (無期限に待つと、ウォッチャー全体が止まる)。
タイムアウト時は、`[ RUN ]` だけで `[ OK ]` が続かなかったテストを、`Hung test` として先頭に出す。
**ただし、制限時間が、全体の実行時間より短いだけの場合も、通常のテスト名が出る。**
Skill は、「直前にソースを変更していない場合、または2回続けて `TEST_TIMEOUT` の場合は、直さず報告して止まる」。

### 4.9 クイック編集モードの無効化
コンソール内をクリックすると、出力が一時停止し、ウォッチャーが止まる (Enter/Esc で再開)。
実際に、ビルドが数分止まった。起動時に、`SetConsoleMode` で無効化する (失敗しても監視は続ける)。

### 4.10 ビルド順 (xxx → xxxTest)
`xxxTest` が `xxx` をプロジェクト参照していれば、ソリューションのビルドで、MSBuild が依存順に解決する。
Skill は、順序を指定しない。参照がない構成は、対象外。

### 4.11 GoogleTest のみ対応
MSTest (C++ ネイティブ) は、テストが DLL で、`vstest.console.exe` で実行する別方式になる。
ホスト側の、実行 (`Invoke-TestExe`) と抽出 (`Select-TestFailureLines`) が関数に分かれているので、
将来、追加できる構造にしてあるが、現在は未対応。

### 4.12 プレビュー版 VS は、対象外
`vswhere` に `-prerelease` を付けない。リリース版の最新だけを使う。

## 5. ファイル形式

| ファイル | 文字コード | 改行 | 理由 |
|---|---|---|---|
| `*.cmd` | CP932 (Shift_JIS)、BOM なし | CRLF | 日本語のコメントを入れるため。Windows のバッチの流儀 |
| `*.ps1` | UTF-8、**BOM あり** | CRLF | Windows PowerShell 5.1 は、BOM がないと CP932 と解釈し、日本語が化ける |
| `*.sh` | UTF-8、BOM なし | **LF** | CRLF では bash で動かない |
| `*.md` | UTF-8、BOM なし | LF | |

- `.cmd` の画面メッセージ (`echo`) は、文字化けを避けるため、英語 (ASCII) のまま。
- `.cmd` の `rem` 行には、`|` や行末の `^` と同じ値の2バイト目を持つ文字 (「ポ」など) を使わない
  (ほかのコードページで実行されたとき、コマンドとして解釈される恐れがあるため)。
  `rem` の中の `&` も使わない。`( )` のブロックの中には、`rem` を書かない。
- `.gitattributes` で、`.cmd` / `.ps1` は `-text` (git の自動変換を無効)、`.sh` / `.md` は `eol=lf`。
  検証は `tools/check-formats.sh`。`install.sh` は、コピー前に必ず、これを実行する。
- `.cmd` の差分を読めるようにするには、クローンごとに、次を設定する。
  ```bash
  git config diff.cp932.textconv "iconv -f cp932 -t utf-8"
  ```

## 6. 既知の制限と、検証範囲

**検証済み** (実機): VS 2026 Enterprise、x64 / Debug、GoogleTest、`.sln`。
どの項目を実機で確認し、どれが未確認かは、`docs/TEST-PLAN.md` の「状況」列を参照。

**未確認:** `Win32` / `ARM64`、`Release`、`.slnx` での、フラグ経由の実行。
**未対応:** MSTest、複数プロジェクトの同時監視 (別ウィンドウで、別のウォッチャーを起動する)。
**未対策:** 実行が重なったときの、古い結果の誤読 (4.4)。

## 7. 取り下げた案 (再び提案しないために)
- **`--gtest_brief=1` を既定の引数にする:** 古い GoogleTest で、ヘルプだけが出て、成功と誤判定された。
- **VS の環境を、ウォッチャー起動時に1回だけ読み込む:** Platform を切り替えられない。毎回別プロセスにした。
- **ps1 に、VS 検出を持たせる:** すでに動作確認済みの `build-windows.cmd` と、二重の実装になるため、バッチに集約した。
- **プレビュー版 VS の対応 (`VC_INCLUDE_PRERELEASE`):** 不要と判断して削除。
- **テストの作業フォルダを `%TEMP%` にする:** プロジェクトのフォルダ基準の相対パスで、データを読むテストが、失敗する恐れがある。
  既定は、テスト exe のフォルダ。必要なら `-TestWorkingDir` で指定する。
