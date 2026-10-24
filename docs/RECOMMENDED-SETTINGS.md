# 推奨する Claude Code の設定 (テストファイルの編集と、コミットの確認)

このツールは、Claude が編集したコードを、Windows 側で、ビルドして、テストを実行する (`docs/DESIGN.md` の 1 章)。
そのため、**Claude が、テストファイルを、意図せず変更すること** (テストを、通るように書き換える、など) を、人が、見逃さない仕組みが、重要になる。

**Skill の本文だけでは、強制できない。** Skill は、モデルへの指示であり、守られる保証がない。
確実に、確認を挟むには、Claude Code の設定 (`settings.json`) の、権限 (`permissions`) を使う。

## 1. 3 つの層

| 層 | 強制力 | 場所 | 内容 |
|---|---|---|---|
| **1. Skill の本文** | 弱い (指示) | `skills/*/SKILL.md` の「完了時の確認」 | 完了時に、変更したファイルを報告する。テストファイルの変更を、冒頭で明示する。コミットしない。**実装済み** |
| **2. 権限設定 (推奨)** | **強い** (ツールの実行前に、確認が出る) | プロジェクトの `.claude/settings.json` | テストファイルの編集と、`git commit` に、確認 (`ask`) を付ける。**この文書の主題** |
| 3. フック | 強いが、失敗時は素通り | `.claude/settings.json` + スクリプト | 確認の理由に、詳細を載せる。**採用しない** (4 章) |

## 2. 設定の例 (層 2)

プロジェクトの `.claude/settings.json` (コミットして、チームで共有できる) に、次を入れる。

```json
{
  "permissions": {
    "ask": [
      "Edit(**/Test*.cpp)",
      "Edit(**/Test*.h)",
      "Edit(**/*Test/**)",
      "Bash(git commit *)"
    ]
  }
}
```

| ルール | 対象 |
|---|---|
| `Edit(**/Test*.cpp)` / `Edit(**/Test*.h)` | テストのソースとヘッダー (`TestGeometry.cpp`、`TestWindowFixture.h` など) |
| `Edit(**/*Test/**)` | テストプロジェクトのフォルダ全体 (`MyAppTest/` 配下。`.vcxproj` や `packages.config` を含む) |
| `Bash(git commit *)` | コミット。通常も確認が出るが、別の設定で、許可されていても、確認を残すため |

- プロジェクトの命名規則 (`Test*.cpp`、`*Test/`) に、合わせて、パターンを調整する。

### .NET (WPF + MSTest) を含むプロジェクトの設定 (v2.0.0 で追加)
.NET のテストは、`*.Tests/` のフォルダに、`*Tests.cs` で置く習慣が多い。C++ 用のパターン (`**/*Test/**`) は、`MyApp.Tests/` に、**一致しない** (末尾が `Tests` のため、`*Test` に合わない)。**.NET 用のパターンを、足す。** あわせて、ビルドの生成物の編集を禁止 (`deny`) する。

```json
{
  "permissions": {
    "ask": [
      "Edit(**/Test*.cpp)",
      "Edit(**/Test*.h)",
      "Edit(**/*Test/**)",
      "Edit(**/*Tests/**)",
      "Edit(**/*.Tests/**)",
      "Edit(**/*Tests.cs)",
      "Edit(**/*Test.cs)",
      "Edit(**/*.csproj)",
      "Edit(**/Directory.Build.props)",
      "Edit(**/Directory.Packages.props)",
      "Edit(**/global.json)",
      "Edit(**/*.runsettings)",
      "Bash(git commit *)"
    ],
    "deny": [
      "Edit(**/obj/**)",
      "Edit(**/bin/**)",
      "Edit(**/*.g.cs)",
      "Edit(**/*.g.i.cs)",
      "Edit(**/packages.lock.json)"
    ]
  }
}
```

| ルール | 対象と理由 |
|---|---|
| `Edit(**/*Tests/**)` `Edit(**/*.Tests/**)` `Edit(**/*Tests.cs)` `Edit(**/*Test.cs)` | .NET のテストプロジェクトとテストコード。**MSTest では、`[Ignore]` の付与、`Assert.Inconclusive`、アサーションの弱め、`[Timeout]` の延長が、`Edit` で行われる。** 人が見逃さないための `ask` |
| `Edit(**/*.csproj)` `Edit(**/Directory.Build.props)` `Edit(**/Directory.Packages.props)` `Edit(**/global.json)` | **対象フレームワーク、パッケージ、SDK、警告の扱い (`NoWarn` / `TreatWarningsAsErrors`)。** ビルドを通すために、警告の抑制や SDK の変更が、紛れ込むのを防ぐ (`ask`)。**テストプロジェクトに、`.cs` を足しても、`.csproj` の編集は不要** (SDK 形式は、ファイルを自動で含める) ので、確認が出る頻度は、高くない |
| `Edit(**/*.runsettings)` | テストの実行設定 (除外、タイムアウト)。テストを実行から外す抜け道になる |
| `deny` の `obj/` `bin/` `*.g.cs` `*.g.i.cs` | **XAML のコンパイルの生成物 (`*.g.cs`) と、ビルドの出力。** 編集しても、次のビルドで上書きされる。`XDG` / `MC` のエラーの修正は、元の `.xaml` / `.cs` に対して行う |
| `deny` の `packages.lock.json` | NuGet のロックファイル。手編集の禁止 (復元で更新する) |

