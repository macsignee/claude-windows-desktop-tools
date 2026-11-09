# msbuild-common

MSBuild の共通設定 (`Directory.Build.props` / `Directory.Build.targets`) のたたき台。**v0.2.0。** `/new-solution` が、新規のソリューションに、薄いファイルと `build\common\` を作り (v2.65.0)、`/add-project common` が、すでにあるソリューションに足す (v2.66.0)。将来、別のリポジトリに分けて、共通のベースにする。

## 目的

- **設定を 1 か所に置く。** 層やテストを足すたびに、各プロジェクトへ、同じ設定を複製しない。
- **MSBuild の標準の仕組みだけを使う。** 独自のファイル形式や、設定ファイルの規則は、作らない。
- **動きを変えずに、始める。** v0.1.x の中身は、これまで `/new-solution` が作っていた `Directory.Build.props` と、同じ。v0.2.0 で、検査 (`ClaudeCheckProject`) が足され、**既定で、警告を出す** (止めるには `ClaudeCheck` を `off`)。

## 構成

- **`Common.props`**: 入口。共通ファイルの版 (`MsbuildCommonVersion`) を決め、プロジェクトの種類 (`.csproj`) で、言語ごとの props を読む。
- **`Dotnet.props`**: .NET の共通設定 (`Nullable`・`ImplicitUsings`・`LangVersion`)。`TargetFramework` は置かない (アプリと層で違う)。
- **`Common.targets`**: 入口。`ClaudeBuildInfo` の target だけを持つ。**既定では何もしない。** `/p:ClaudeBuildInfo=true` を渡すと、ビルドの最後に、プロジェクト名・構成・Platform・出力ファイル・共通ファイルの版を、中間出力フォルダの `claude-build-info.txt` に、1 行ずつ書く (C++ は `$(IntDir)`。SDK 形式の .csproj は `$(IntDir)` が空なので `$(IntermediateOutputPath)`)。
- **`templates/reference/Directory.Build.props`・`Directory.Build.targets`**: 参照型の薄いファイル (下の「ソリューションへの置き方」)。環境変数 `MSBUILD_COMMON_DIR` が指す、外の正本を読む。
- **`templates/Directory.Build.props`・`Directory.Build.targets`**: コピー型の薄いファイル。 ソリューション直下に置く薄いファイル。親のフォルダのファイルを読み (MSBuild は、最も近い 1 つしか読まないため)、そのあと、`build\common\` の共通ファイルを読む。
- **`VERSION`**: 共通ファイルの版。`Common.props` の `MsbuildCommonVersion` と同じ値にする (テストが確かめる)。

## ビルドの前の検査 (v0.2.0。`ClaudeCheckProject`)

`mfc-check` / `wpf-check` / `winforms-check` の検査のうち、**プロジェクトの設定だけで判定できるもの**を、ビルドの前に確かめる (`Common.targets`)。ソースの中身を読む検査 (バインディング・メッセージマップ・リソース ID・`InitializeComponent()` の呼び忘れなど) は、MSBuild ではできないので、これまでどおり、各 check が行う。コードと意味は、各 check と同じ。

| コード | 内容 | 対応する check |
|---|---|---|
| `LAY003` | プロジェクト参照の向きが、層 (UI → ViewModel → ロジック → データ) に反する | mfc-check の LAY003、wpf-check の LAY003、winforms-check の WFL003 |
| `LAY001` | ロジック層・データ層が、WPF / WinForms に依存している (`UseWPF`・`UseWindowsForms`・`-windows` の `TargetFramework`) | wpf-check の LAY001、winforms-check の WFL001 |
| `DLL001` | MFC の DLL で、`_USRDLL` と `_AFXEXT` が、両方定義されている | mfc-check の DLL001 |
| `DLL002` | MFC 拡張 DLL (`_AFXEXT`) で、`UseOfMfc` が `Dynamic` でない | mfc-check の DLL002 |
| `DLL003` | MFC の DLL で、`UseOfMfc` が有効なのに、`_USRDLL` も `_AFXEXT` もない (警告のみ) | mfc-check の DLL003 |

- **層の役割は、プロジェクトの名前から決める** (`solution_state.py` の `role_of_name` と同じ規則。`tests/msbuild_common_test.sh` が、同じ判定になることを確かめる)。決まらないときは、プロジェクトに `<ClaudeLayerRole>data|logic|viewmodel|ui|other</ClaudeLayerRole>`。exe は `main` (どの層も、参照してよい)。名前が `Test` / `Tests` で終わるプロジェクトは、検査しない。
- **`ClaudeCheck`** (`Common.props` の既定は `warning`): `off` = 検査しない / `warning` = 警告を出す / `error` = `LAY001`・`LAY003`・`DLL001`・`DLL002` を、エラーにする。`/p:ClaudeCheck=error` か、各プロジェクトの `<ClaudeCheck>` で変える。警告は、ウォッチャーの `warnings.log` に出る。
- **違いと限界:** C++ の検査は、ビルドしている構成だけを見る (mfc-check は、全部の構成)。参照先の役割は、名前だけで決める (参照先の exe は、見分けない)。参照先の MFC の設定 (`DLL008`) は、参照先を評価しないと分からないので、含めない。

## ソリューションへの置き方

Claude は、共通ファイルの中身を決めない。**外の正本 (この `msbuild-common/`。将来は別のリポジトリ) を読んで、ソリューションに合わせて置く。** 置き方は、2 つ。

**参照型** (正本の場所が、環境変数か `CLAUDE.md` で決まるとき。既定):

```
<ソリューション>\
  Directory.Build.props      ← templates/reference/ のコピー (環境変数 MSBUILD_COMMON_DIR の正本を、Import する)
  Directory.Build.targets    ← templates/reference/ のコピー
