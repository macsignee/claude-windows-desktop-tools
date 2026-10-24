---
name: add-package
description: ライブラリ / パッケージを、プロジェクトに追加する手順。.NET / WPF は NuGet (dotnet add package)、C++ は vcpkg (マニフェストモード) か、GitHub のソースの取り込み (ヘッダーのみのライブラリなど)。WSL からは NuGet も vcpkg も直接実行できないので、Windows ホスト側のウォッチャーに、フラグ (trigger_package.flag) で実行させ、結果を読む。「NuGet パッケージを追加して」「ライブラリを入れたい」「vcpkg で xxx を使いたい」、ビルドエラーの C1083 (include が見つからない) / LNK2019 (外部ライブラリ) / CS0246 (型や名前空間が見つからない) / NU1101 (パッケージが見つからない) の原因がライブラリの不足、といった場面で使う。GoogleTest は対象外 (現状の方式のまま)。
---

# パッケージの追加 (NuGet / vcpkg / ソースの取り込み)

Claude (WSL) は、NuGet も vcpkg も、直接実行できない (ネットワークと、Windows 側のツールに届かない)。
そこで、**ホスト側のウォッチャーに、操作を依頼する** (`trigger_package.flag`)。結果は、ファイルで返る。
**自分で `dotnet` / `vcpkg` / `nuget` / `git clone` を実行しない。** 同梱のスクリプトを使う。

## 前提
- ユーザーが、対象のソリューションで `run_watcher.cmd` を起動済みであること (ビルドと同じウォッチャー)。
- ソリューションのフォルダ (`.sln` / `.slnx` があるフォルダ) を `$SLN` とする。`<このSkillのフォルダ>` は、スクリプトと同じ場所。

## どの方法を使うか

