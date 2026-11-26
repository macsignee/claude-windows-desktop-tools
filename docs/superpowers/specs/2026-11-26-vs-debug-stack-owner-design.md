# 設計: `vs-debug` の、フレームの所有者の判定 (原因が、こちらか、外のライブラリか)

作成: 2026-11-26。状態: 草稿 (ユーザーの承認待ち)。規模: 小〜中 (ホスト側の小さな変更 + Skill 側のスクリプト)。

## 1. 目的と、その理由
別のソリューションでビルドされたライブラリ (静的ライブラリ、DLL とヘッダー、アセンブリ。日次でビルドされ、共有フォルダに置かれる) を使うソリューションで、不具合が起きたとき、**原因が、外のライブラリにあるのか、こちらのコードにあるのかを、切り分けたい**。

切り分けは、静的な検査 (`mfc-check` など) ではなく、**デバッグ (`vs-debug`) で行う** (ユーザーの決定、2026-11-26)。モジュールの境界をまたぐ原因は、実行時の証拠 (スタック、引数の値) が要るため。外のソースに対する静的チェック、境界の静的な検査は、将来の話にする。

## 2. ゴール・非ゴール・アンチゴール
**ゴール**
- (G1) `vs_once.sh --inspect` の `STACK:` の各フレームに、**所有者の印** (`ours` / `ext` / `sys` / `unknown`) が付く。
- (G2) **要約の行**が付く: 上から見て、最初の `sys` でないフレームの所有者 (`OWNER:`)、`ours` が `ext` を呼んでいる境界 (`BOUNDARY:`)。
- (G3) `--frame N` で、**そのフレームを選んで** `LOCALS:` と `--eval` を読める (境界で、こちらが、何を渡したか)。
- (G4) 静的ライブラリ (exe に取り込まれ、モジュールがこちらの exe になる) の関数も、正しく `ext` と判定できる。
- (G5) 日次の配布で、PDB とソースを揃える運用を、Skill に書く。

**非ゴール**
- 静的なチェックを、外のソースに広げること (将来)。
- 「どちらのコードが誤っているか」の、断定。印と要約は、**見当 (ヒント)** にすぎない (こちらが誤った引数を渡して、外の中で落ちるときも、`OWNER: ext` と出る)。
- `wpf-check` / `winforms-check` への展開 (将来)。

**アンチゴール**
- 外のライブラリを、こちらと誤判定して、「こちらのバグ」と、思い込ませること。分からないときは、`unknown` にする。
- `--frame` が、VS の画面の選択状態を、変えたまま残すこと (読んだら、元に戻す)。

## 3. 調べて分かったこと
- 現在の `STACK:` は、`#i 関数名 at ファイル:行` だけで、**モジュールが出ない**。VS のスタック フレーム (`EnvDTE.StackFrame`) は `Module` を持つ。`FileName` / `LineNumber` は、すでに使っている。
- 静的ライブラリの関数は、モジュール (exe) では見分けられない。**ソースファイルのパス**で見分ける (こちらのソースか、ほかの場所のソースか)。
- `vs_once.sh` は、ウォッチャーが書いた `vs_output.txt` を、そのまま整形して出す。結果の終わりに `SOLUTION: c:\...\X.slnx` (Windows のパス) が出る。

## 4. 検討した案
- **A. 判定は、WSL 側の Python (Skill のスクリプト)。ホストは、事実 (モジュール) を出すだけ** (採用): 判定の規則を、WSL で、単体テストできる (WSL には `pwsh` がない)。規則の変更に、ホストの再配布が要らない。
- B. 判定を、すべて PowerShell (ホスト) に書く: WSL でテストできない。規則を直すたびに、再配布とウォッチャーの再起動。不採用。
- C. 別のツール・Skill にする: `--inspect` の出力と、二重になる。不採用。

## 5. 設計
### 5-1. ホスト側 (`host-tools/lib/vs-ide.ps1`。`HOST_VERSION` を上げる)
- `Get-VsInspectLines` の `STACK:` の行の末尾に、`[module=<Module の値>]` を足す (`Module` が取れなければ、足さない)。それ以外は、今のまま。
- 操作 `frame <N>` を足す (`inspect` と `eval` の前に置く): `CurrentThread.StackFrames` の N 番目を `Debugger.CurrentStackFrame` に設定する。N は 0 以上の整数。範囲外は `FRAME_OUT_OF_RANGE: <N> (frames: <件数>)` で失敗。**実行の最後に、元のフレームに戻す** (`finally`)。選んだら、`FRAME: #N <関数> at <ファイル>:<行>` の行を出す。
- `frame` は、ブレークで止まっているときだけ (止まっていなければ `FRAME_SKIP:`)。`--step` / `--continue` / `--pause` / `--debug` とは併用しない (`vs_once.sh` が `BAD_ARGS`)。

### 5-2. Skill 側 (`skills/vs-debug/scripts/`)
- `vs_once.sh`: `--frame <N>` (0〜99。`--inspect` か `--eval` が必要。`--step` / `--continue` / `--pause` / `--debug` と併用不可)。フラグに `frame <N>` の行を、`eval` / `inspect` の前に書く。
- 新規 `stack_owner.py`: `vs_output.txt` の `STACK:` の行を読み、所有者の印と要約を足して出す。`vs_once.sh` が、`show "$OUTFILE"` の代わりに、通す (`STACK:` の行がなければ、そのまま)。
  - 出力の形: `STACK: #0 [ours] GreetingDialog::OnClear at …\\GreetingDialog.cpp:54` (モジュールがあれば、行の末尾に ` (<module>)`)。`STACK:` の行の後に、`OWNER: top=ours (frame #0)` と `BOUNDARY: none` (または `BOUNDARY: #3 ours -> ext #2`)。