```

- **コピーしない。** 正本を直せば、すべてのソリューションに効く。
- **WSL と Windows で、別に設定する。** Claude (WSL) は、環境変数 `MSBUILD_COMMON_DIR` (例 `/mnt/c/Tools/msbuild-common`) か、`CLAUDE.md` の `- MSBuild 共通: /mnt/c/Tools/msbuild-common` で、正本を読む (**`CLAUDE.md` が優先**)。MSBuild (Visual Studio とウォッチャー) は、**Windows 側の**環境変数 `MSBUILD_COMMON_DIR` (例 `C:\Tools\msbuild-common`。`wslpath -w` で、同じフォルダか、確かめる) で探す。Visual Studio は、設定後に再起動する。
- **未設定だと、止まる。** 薄いファイルは、`__MSBUILD_COMMON_DIR_NOT_SET__\Common.props` を Import しようとして、`was not found` のエラーになる (黙って飛ばさない。`Nullable` などが効かないまま、ビルドが通ることを避ける)。
- ソリューションだけでは、完結しない (正本のないマシン・CI では、止まる)。完結させたいときは、コピー型。

**コピー型** (正本の場所が決まらないとき。または `--common copy`):

```
<ソリューション>\
  Directory.Build.props      ← templates/ のコピー
  Directory.Build.targets    ← templates/ のコピー
  build\common\              ← このフォルダの、Common.props・Dotnet.props・Common.targets・VERSION のコピー
```

**ソリューションだけで完結する** (WSL の `~/.claude` は、Windows のビルドから見えないので、コピーして、コミットする)。

**正本に求める形 (読み込む側との約束):** `Common.props`・`Common.targets`・`VERSION`、コピー型には `Dotnet.props`・`templates/Directory.Build.{props,targets}`、参照型には `templates/reference/Directory.Build.{props,targets}`。`/new-solution` と `/add-project common` は、足りないファイルがあると、何も書かずに止まる。

## 正本と、配布用のコピー

- 正本は、この `msbuild-common/`。**場所の指定がないとき**、`/new-solution` が使うのは、`skills/new-solution/msbuild-common/` のコピー (`install.sh` は `skills/` だけを配るため)。**正本を変えたら、同じファイルを、コピーにも同期する** (`tests/msbuild_common_test.sh` が、同じであることを確かめる)。

## 別のリポジトリに分けるとき

- 共通ファイルは、スキルのパスや `CLAUDE.md` に、触れない。そのまま、移せる。
- 分ける時期は、使う側が 2 つ以上になる、または、中身が安定したあと。

## 今後の候補

- C++ の共通設定 (`Cpp.props`): `OutDir`・`IntDir`・`WarningLevel` など。既存の `.vcxproj` の設定との優先順位を、確かめてから。
- ビルドの情報を、ウォッチャーの結果に使う。
- 品質の強制 (警告をエラーにする) は、生成直後のビルドが通らなくなる恐れがあるので、段階的に。
