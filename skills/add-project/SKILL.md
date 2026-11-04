---
name: add-project
description: すでにあるソリューション (C++ の MFC / Win32 / DLL、.NET の WPF / WinForms) に、プロジェクトを足していく流れ。足せるもの: 層 (ロジック・データ・ViewModel のライブラリ。C++ は DLL / 静的ライブラリ / MFC 拡張・標準 DLL) とそのテスト、画面を持つ DLL + 画面ホスト、テストの後付け、UI テストの後付け。現状を読む → 何を足すか質問 → 案を示して承認 → 既存のスクリプトで作る → CLAUDE.md を合わせる → ビルドとテストで確かめる、まで進める。「層を足したい」「テストを後付けしたい」「プロジェクトを追加したい」といった依頼で使う。ソリューションを新しく作るのは /new-solution。
argument-hint: "[layer | tests | ui-host | ui-tests] [名前]"
disable-model-invocation: true
---

# プロジェクトを足す (/add-project)

すでにあるソリューションに、プロジェクトを足していく**入口**。作るのは、既存のスクリプト (`add_layer.py` / `add_project.py` / `add_ui_host.py` / `new_solution.py`)。**このコマンドは、手順の案内と、足したあとの記録・確認をする。** `.vcxproj` / `.csproj` / `.slnx` を、自分で手書きしない。

**配布されていること:** `cpp-test-first` / `csharp-test-first` / `new-solution` / `build-test-loop` / `auto-build` の Skill (スクリプトは、それぞれの `scripts/`)。ウォッチャー (`run_watcher.cmd`) が、起動していること (ビルド・テストの確認のとき)。

## 前提
- カレントが、ソリューションフォルダ (`.sln` / `.slnx` があるフォルダ)。以降 `$SLN_DIR`。**なければ、`/new-solution` を案内して止まる。** 複数あれば、止まって、ユーザーに確認する。
- **作業フォルダ (`solutions.md` があり、`.sln` / `.slnx` がないフォルダ) では、使わない** (複数の候補を比べる場所。`/new-solutions`)。
- カレントにしか書き込まない (サンドボックスの制限)。

## 手順

### 1. 現状を読む (読み取りだけ)
```bash
python3 <このSkillのフォルダ>/scripts/solution_state.py "$SLN_DIR"
```
出力の読み方 (`KEY: 値` の行):

| キー | 意味 | 使い方 |
|---|---|---|
| `KIND` / `MAIN` | cpp / dotnet / mixed。メイン | どのスクリプトを使うかを、決める |
| `PROJECT` | 名前 \| 種類 \| 役割 \| テスト \| 参照 \| include だけの参照 | 層の一覧と、テストの有無 |
| `MISMATCH` | CLAUDE.md と、実際の食い違い | **先に、ユーザーに伝える** (足す前に、直すか確認) |
| `REF_ISSUES` | 層の参照の向きの違反 | **先に、ユーザーに伝える。** 違反を、さらに増やさない |
| `SUGGEST_REF` | 参照されていない層と、参照するのが自然な使う側 (`使う側 -> 層`) | 手順 5 で使う |
| `ADDABLE` | 足せるもの。例のコマンド (`--dry-run`) | 手順 2・3 で使う |

終了コード 2 (ソリューションなし) / 3 (複数) は、止まって、ユーザーに伝える。

### 2. 何を足すかを決める (質問は、1 回に 1 つ)
引数 (`layer` / `tests` / `ui-host` / `ui-tests`、名前) があれば、そのとおり。なければ、`ADDABLE` から、選択肢を作って、質問する (AskUserQuestion が使えるなら、選択肢で)。

| 足すもの | 決めること | 使うスクリプト |
|---|---|---|
| **層** (`layer`) | 名前、役割 (データ / ロジック / ViewModel / その他)、種類 (C++: `dll` / `lib` / `mfc-ext-dll` / `mfc-std-dll`。.NET: `lib` / `data` / `logic` / `viewmodel`)、テストの有無、**参照する層 (`--uses`)** | C++: `cpp-test-first` の `add_layer.py`。.NET: `csharp-test-first` の `add_project.py` |
| **テストの後付け** (`tests-for:<名前>`) | どの層か (`ADDABLE` の項目) | 同上の `--tests-only` |
| **画面を持つ DLL + 画面ホスト** (`ui-host`。C++ だけ) | 名前、種類 (標準 / 拡張)、ロジック層 (`--logic`)、UI テストの有無 | `cpp-test-first` の `add_ui_host.py` |
| **UI テストの後付け** (`ui-tests:<アプリ>`) | どのアプリか | `new-solution` の `new_solution.py --ui-tests flaui` |

- **層の名前は、既定のままでよい** (`LogicLayer` / `DataLayer` / `ViewModels`。変更は、作成後にもできる。`DLL-LAYOUT.md`)。作るのは、ユーザーが望んだときだけ。
- **参照の向きを守る:** メイン → 画面 → ViewModel → ロジック → データ。**下の層は、上の層を参照しない。** `--uses` に、上の層を指定する依頼は、その場で指摘する。
- **MFC 拡張 DLL (`mfc-ext-dll`) は、メインが MFC のときだけ。** MFC の DLL の選び方は、`cpp-test-first` の `DLL-LAYOUT.md`。
- **C++ のテスト (`gtest`) の入れ方** (`--gtest auto|vcpkg|source`) は、`new-solution` の「GoogleTest」と同じ。迷ったら `auto`。
- **UI 層はテストしない** (画面のテストは UI テスト)。UI DLL に、`tests-for` を出さない。