### 5-3. 判定の規則 (`stack_owner.py`。順に見る)
1. **ソースファイルのパスがあるとき**:
   - ソリューションのフォルダの下 (`SOLUTION:` の行から求める。大文字小文字は区別しない) → `ours`
   - システム・VS・MFC・CRT のパス (`\Windows\`、`\Microsoft Visual Studio\`、`\Windows Kits\`、`\VC\Tools\MSVC\`、`\atlmfc\`、`\vctools\`、`\ucrt\`、`\minkernel\`、`\onecore\`、`\dotnet\`、`\Microsoft.NET\`) → `sys`
   - それ以外 → `ext`
2. **ソースがないとき (シンボルなし)**: `[module=...]` で判定。システムのモジュール名 (`ntdll`・`kernel32`・`kernelbase`・`user32`・`ucrtbase`・`vcruntime*`・`msvcp*`・`mfc*`・`atl*`・`System.*`・`Microsoft.*`・`Presentation*`・`WindowsBase` など) か、パスがシステムの場所 → `sys`。パスがソリューションの下 → `ours` (ソースなし)。**それ以外の名前だけで、パスが分からない → `unknown`**。
3. 関数名も、ファイルも、モジュールもない → `unknown`。
4. **`OWNER:`**: 上 (#0) から見て、最初の `sys` でないフレーム。`unknown` なら `unknown`。全部 `sys` なら `sys`。
5. **`BOUNDARY:`**: `sys` のフレームを飛ばして、上から見て、**最初の「`ext` を、`ours` が呼ぶ」組** (呼ぶ側が `ours`、呼ばれる側が `ext`)。なければ `none`。`unknown` を挟むときは、境界とは断定せず、`BOUNDARY: unknown (frame #n has no symbols)`。
6. 表示は、`STACK:` の既存の上限 (10 フレーム) の中だけを対象にする。

## 6. 文書 (`vs-debug/SKILL.md`)
「原因が、こちらか、外のライブラリか」の節を足す:
1. `vs_once.sh "$SLN_DIR" --inspect` で、`OWNER:` と `BOUNDARY:` を読む。
2. 境界があれば、`--frame <呼ぶ側の番号> --inspect` / `--eval` で、こちらが、外に何を渡したかを読む。引数が、不正なら、こちらの責任の見当。正しいのに、外の中で落ちるなら、外の責任の見当。
3. **ヒントであり、断定ではない**ことを、書く。
4. 日次の配布の運用: 番号つきフォルダに、バイナリ・PDB・ソースを揃える。**番号を見ない運用なら、PDB とソースの世代が、バイナリと揃っているかを、確かめる** (揃っていなければ、シンボルが読み込まれず、`ext` ではなく `unknown` と出る)。.NET は `EmbedAllSources`、C++ の静的ライブラリは `/Z7`、`/ZH:SHA_256`。VS の「デバッグ ソース ファイル」と「シンボル」の設定 (ユーザー単位)。

## 7. 制約
- WSL には `pwsh` も `dotnet` もない。ホスト側 (PowerShell) は、静的な確認だけ。判定の規則 (Python) は、WSL で単体テストする。
- マージは、ユーザーが行う。ホスト側を変えるので、`HOST_VERSION` と `VERSION` を上げ (2.107.0)、再配布 (`--host-only` と `--skills-only`) とウォッチャーの再起動が要る。
- テストを先に書く。

## 8. ビルダーに任せること
- `Module` プロパティが返す値 (名前か、パスか) は、実機で確かめて、判定の細部を合わせる (パスが取れなければ、規則 2 のとおり、名前で判定)。
- フレームの選択と復元の COM の呼び方、`FRAME_OUT_OF_RANGE` などの文言。

## 9. 私 (Claude) の判断として決めたこと (確認してほしい)
- 判定は、WSL 側の Python (案 A)。
- 所有者の語は `ours` / `ext` / `sys` / `unknown`、要約の行は `OWNER:` / `BOUNDARY:`、選択の行は `FRAME:`。
- `--frame` は、読み取りの直前だけ選び、最後に元に戻す。`--step` などとは併用不可。
- 名前だけでパスが分からないモジュールは、`ext` ではなく `unknown` (誤判定を避ける)。
- 版は 2.107.0。

## 10. 実機での確認 (完了の条件)
確認用に、**ソリューションの外**にある小さな DLL (外のライブラリ役) と、それを使う MFC のアプリを用意する (ユーザーの作業)。
1. 外の DLL の関数の中で止める: `STACK:` に、`[ours]` と `[ext]` と `[sys]` が混ざり、`OWNER: top=ext`、`BOUNDARY: #… ours -> ext #…` が出る。
2. `--frame <呼ぶ側>` で、こちらの関数の `LOCALS:` が読め、実行後、VS の選択が元のフレームに戻る。
3. 静的ライブラリ (外のソースをビルドして、取り込んだもの) の関数が、`ext` になる (モジュールは、こちらの exe)。
4. PDB がない外の DLL は、`unknown` (または `sys` でない) になり、`ours` にならない。
5. 通常の `--inspect` (ブレーク中の、今までの使い方) が、変わらず動く。
