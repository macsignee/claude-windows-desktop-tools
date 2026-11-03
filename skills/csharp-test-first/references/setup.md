# セットアップ: 層やテストを、あとから足す手順

`csharp-test-first` の `SKILL.md` から分けた文書。**層やテストが、足りないときだけ読む** (通常は、`/new-solution` が作ったものが、そのまま使える)。`$SLN_DIR` などの用語は、`SKILL.md` と同じ。

**最初のソリューション・アプリ (WPF / WinForms)・層・テストは、`/new-solution --type wpf` / `--type winforms` が作る** (層 `--layers` と、テスト `--tests` を、別々に指定できる)。
この Skill が、セットアップに関わるのは、**作ったあとで、足りないものが分かったとき**だけ。

1. **設定を読む:** `$SLN_DIR` の `CLAUDE.md` の `- 層:` と `- テスト:` の行 (なければ、構造から判定: `*.Tests` プロジェクトと `Microsoft.NET.Test.Sdk` の有無)。
   - **`テスト: なし` の場合、この Skill (テスト先行) は、使えない。** 「テストが、導入されていません。`/new-solution --tests mstest` で、後付けできます」と案内して止まる (ユーザーが望めば、そのコマンドへ)。
2. **足りないものを確認する (読み取りだけ):** 対象の層のライブラリと、`<名前>.Tests` が、あるか。
   - **ライブラリはあるが、テストプロジェクトがない:** `/new-solution --tests mstest` (後付け) の対象。案内する。
   - **対象の層のライブラリがない** (例: `層: logic` で、ViewModel 層が必要になった): 次の 3. で、層を足す。
3. **案を示して、了承を得て、同梱のスクリプトで足す。** 自分で `.csproj` や `.sln` / `.slnx` を手書きしない。
   ```bash
   python3 <このSkillのフォルダ>/scripts/add_project.py "$SLN_DIR" DataLayer --kind data
   python3 <このSkillのフォルダ>/scripts/add_project.py "$SLN_DIR" LogicLayer --kind logic --uses DataLayer
   python3 <このSkillのフォルダ>/scripts/add_project.py "$SLN_DIR" ViewModels --kind viewmodel --uses LogicLayer
   ```
   - `--tests mstest` (既定): ライブラリと、`<名前>.Tests` を足す。`--tests none`: ライブラリだけ。`--tests-only`: すでにあるライブラリに、テストだけを足す。
   - **WinForms は、`--kind viewmodel` を使わない** (層は `data` / `logic` だけ。Presenter と `IView` は、ロジック層に置く)。
   - `--kind viewmodel`: `ObservableObject` / `RelayCommand` / `MainViewModel` も作る (ViewModel 層を、アプリの中から切り出すときは、**既存の ViewModel を、移す。上書きしない**。名前が重なるものは、先に、ユーザーと決める)。
   - 名前の既定は `DataLayer` / `LogicLayer` / `ViewModels`。終了コード 3 (すでに存在する) は、何も書かれていない。**既存のプロジェクトを、上書きしない。**
   - 層を足したら、`CLAUDE.md` の `- 層:` の行も、実際の構成に合わせる。
   - **MSTest のバージョンは、スクリプトの既定** (実在を確認した版)。新しい版にするときは、`add-package` の `nuget versions MSTest.TestFramework` で確認して、`--mstest-version` で指定する。
   - **NuGet の復元は、ウォッチャーのビルドが行う** (`/restore`)。ホストが nuget.org に届く必要がある。
4. **メインから層を使う配線 (ProjectReference、`DataContext` の設定) は、ここでは、しない。** 必要になったときに、ユーザーの了承を得て行う。
5. **ベースラインを確認する (`SKILL.md` の「手順」の 4. と同じ実行方法で、`build-test-loop` のスクリプトを使う):** ビルドが通り、**`PASSED`** になること。
   - `BUILD_FAILED`: エラーを読んで直す。ベースのアプリ自体の、もともとのエラーなら、直さずに、報告する。
   - `ENV_ERROR`: .NET SDK、NuGet の復元 (ネットワーク)、テストが 1 件も実行されない、を確認して、ユーザーに報告する。
   - **ベースラインが緑になる前に、本物のテストを書かない。**