| 追加したいもの | 方法 | 理由 |
|---|---|---|
| .NET / WPF のパッケージ (CommunityToolkit.Mvvm, Serilog など) | **NuGet** (`nuget add`) | `dotnet add package` が、ID の実在・バージョンの解決・`.csproj` (または `Directory.Packages.props`) の書き換えを、正しく行う |
| C++ のライブラリ (fmt, spdlog, boost, zlib など。vcpkg にあるもの) | **vcpkg** (`vcpkg.json` + `vcpkg install`) | ソースからビルドされ、バージョンが固定でき、MSBuild が自動でリンクする |
| C++ のヘッダーのみ / 単一ファイルのライブラリ (nlohmann/json, stb, magic_enum など) で、vcpkg を使いたくない | **ソースの取り込み** (`fetch`) | 軽く、確実。`ThirdParty\<名前>\` に置く |
| GoogleTest | **この Skill の対象外** | 現状の方式のまま (`/new-solution` の `--gtest`、`gtest_once.sh`) |

迷ったら、C++ は vcpkg。vcpkg にないライブラリは、`fetch`。

## 共通のルール
1. **追加する前に、実在とバージョンを確認する** (`nuget search` / `nuget versions` / `vcpkg search`)。**名前を、推測で書かない。** 紛らわしい名前 (名前の似た別のパッケージ) を、入れないため。
2. **ユーザーが名指しした名前だけを、追加する。** 検索で見つけた、似た名前を、勝手に選ばない。候補が複数あるときは、ID・バージョン・ダウンロード数・発行元の確認済み (`verified=True`) を示して、ユーザーに選んでもらう。
3. **バージョンは、明示して固定する** (NuGet は、`versions` の最新の stable。vcpkg は `builtin-baseline`)。プレリリースは、ユーザーが頼んだときだけ。
4. **このスクリプトの実行は、設定で、確認が出ることがある** (`docs/RECOMMENDED-SETTINGS.md`)。確認が出たら、何を、なぜ追加するのかを、簡潔に説明する。拒否されたら、別の方法で、同じことをしない。
5. **追加したら、ビルド (`auto-build` / `build-test-loop`) で、確認する。** ビルドが通るまでが、追加の完了。
6. 完了時に、変更したファイルを報告する (下記)。`git commit` は、頼まれない限り、しない。

## 実行 (1 回分)

```bash
bash <このSkillのフォルダ>/scripts/package_once.sh "$SLN" [--timeout 秒] "<操作>" ["<操作>" ...]
```
- 操作は、1 引数に 1 つ。**決まった形だけ**が通る (それ以外は、`BAD_ARGS`)。
  ```
  nuget search <語>
  nuget versions <ID>
  nuget add <プロジェクト> <ID> [<バージョン>]     # プロジェクト: ソリューション内の .csproj の、相対パス
  nuget remove <プロジェクト> <ID>
  vcpkg search <語>
  vcpkg baseline
  vcpkg install
  fetch <owner/repo> <タグ> <名前> [<サブフォルダ>]
  ```
- 複数の操作は、上から順に実行され、**最初の失敗で止まる**。
- `--file <ファイル>`: 1 行 1 操作のファイル (`ThirdParty.manifest` など) を、まとめて実行する。
- **`vcpkg install` は、長い** (ポートのビルド。数分〜数十分)。`run_in_background: true` で実行し、`--timeout 1800` 以上を付ける。完了通知が来るまで、ファイルを読まない・再実行しない (ビルドと同じ。古い結果を読むため)。それ以外は、短い (`--timeout` の既定は 300 秒)。
- Bash ツールの既定のタイムアウトは 120 秒。待つ時間が長いときは、`run_in_background: true`、または、`timeout` を、待つ秒数 + 20 秒以上にする。

| 1 行目 | rc | 意味 | 次の行動 |
|---|---|---|---|
| `OK` | 0 | 成功。2 行目以降に、各操作の出力 | 次の手順へ |
| `FAILED` | 1 | 失敗 (ソース側の問題: パッケージ名の誤り、`vcpkg.json` がない、サブフォルダがない など) | 出力を読んで直す。名前の誤りなら、`search` / `versions` で確かめる |
| `ENV_ERROR` | 4 | 環境エラー (ネットワーク、`dotnet` / `vcpkg` がない) | **ソースを直さず**、内容を報告して停止。ユーザーに、環境の確認 (ネットワーク、SDK、VS の vcpkg コンポーネント) を依頼 |
| `WATCHER_NOT_RUNNING` | 3 | フラグが回収されない | 停止し、`run_watcher.cmd` の起動をユーザーに依頼 |
| `TIMEOUT` | 5 | 完了マーカーが出ない | `vcpkg install` なら、`--timeout` を延ばして 1 回だけ再試行 (終わったポートは、キャッシュされる) |
| `BAD_ARGS` | 2 | 操作の形が不正 | 形を直す (理由が出る) |

## 手順 1: NuGet (.NET / WPF)

1. 実在とバージョンの確認:
   ```bash
   bash <Skill>/scripts/package_once.sh "$SLN" "nuget versions CommunityToolkit.Mvvm"
   ```
   名前が不確かなら、`"nuget search <語>"` (ダウンロード数と `verified` が出る)。
2. 追加 (最新の stable を、明示):
   ```bash
   bash <Skill>/scripts/package_once.sh "$SLN" "nuget add MyApp/MyApp.csproj CommunityToolkit.Mvvm 8.4.0"
   ```
   出力の `added <ID> <バージョン> -> <プロジェクト>` で、書き込まれたバージョンを確認する。中央管理 (`Directory.Packages.props`) のソリューションでも、`dotnet add package` が、正しく扱う。
3. ビルドで確認: `auto-build`。**復元は、ビルドが行う** (`/restore`)。
4. 削除は、`"nuget remove <プロジェクト> <ID>"`。

- `search` / `versions` は、**nuget.org だけ**を見る。社内フィードのパッケージは、`add` は (ホストの NuGet の設定のとおり) 動くが、`search` には出ない。
- `.csproj` を、手で編集して `PackageReference` を足さない (名前とバージョンの確認ができないため)。

## 手順 2: vcpkg (C++)

初回だけ、セットアップが要る (`vcpkg.json` と、`.vcxproj` の設定)。

1. **セットアップ** (WSL で完結。ネットワーク不要。何度実行しても同じ):
   ```bash
   python3 -I <Skill>/scripts/cpp_pkg.py setup "$SLN"
   ```
   `vcpkg.json` を作り、各 `.vcxproj` (gtest を除く) に、マニフェストモードの設定を足す。**トリプレットは、既定で `x64-windows-static-md`** (静的ライブラリ + 動的 CRT `/MD`)。DLL で配布するなら `--linkage dynamic`。
   **`.vcxproj` が変わるので、ユーザーに、変更したことを伝える** (VS で、プロジェクトの再読み込みの確認が出ることがある)。
2. **ポートの確認:** `"vcpkg search fmt"`。**マニフェストモードの `search` は、`builtin-baseline` が要る** (実機で判明)。`list` で `baseline:` が `(none)` なら、先に `package_once.sh "$SLN" "vcpkg baseline"` を実行する。 **`search` は、baseline 後でも約 3 分かかる (実機)。`--timeout 600` 以上で、バックグラウンドで実行する。**
3. **追加** (`vcpkg.json` の編集。WSL で完結):
   ```bash
   python3 -I <Skill>/scripts/cpp_pkg.py add "$SLN" fmt
   python3 -I <Skill>/scripts/cpp_pkg.py add "$SLN" boost-asio --features ssl --version-ge 1.84.0
   ```
   削除は `remove`、一覧は `list`。
   **ポート固有の設定は、`add` / `remove` が自動で行う** (`.vcxproj` の `<ItemDefinitionGroup Label="VcpkgDefines">`)。今は fmt の `FMT_UNICODE=0` (fmt は MSVC で `/utf-8` を要求する (C2338)。`/utf-8` は、ソースが CP932 だと文字化けするので、定義で回避)。`.vcxproj` が変わるので、ユーザーに伝える。
4. **取得とビルド** (ホスト側。**長い。バックグラウンドで**):
   ```bash
   bash <Skill>/scripts/package_once.sh "$SLN" --timeout 1800 "vcpkg baseline" "vcpkg install"
   ```
   - `vcpkg baseline` は、**初回だけ** (`vcpkg.json` に `builtin-baseline` を入れる。バージョンの固定)。`python3 -I <Skill>/scripts/cpp_pkg.py list "$SLN"` で、`baseline:` が `(none)` でなければ、不要。
   - ポートを足したあとの `vcpkg install` は、足した分だけビルドされる (キャッシュ)。
5. **ビルドで確認:** `auto-build` / `build-test-loop`。vcpkg のライブラリは、**インクルードとリンクが自動** (`#include <fmt/core.h>`)。プロジェクトの設定の変更は、不要。

