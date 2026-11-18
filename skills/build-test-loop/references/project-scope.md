# プロジェクト単位のビルド・テスト (`--project <名前>`。v2.98.0)

`build-test-loop` の `SKILL.md` から分けた文書。**ソリューション全体ではなく、1 つのプロジェクトと、そのテストだけを回したいときに読む** (ビルドとテストの繰り返しを、速くする)。

## 使い方
```bash
bash <このSkillのフォルダ>/scripts/build_test_once.sh "$SLN_DIR" 300 --project OrderLogic      # ビルド + テスト
bash <Skill群>/auto-build/scripts/build_once.sh "$SLN_DIR" 180 --project OrderLogic            # ビルドだけ
bash <このSkillのフォルダ>/scripts/uitest_once.sh "$SLN_DIR" --project MyApp --separate          # ビルド + UI テスト
```
`--project` は、`<solution_dir>` と `[timeout]` の前後、どこに書いてもよい。付けなければ、これまでどおり、ソリューション全体。

## 何が、どのプロジェクトになるか (名前から推測する。名前の規則は、`/new-solution` と同じ)
| 回し方 | ビルドするもの (この順。最初の失敗で止まる) | 実行するもの |
|---|---|---|
| ビルド / ビルド + テスト | `<名前>` (あれば)、`<名前>` のテストのプロジェクト | C++: 名前が `<テストのプロジェクト>.exe` の GoogleTest exe。.NET: そのプロジェクトの `dotnet test` |
| UI テスト | `<名前>` (あれば)、`<名前>.UITests` | その UI テストのプロジェクトの `dotnet test` |

- **テストのプロジェクトの名前:** C++ は `<名前>Test`、.NET は `<名前>.Tests` (`<名前>Test` / `<名前>Tests` も可)。UI テストは `<名前>.UITests` (`UITests` / `.UiTests` も可)。**この規則以外の名前は、扱わない** (命名規約を変えたときは、ウォッチャーの `Resolve-ProjectScope` を直す)。
- `<名前>` が、ソリューションにないとき、テストのプロジェクトがないとき、名前が不正なときは、**環境エラー** (`BUILD_FAILED` / `ENV_ERROR`)。`build_error.log` に、ソリューションにあるプロジェクトの名前が出る。**ソースを直さず**、名前を確かめて、やり直す。
- テストの要約 (`PASSED` の 2 行目など) は、その 1 つのテストのプロジェクトのもの。**全体のテストが通ったことには、ならない。** 区切りでは、`--project` なしで、全体を、1 回、回す。

## 必要なもの
- **ウォッチャーが、新しい版 (`HOST_VERSION` 2.98.0 以降) であること。** 古いウォッチャーは、フラグの `project=` を読まず、**ソリューション全体を、ビルド・実行する**。結果は、正しく出るが、全体の結果になる。出力の末尾の `NOTE: --project ... を指定したが、ウォッチャーは、プロジェクト単位 (project=) で処理していない` で、分かる。`install.sh` で、ホスト側を最新に揃え、ウォッチャーを再起動する。
- 結果の `RESULT_INFO:` の行に、`scope=project=<名前>` が出る (ウォッチャーが、プロジェクト単位で処理した印)。

## ウォッチャーが行うこと (仕組み)
- フラグ (`trigger_build.flag` / `trigger_test.flag` / `trigger_uitest.flag`) の中身の `project=<名前>` を読む。
- `<名前>` と、そのテストのプロジェクトを、**1 つずつ**、MSBuild に渡す (`build-windows.cmd <プロジェクトのファイル> ...`)。単独のプロジェクトを渡すと `SolutionDir` が空になり、C++ の出力先 (`$(SolutionDir)x64\Debug\`) が、全体のときと変わる。そのため、**環境変数 `SolutionDir` を、ソリューションのフォルダにして渡す**。DLL とテスト exe が、同じフォルダに出る。
- .NET の単独のプロジェクトには、Platform を `AnyCPU` と渡す (`Any CPU` は、ソリューションの構成の名前)。
- 参照先のプロジェクト (`ProjectReference`) は、MSBuild が、必要なぶんだけ、ビルドする。

## 実機の確認 (2026-11-18。TEST-PLAN 2-58)
- 合格: C++ の層 (`NativeLayer`)、.NET の層 (`LogicLayer`)、全体に戻る、混在での出力先、ない名前、テストのない名前、ビルドの失敗、UI テスト (`uitest_once.sh --project PS5`: `PS5.UITests` の 5 件が `PASSED`、`scope=project=PS5`)。
- 不具合を 3 件、直した (v2.98.1〜v2.98.3): 混在の単独の .NET の出力先、`.slnx` の `x64` の不足、ない名前の `scope=` の記録。
- **速さ:** 小さいソリューションでは、差がない (本体とテストの 2 回の MSBuild 呼び出しで、初期化が 2 回入る)。大きいソリューションでの効果は、未確認。
- MFC (SDI) のソリューションでも、合格 (`--project LogicLayer`、メインだけ `--project <メイン>`、出力先)。
- 未確認: 大きいソリューションでの時間。