### パッケージの追加 (`add-package`) の設定 (v2.2.0 で追加)
パッケージの追加は、**供給網への入口**になる (紛らわしい名前の混入、意図しないバージョン)。Skill の規則 (「追加する前に確認する」) は、指示にすぎないので、**実行そのものに、確認を付ける。**

```json
{
  "permissions": {
    "ask": [
      "Bash(*package_once.sh*)",
      "Edit(**/vcpkg.json)",
      "Edit(**/*.vcxproj)",
      "Edit(**/ThirdParty.manifest)",
      "Bash(*cpp_pkg.py*)"
    ]
  }
}
```

| ルール | 対象と理由 |
|---|---|
| `Bash(*package_once.sh*)` | **ホスト側で、NuGet / vcpkg / GitHub のソースを取得する操作。** `search` / `versions` だけでも、確認が出る (頻度が高くて煩わしければ、`nuget search` を含む呼び出しだけ、`allow` にする。ただし、`allow` は `ask` より弱い (評価の順序は deny → ask → allow) ので、`ask` と、同じパターンには、書かない) |
| `Edit(**/vcpkg.json)` `Edit(**/ThirdParty.manifest)` | 依存関係の宣言と、取得したソースの記録。バージョンと名前を、人が見る |
| `Edit(**/*.vcxproj)` | `cpp_pkg.py setup` / `include-dir` が書き換える。**ただし、`cpp_pkg.py` は、別のプロセスが書くので、`Edit` のルールは効かない** (上の 3 章の限界)。**そのため、`Bash(*cpp_pkg.py*)` にも、`ask` を付ける** |
| `Bash(*cpp_pkg.py*)` | `vcpkg.json` と `.vcxproj` の編集のスクリプト |

- **`ask` は、許可すれば実行される。** 確認で、**パッケージ名とバージョンが、依頼したものと一致するか**を見る。コミットの前に、`git diff` で、`.csproj` / `Directory.Packages.props` / `vcpkg.json` の差分も見る。
- **C++ のパッケージは、ソースからビルドされ、ビルドスクリプトが、Windows 側で実行される。** 信頼できないポートを入れると、ビルド中に、任意のコードが走る。vcpkg の登録 (`builtin-baseline`) の、公式のポートだけを使う運用を、勧める。
- `fetch` は、**GitHub のタグのソースを置くだけで、ビルドしない** (`.vcxproj` に足すまで)。ただし、置かれたソースは、そのあと、ビルドされる。
- **このパターンの、実機での確認は、未実施。**

- **C++ と .NET の混在のソリューションは、両方のパターンを、合わせる** (上の例のとおり)。**`ask` と `deny` は、配列がマージされる。** 既存の設定を、置き換えずに、追記する。
- **`Edit(**/*.csproj)` の `ask` は、`/new-solution` や、テストの後付けの、`.csproj` の生成でも、出る** (正常な動作)。
- `deny` は、Skill のスクリプトや `dotnet` / `msbuild` が、生成物を書くのを防がない (4.3 の限界の、`Edit` のルールが効く範囲と、同じ)。**Claude の `Edit` / `Write` による編集だけが対象。**
- **このパターンの、実機での確認は、未実施** (TEST-PLAN の S9 / S10 を、.NET のファイルで繰り返す)。
- **すでに `.claude/settings.json` がある場合は、置き換えずに、`permissions.ask` の配列に、追記する** (既存の `allow` / `deny` は、そのまま保つ)。

### 公式ドキュメントで確認した、仕様 (2026-10-13 の調査)
- パスのルールは、`Edit(...)` と書く。**`Edit` のルールは、`Write`、`MultiEdit`、`NotebookEdit` にも、効く** (`Write(...)` などのパスのルールは、無視される)。
- 評価の順序は、**`deny` → `ask` → `allow`**。`ask` は `allow` より優先される。自動承認のモード (`acceptEdits`) でも、`ask` に一致したものは、確認が出る。
- `ask` と `deny` は、ワークスペースの信頼ダイアログの承認に関係なく、効く (`allow` とフックは、承認後に有効になる)。
- `**/` で始めると、WSL のパス (`/mnt/c/...`) の違いを、吸収できる。
- 設定の優先順位 (高い順): 管理者 (managed) → `--settings` → `.claude/settings.local.json` → `.claude/settings.json` → `~/.claude/settings.json`。
  配列は、マージされる。管理者の `deny` と `ask` は、下位の設定で、上書きできない。

