# msbuild-common

MSBuild の共通設定 (`Directory.Build.props` / `Directory.Build.targets`) のたたき台。**v0.1.1。まだ、`/new-solution` などのスキルは、これを使っていない** (使うのは、次の版)。将来、別のリポジトリに分けて、共通のベースにする。

## 目的

- **設定を 1 か所に置く。** 層やテストを足すたびに、各プロジェクトへ、同じ設定を複製しない。
- **MSBuild の標準の仕組みだけを使う。** 独自のファイル形式や、設定ファイルの規則は、作らない。
- **動きを変えずに、始める。** v0.1.x の中身は、これまで `/new-solution` が作っていた `Directory.Build.props` と、同じ。

## 構成

- **`Common.props`**: 入口。共通ファイルの版 (`MsbuildCommonVersion`) を決め、プロジェクトの種類 (`.csproj`) で、言語ごとの props を読む。
- **`Dotnet.props`**: .NET の共通設定 (`Nullable`・`ImplicitUsings`・`LangVersion`)。`TargetFramework` は置かない (アプリと層で違う)。
- **`Common.targets`**: 入口。`ClaudeBuildInfo` の target だけを持つ。**既定では何もしない。** `/p:ClaudeBuildInfo=true` を渡すと、ビルドの最後に、プロジェクト名・構成・Platform・出力ファイル・共通ファイルの版を、中間出力フォルダの `claude-build-info.txt` に、1 行ずつ書く (C++ は `$(IntDir)`。SDK 形式の .csproj は `$(IntDir)` が空なので `$(IntermediateOutputPath)`)。
- **`templates/Directory.Build.props`・`Directory.Build.targets`**: ソリューション直下に置く薄いファイル。親のフォルダのファイルを読み (MSBuild は、最も近い 1 つしか読まないため)、そのあと、`build\common\` の共通ファイルを読む。
- **`VERSION`**: 共通ファイルの版。`Common.props` の `MsbuildCommonVersion` と同じ値にする (テストが確かめる)。

## ソリューションへの置き方 (予定)

```
<ソリューション>\
  Directory.Build.props      ← templates/ のコピー
  Directory.Build.targets    ← templates/ のコピー
  build\common\              ← このフォルダの、Common.props・Dotnet.props・Common.targets・VERSION のコピー
```

**Windows (Visual Studio とウォッチャー) から見える場所に置くため、コピーして、ソリューションにコミットする** (WSL の `~/.claude` は、ビルドから見えない)。配布の方法は、あとで、git のサブモジュールか NuGet パッケージ (`build\` の props は、自動で読まれる) に、差し替えられる。

## 正本と、配布用のコピー

- 正本は、この `msbuild-common/`。`/new-solution` が配るのは、`skills/new-solution/msbuild-common/` のコピー (`install.sh` は `skills/` だけを配るため)。**正本を変えたら、同じファイルを、コピーにも同期する** (`tests/msbuild_common_test.sh` が、同じであることを確かめる)。

## 別のリポジトリに分けるとき

- 共通ファイルは、スキルのパスや `CLAUDE.md` に、触れない。そのまま、移せる。
- 分ける時期は、使う側が 2 つ以上になる、または、中身が安定したあと。

## 今後の候補

- C++ の共通設定 (`Cpp.props`): `OutDir`・`IntDir`・`WarningLevel` など。既存の `.vcxproj` の設定との優先順位を、確かめてから。
- `/add-project` で、既存のソリューションに足す (薄いファイルと `build\common\`)。
- ビルドの情報を、ウォッチャーの結果に使う。
- 品質の強制 (警告をエラーにする) は、生成直後のビルドが通らなくなる恐れがあるので、段階的に。