- 取得は、GitHub などに、ネットワークが届く必要がある。失敗は `ENV_ERROR`。
- ポート名の誤り (`vcpkg install` の `FAILED`) は、ソースの問題 (`search` で確認し、`vcpkg.json` を直す)。
- `vcpkg_installed/` は、`.gitignore` に入る (`setup` が足す)。コミットしない。
- ウィザードで作った MFC のプロジェクトでも、使える。

## 手順 3: ソースの取り込み (`fetch`)

```bash
bash <Skill>/scripts/package_once.sh "$SLN" "fetch nlohmann/json v3.11.3 json single_include"
```
- `ThirdParty\json\` に、GitHub のタグ `v3.11.3` の、`single_include` の**中身**が置かれる (サブフォルダを省くと、リポジトリ全体 (`.git` を除く))。同じ内容があれば、何もしない。
- **インクルードパスを足す** (すべての構成に。`.vcxproj` の編集は、スクリプトで):
  ```bash
  python3 -I <Skill>/scripts/cpp_pkg.py include-dir "$SLN/MyApp/MyApp.vcxproj" '$(SolutionDir)ThirdParty\json'
  ```
  → `#include <nlohmann/json.hpp>`。
  `.vcxproj` が変わるので、**VS で開いたままなら、プロジェクトの再読み込みが要る** (再読み込み前は、プロパティページに、反映されない。実機で確認)。ユーザーに伝える。