## 3. 限界 (必ず理解しておくこと)

| 限界 | 内容 |
|---|---|
| **ask は、許可すれば、編集される** | 確認が出るだけで、編集を、禁止するものではない。確認で、内容を、見てから、許可する運用が前提 |
| **別のプロセスが、ファイルを書く場合は、防げない** | `Edit` のルールが効くのは、Claude の組み込みのファイル編集と、認識できるコマンド (`sed`、`tee`、リダイレクトなど)。`python script.py` のように、別のプログラムが、ファイルを書く場合は、効かない。OS のレベルで防ぐには、サンドボックスが必要。**サンドボックスは、Bash にだけ効き、Read / Edit / Write のツールには効かない** |
| **確認が、2 回出ることがある** | テストの期待値が、誤りの場合、Skill の方針で、Claude が、先にユーザーに確認する。承認後の編集で、権限の確認が、もう一度出る |
| **管理者の設定が、優先される** | 管理者 (Enterprise) の設定に、同じ種類の規則があると、そちらが優先される (`deny` と `ask` は、上書きできない) |
| **ビルドが、テストファイルを使う** | このツールのウォッチャーは、テストファイルを、そのまま、ビルドして実行する。**確認を、すり抜けた変更は、Windows 側で、そのまま実行される** |

だから、**層 1 と層 2 に加えて、コミットの前に、人が、`git diff` で、変更を、確認する運用**が、最後の砦になる。

## 4. フックを採用しない理由 (検討した結果)
フック (`PreToolUse`) で、確認の理由に、詳細を載せる方法も、検討した。次の理由で、採用していない。
- **フックが、タイムアウトや、クラッシュした場合は、ブロックされず、通常の権限の流れに進む** (失敗時に素通り)。強制には、`permissions` が、確実。
- 確認のダイアログに、理由の文字列が、表示されるかは、**公式ドキュメントで、未確認**。
- 「作業の完了時に、`git diff` を、確認させる」公式の仕組みは、ない (`Stop` フックは、Claude の作業を、続けさせる仕組みで、表示の仕組みではない)。
- Skill の frontmatter に `hooks` を書くことはできるが、**有効な範囲が、Skill の実行中だけではなく、セッションの終わりまで**になる。Skill で、権限を、制限 (`deny`) することも、できない。

## 4.5. 確認の単位と、影響の範囲 (公式ドキュメントの記載と、このプロジェクトでの確認)
- **確認は、ツールの呼び出し 1 回ごと**に出る (`ask` は、「そのツールを使おうとするたびに」確認する)。別のファイル 2 つなら 2 回。同じファイルを 2 回編集すれば、2 回目も出ると読める (推測を含む)。
  1 回の `Edit` 呼び出しで、同じファイルの複数箇所を、`replace_all` で、まとめて置換する場合は、1 回と推測される。
- **「このセッションでは許可」の選択肢が、`ask` の確認に出るか、出た場合に `ask` を覆すかは、公式に明記されていない。** 評価順 (`deny` → `ask` → `allow`) から、`ask` を覆さない可能性が高いと推測されるが、**実機での確認が必要** (TEST-PLAN の S9b / S9c)。
  覆す場合は、`ask` の目的 (テストファイルの編集を、見逃さない) が、損なわれる。
- `acceptEdits` モードでも、明示的な `ask` ルールに一致する操作は、自動承認されない。
- **影響の範囲 (DoubleBufferSample の場合):** `Test*.cpp` / `Test*.h` は、すべて、テストプロジェクト (`DoubleBufferSampleTest/`) の中にあり、本体 (`DoubleBufferSample/`) には、ない。
  そのため、**本体のソースの編集では、確認は出ない。** 出るのは、テストプロジェクトの全ファイル (`.vcxproj`、`packages.config` を含む) の編集と、`git commit`。
  設定は、プロジェクトごと (`.claude/settings.json`) なので、ほかのプロジェクトには、影響しない。
  一方、Skill の「完了時の確認」は、ユーザー Skill (`~/.claude/skills`) として配ると、**その Skill を使うすべてのプロジェクト**に効く。

## 5. 確認の方法 (実機)
設定を入れたら、**新しいセッション**で、次を確認する (`docs/TEST-PLAN.md` の S9 / S10)。
1. Claude に、テストファイル (例: `TestGeometry.cpp`) を、編集させる。**確認ダイアログが出る**こと。
2. Claude に、`git commit` を、依頼する。**確認ダイアログが出る**こと。
3. ビルドとテストのループを、実行する。**完了時の報告に、変更したファイルの一覧と、テストファイルの変更の有無が、含まれる**こと。

## 6. 参考 (公式ドキュメント)
- https://code.claude.com/docs/en/permissions
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/skills
- https://code.claude.com/docs/en/settings
- https://code.claude.com/docs/en/permission-modes
- https://code.claude.com/docs/en/sandboxing