### 3. 案を示して、承認を得る (**必ず止まる**)
`ADDABLE` の例の `--dry-run` を、実際の引数で実行し、出力を要約して見せる。
- 作るプロジェクトとファイル、参照 (`--uses`)、テスト、GoogleTest / MSTest の状態 (`GTEST_MODE` / `NOTE`)、ソリューションへの登録。
- **変わるのは、新しいプロジェクトと、ソリューション (`.slnx` / `.sln`)、`CLAUDE.md` (手順 6) だけ**であることを、明記する。既存のプロジェクトは、書き換えない (参照の追加は、手順 5)。
- 「この内容で、足してよいですか?」と聞いて、返事を待つ。**承認が出るまで、何も作らない。**
- 終了コード 3 (すでにある) は、何も書かれていない。**既存のものを、上書きしない。** 終了コード 2 は、組み合わせや入力の問題。内容を、ユーザーに伝える。

### 4. 作る
承認された引数で、`--dry-run` を外して、実行する。**手で、`.vcxproj` や `.csproj` を書かない。**
- C++ のテストを足したとき: 出力の `GTEST_MODE` で、仕上げを行う (`new-solution` の A. の 5.。`GTEST_VCPKG: no-baseline` のときは、`package_once.sh` で baseline の固定と取得)。
- .NET: NuGet の復元は、ウォッチャーのビルドが行う (`/restore`)。

### 5. 参照 (使う側から、新しい層へ)
**この版では、案内だけ。** `solution_state.py` を、もう一度実行し、**`SUGGEST_REF` の行 (`使う側 -> 層`) と、`REF_ISSUES`** を、報告に書く。
- 例: 「メイン `Foo` が、新しい `ReportLayer` を参照する必要があります (`ProjectReference`、C++ は、リンクも)」。
- **ユーザーの了承なしに、既存のプロジェクトを書き換えない。** 参照の追加を頼まれたら、了承を得て、`.csproj` / `.vcxproj` の `ProjectReference` を、最小の差分で足す (C++ の DLL は、インクルードパスとリンクの条件が、DLL の種類で違う。`DLL-LAYOUT.md`)。
- 新しい層が、`--uses` で他を参照している場合は、`add_layer.py` / `add_project.py` が、すでに書いている (新しい側から、下の層への参照)。

### 6. CLAUDE.md を、実際の構成に合わせる
**書き換えるのは、次の 3 か所だけ** (ほかの節は、触らない)。`CLAUDE.md` がなければ、作らず、ユーザーに伝える。
- **`- 層:` の行:** 役割で足す。既定の名前 (`DataLayer` / `LogicLayer` / `ViewModels`) なら、役割だけ (`data,logic`)。既定でない名前は、`logic:OrderLogic` の形。役割が「その他」の層は、この行に書かず、下の表に書く。**書いてある層は、消さない・並べ替えない。**
- **層の表 (「## 層と依存の向き」):** 1 行足す (プロジェクト、種類、テスト)。表がなければ、「- 追加した層: 名前 (種類)」の箇条書きを、その節の末尾に足す。
- **`- テスト:` の行:** 最初のテストを足したとき、`なし` を `あり (GoogleTest)` / `あり (MSTest)` に直す。
- 画面を持つ DLL + 画面ホストは、`add_ui_host.py` が、自分で CLAUDE.md に節を足す (二重に足さない)。

直したあと、`solution_state.py` を実行して、**`MISMATCH` が出ないこと**を確認する。

### 7. 確かめる (ベースライン)
- **ビルド:** `auto-build` の手順 (`build_once.sh`)。`SUCCESS` になるまで。
- **テストを足したとき:** `build-test-loop` の手順 (`build_test_once.sh`)。`PASSED` (追加分の 1 件のテストを含む) になること。
- **静的な検査:** MFC は `mfc-check` (層の依存、DLL の設定)、WPF は `wpf-check`、WinForms は `winforms-check`。**指摘が 0 件**であること (生成物は、指摘が出ないように作ってある。出たら、生成の誤り)。
- 失敗したら、それぞれの Skill の規則で直す。**環境の問題 (`ENV_ERROR`、ウォッチャー未起動) は、直さずに報告する。**

### 8. 報告して、終わる
作ったもの (プロジェクト、テスト、ソリューションへの登録)、`CLAUDE.md` で直した行、**足りない参照 (`SUGGEST_REF`)**、ビルド・テスト・静的検査の結果、**確認できていないこと** (実機の画面など) を、短く示す。自動で、次に進まない。**`git commit` / `git push` は、ユーザーの指示があるときだけ。**
- ユーザーに、Visual Studio で `.slnx` を開いて、問題がないか確認してもらうとよい、と添える。

## しないこと
- 承認なしの作成。既存のスクリプトを使わない、プロジェクトファイルの手書き。
- 既存のプロジェクトの、無断の書き換え (参照の追加は、了承を得てから)。
- 参照の向きを逆にする (下の層から、上の層への参照)。
- ソリューションの新規作成 (`/new-solution`)、機能のコード、仕様書の作成 (`claude-spec-workflow`)。
- カレントの外への書き込み。`git commit` / `git push` / `git init`。