- **記録する** (別の PC でも再現できるように。`ThirdParty/<名前>/` は、`.gitignore` に入り、`ThirdParty.manifest` がコミットされる):
  ```bash
  python3 -I <Skill>/scripts/cpp_pkg.py record-fetch "$SLN" nlohmann/json v3.11.3 json single_include
  ```
  クローンし直したあと: `bash <Skill>/scripts/package_once.sh "$SLN" --file "$SLN/ThirdParty.manifest"`。
- **ソースをビルドする必要があるライブラリ** (`.cpp` が、いくつもある) は、`fetch` で置いただけでは、ビルドされない。静的ライブラリのプロジェクトを、ソリューションに足す必要がある (GoogleTest の `gtest.vcxproj` と同じ形)。**ユーザーに確認してから、行う。** vcpkg にあれば、vcpkg を使う。
- `fetch` は、**GitHub のタグ**だけ (ブランチは不可)。リポジトリ名・タグ・名前・サブフォルダは、決まった文字だけが通る。

## 完了時の確認 (変更の報告)
作業を終える前に (成功でも、停止でも)、変更したファイルを一覧して、報告に含める。ユーザーが、コミットの前に、`git diff` で、変更を確認できるようにするため。**このセッションで、ファイルを変更していない場合 (`search` / `versions` だけなど) は、実行せず、「変更なし」と報告する。**

```bash
git -c core.fileMode=false --no-optional-locks status --short
```
- 報告に含める: 追加した ID / ポート名と、**バージョン**、変更したファイル (`.csproj` / `Directory.Packages.props` / `vcpkg.json` / `.vcxproj` / `ThirdParty.manifest` / `.gitignore`)。
- **`.csproj` / `.vcxproj` / `vcpkg.json` は、ビルドに影響するので、報告の先頭で述べる。**
- 「コミット前に、`git diff` で変更を確認してください」と、一言添える。**`git commit` と `git push` は、ユーザーの明示的な指示がない限り、実行しない。**

## 限界
- **`search` / `versions` は、nuget.org だけ。** `vcpkg search` は、vcpkg の登録 (ポートの一覧) を、ホストの vcpkg が引ける場合だけ動く (引けない場合は、`FAILED` / `ENV_ERROR` の理由が出る)。
- **ホスト側 (Windows) の動作は、実機での確認が必要** (`docs/TEST-PLAN.md` の P 系)。
- vcpkg の、初回のビルドは、長い。Visual Studio 同梱の vcpkg (`VC\vcpkg`) を使う。`VCPKG_ROOT` が設定されていれば、そちら。
- 複数のプロジェクトが、同じ `vcpkg.json` を使う。ビルドを並列に走らせると、取得が競合することがある。**先に `vcpkg install` を済ませておく** (上記の手順 4)。
- **`CommunityToolkit.Mvvm` に切り替えるとき (実機で確認):** 生成物の自前の `ObservableObject` が、**同じ名前で衝突**し、`[ObservableProperty]` が解決されない (`MVVMTK0019`、`CS0103`)。パッケージを足しただけでは、ビルドは通る。**`[ObservableProperty]` / `[RelayCommand]` に書き換えるときは、自前の `ObservableObject.cs` (と、使わなくなった `RelayCommand.cs`) を、削除する。**
- **C++ の NuGet は、対象外** (`packages.config` も、VS 2026 の `PackageReference` (Experimental) も。`.vcxproj` への `nuget add` は、拒否される)。C++ のライブラリは、**vcpkg** を使う。GoogleTest の既存の方式は、そのまま。
