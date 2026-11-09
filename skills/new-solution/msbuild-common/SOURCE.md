# msbuild-common (取り込んだコピー)

このフォルダは、**外の正本 `macsignee/msbuild-common` の、取り込んだ版のコピー**です。**ここを、直接、編集しません。** 直すときは、正本 (別のリポジトリ) を直して、`bash tools/sync-msbuild-common.sh <正本の clone>` で、取り込みます。

- 使われるとき: 環境変数 `MSBUILD_COMMON_DIR` も、ソリューションの `CLAUDE.md` の「- MSBuild 共通: <パス>」の行もないとき、`/new-solution` と `/add-project common` が、このコピーを使う (コピー型)。
- 取り込んでいる版は、`VERSION` のとおり。
- 取り込むのは、`Common.props`・`Dotnet.props`・`Common.targets`・`VERSION`・`templates/` の 8 ファイルだけ。
