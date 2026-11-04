# 3層 + DLL 単位のテスト: ソリューションの構成と規約

`cpp-test-first` が前提にする、ソリューションの構成。プロジェクトを新しく作る (ユーザーが了承した) ときと、
既存の構成が規約に合っているかを確認するときに読む。**ここに書いていることを、ユーザーの了承なしに、既存プロジェクトへ適用しない。**

## 構成

```
UI (MFC exe)  ──▶  ロジック DLL  ──▶  データ DLL (のインターフェース)
                       ▲                     ▲
                 ロジックのテスト exe     データのテスト exe
```

| プロジェクト | 種類 | MFC | 参照するもの |
|---|---|---|---|
| UI (MFC アプリ) | exe | 使う (共有 DLL) | ロジック DLL、データ DLL |
| ロジック DLL | **MFC 拡張 DLL** | 使う (共有 DLL) | データ DLL の**ヘッダ** (インターフェースだけ。リンクはしない) |
| データ DLL | **MFC 拡張 DLL** | 使う (共有 DLL) | なし |
| ロジックのテスト | exe (GoogleTest) | 使う (共有 DLL) | ロジック DLL (プロジェクト参照) |
| データのテスト | exe (GoogleTest) | 使う (共有 DLL) | データ DLL (プロジェクト参照) |

- **ロジック DLL は、データ層の実装を知らない。** データ層の**インターフェース** (純粋仮想クラス。ヘッダだけ) にだけ依存する。
  実装は、UI 層が組み立てて、ロジックに渡す。これで、ロジックのテストで、データ層をフェイクに差し替えられる。
- **テストは、DLL 単位。** DLL 1 つに、テスト exe 1 つ。名前は、`<DLL名>Test` (ウォッチャーの既定の検出パターン `(Test|Tests)\.exe$` に合わせる)。
- UI 層にテストは作らない。

### なぜ MFC 拡張 DLL なのか
ロジック層・データ層で `CPoint` / `CObject` / `CArchive` など MFC の型やシリアライズ (`DECLARE_SERIAL` / `IMPLEMENT_SERIAL`) を扱う場合、各プロジェクトが MFC を個別に静的リンクすると、`CObject` 派生クラスの RTTI (`CRuntimeClass`) やモジュール状態が、DLL 境界をまたいで共有されず、実行時に不正な動作やクラッシュの原因になる。
**MFC 拡張 DLL (MFC Extension DLL)** として作ることで、EXE (UI) と各 DLL が、同一の共有 MFC ランタイム (`mfc1xxu.dll` など) を使い、`CObject` 派生クラスのやり取り (生成・シリアライズ・型情報) が、プロジェクトをまたいでも正しく動く。
MFC を使わない、純粋な計算・ロジックだけの DLL を作る場合は、この節は適用しない (従来どおり、通常の DLL でよい)。この構成を採るかどうかは、**仕様で MFC 型をロジック/データ層に持ち込むと決めたときだけ**、ユーザーの了承を得て選ぶ。

## 規約 (vcxproj)

1. **出力先を、全プロジェクトで同じにする:** `$(SolutionDir)$(Platform)\$(Configuration)\`
   - ウォッチャーは、`<ソリューション>\<Platform>\<Configuration>\` の `*Test.exe` を探して実行する。
   - 実行時に、DLL がテスト exe と同じフォルダにないと、起動に失敗する。出力先をそろえれば、自然に満たされる。
   - ソリューション直下の `Directory.Build.props` で、`OutDir` / `IntDir` を設定するのが、簡単。`IntDir` は、プロジェクトごとに分ける (`$(SolutionDir)obj\$(ProjectName)\...`)。
2. **DLL の公開マクロ:** DLL ごとに `<Name>Api.h` を持つ。
   ```cpp
   #ifdef LOGICLAYER_EXPORTS
   #define LOGICLAYER_API __declspec(dllexport)
   #else
   #define LOGICLAYER_API __declspec(dllimport)
   #endif
   #pragma warning(disable : 4251)   // 公開クラスの std:: メンバの警告。同じコンパイラ・CRT でビルドする前提で抑止
   ```
   - DLL のプロジェクトに、プリプロセッサ定義 `LOGICLAYER_EXPORTS` を追加する。**テスト exe や UI には、定義しない** (インポート側になる)。
   - 公開するクラスに、`class LOGICLAYER_API Foo` と書く。
   - **MFC 拡張 DLL の場合:** `CObject` 派生クラス (シリアライズ対象など) は、上記の `__declspec` マクロの代わりに、MFC の拡張 DLL 用マクロ `AFX_EXT_CLASS` を使う (`class AFX_EXT_CLASS Foo : public CObject`)。`CObject` を継承しない、純粋な値クラスや関数には、従来どおり `<Name>_API` を使ってよい (混在可)。
2.5. **MFC 拡張 DLL のプロジェクト設定 (MFC 型を使う DLL のときだけ):**
   - `<ConfigurationType>DynamicLibrary</ConfigurationType>` のまま、`<UseOfMfc>Dynamic</UseOfMfc>` を追加する (静的リンクではなく、**共有 DLL** にすること。プロジェクトをまたいだ `CObject` のやり取りに必要)。
   - プリプロセッサ定義に `_AFXDLL` と `_AFXEXT` を追加する。**`_USRDLL` は付けない (通常の DLL の印であり、`_AFXEXT` と同時に定義すると、MFC のスタブライブラリ (`mfcs1xx(u)(d).lib`) が提供する既定の `DllMain` と、拡張 DLL 用に書く `DllMain` が衝突し、`LNK2005` (二重定義) になる)。**
   - **`PrecompiledHeader` を `Use` にし、`pch.h`/`pch.cpp` 経由で `<afxwin.h>` を読み込む (`NotUsing` のまま生の `#include <afxwin.h>` を直接コンパイルすると、拡張 DLL 用のヘッダ (`afxdllx.h`) が正しく解決できず、原因の分かりにくいコンパイルエラーになることがある)。** `add_layer.py` が生成する既定は `NotUsing` なので、MFC 拡張 DLL にする場合は、ここも手動で変更する。
   - DLL のエントリポイント (`.cpp`) に、拡張 DLL の定型コード (`static AFX_EXTENSION_MODULE` と、`DllMain` 内の `AFX_MANAGE_STATE` / `AfxInitExtensionModule`) を書く。これを忘れると、実行時にモジュール状態が壊れ、クラッシュや `CRuntimeClass` の不整合につながる。
   - **新しく作るファイル (`pch.h`、`DllMain` の `.cpp` など) は、既存ファイルと同じ UTF-8 BOM + CRLF で保存する。** BOM なし・LF のまま日本語コメントを含めると、MFC のヘッダを巻き込んだコンパイルで、無関係に見える箇所 (`afxdllx.h` の内部など) に、原因不明の構文エラーが出ることがある。
3. **テスト exe:** 種類は、コンソール (`SubSystem=Console`) の exe。
   - 対応する DLL への `ProjectReference` (これで、インポートライブラリが、自動でリンクされる)。
   - `AdditionalIncludeDirectories` に、テスト対象の DLL のヘッダのフォルダ (と、ロジック側なら、データ層のインターフェースのフォルダ)。
   - MFC 拡張 DLL を参照するテストの場合: テスト exe 自身も `<UseOfMfc>Dynamic</UseOfMfc>` にする (同じ共有 MFC ランタイムにリンクするため)。MFC を使わない DLL だけを参照するテストは、従来どおり MFC なしでよい。
4. **GoogleTest (既定は vcpkg):** `vcpkg.json` (ソリューション直下) の `gtest`、トリプレット `x64-windows-static-md` (静的ライブラリ + 動的 CRT。`/MD` `/MDd` と合わせる)。
   - テスト exe の `.vcxproj` に、`<PropertyGroup Label="Vcpkg">` (`VcpkgEnableManifest`、`VcpkgTriplet`) がある。ライブラリのインクルードとリンクは、vcpkg の MSBuild 統合が、自動で行う (構成ごとに `debug\lib` / `lib` の `*.lib`)。
   - **`gtest_main` は、自動ではリンクされない** (`lib\manual-link\` にある)。テスト exe ごとに、自前の **`main.cpp`** (`InitGoogleTest` と `RUN_ALL_TESTS`) を置く。このため、出力に「Running main() from ...」の行は出ない。
   - 取得は、ウォッチャー経由 (`package_once.sh "vcpkg baseline" "vcpkg install"`)。`builtin-baseline` で版を固定する。バイナリキャッシュが効くので、2 回目以降は速い。GoogleTest は C++17 以上が必要 (生成するプロジェクトは C++20)。
   - 旧方式 (NuGet `Microsoft.googletest.v140.windesktop.msvcstl.static.rt-dyn` 1.8.1.8: `packages.config` とコピー) は、すでにその方式のソリューションだけ。`gtest_main` がリンクされるので、`main()` は書かない。
5. **ランタイム:** すべてのプロジェクトで、同じ CRT (動的 `/MD` `/MDd`) にそろえる。DLL の境界で `std::string` や `std::vector` を渡すため。
6. **PlatformToolset / C++ 標準 / 文字セット** は、全プロジェクトで同じにする。

## 新しい DLL とテスト exe を、組で作るとき (了承を得た場合)

**同梱の `scripts/add_layer.py` で作る** (手書きしない)。上の規約は、このスクリプトが生成する内容そのもの。

```bash
python3 <このSkillのフォルダ>/scripts/add_layer.py "$SLN_DIR" DataLayer
python3 <このSkillのフォルダ>/scripts/add_layer.py "$SLN_DIR" LogicLayer --uses DataLayer
python3 <このSkillのフォルダ>/scripts/add_layer.py "$SLN_DIR" DataLayer --tests none        # DLL だけ (テストなし)
python3 <このSkillのフォルダ>/scripts/add_layer.py "$SLN_DIR" DataLayer --tests-only        # すでにある DLL に、テストだけを足す
python3 <このSkillのフォルダ>/scripts/add_layer.py "$SLN_DIR" CoreLib --kind lib            # 静的ライブラリ (公開マクロなし)
```

- **`--tests none|gtest`** (既定 `gtest`): 層とテストは、独立した軸。`none` は、DLL だけ (テスト・GoogleTest は、作らない)。
- **`--tests-only`**: すでにある DLL (または静的ライブラリ) `<Name>` に、`<Name>Test` だけを足す。名前空間と参照は、既存のファイルから読む。
- **`--kind dll|lib|mfc-ext-dll|mfc-std-dll`** (既定 `dll`): `mfc-ext-dll` は MFC 拡張 DLL、`mfc-std-dll` は MFC 標準 DLL (下の「MFC 拡張 DLL を作るとき」「MFC 標準 DLL を作るとき」)。`lib` は静的ライブラリ。公開マクロ (`<Name>Api.h`) は作らず、`<Link>` の設定も出さない。テスト exe は、`ProjectReference` で、ライブラリを、リンクで取り込む (実行時に、DLL を、exe のそばに置く必要もない)。
- **GoogleTest:** テストを作るとき、vcpkg 方式なら、`vcpkg.json` に gtest を入れ、`.gitignore` に `vcpkg_installed/` を足す (ネットワークは使わない。出力: `GTEST_VCPKG`)。旧 NuGet 方式は、v2.31.0 で廃止 (`packages\` に旧方式のテストがあるソリューションでも、新しいテストは vcpkg。出力に `NOTE`)。
- **メインの exe を、保護する:** テストを作るとき、exe で、名前が `Test` / `Tests` で終わるメインのプロジェクト (GoogleTest を使わないもの) に、`<TargetName>$(ProjectName)_Main</TargetName>` を足す。ウォッチャーが、`*Test.exe` を、テストとして実行するため。
- **`--gtest auto|vcpkg|source|nuget`** (既定 `auto`): GoogleTest の入れ方。`vcpkg`: 上の 4.。`source`: `ThirdParty/googletest` のソースを、ソリューション内の静的ライブラリ `gtest` としてビルドする
  (vcpkg が使えないとき。ソースは、ウォッチャー経由で取得する: `/new-solution` の `gtest_once.sh`)。`nuget`: 旧方式 (NuGet のパッケージを、コピーして使う)。
  `auto`: すでに `gtest` プロジェクトがあれば `source`、`packages\` に NuGet の GoogleTest があれば `nuget`、それ以外は `vcpkg`。
  層を足すときは、**すでにあるソリューションと同じ方式**になる (`gtest` プロジェクト・`packages\` の有無で、判定される)。
- 最初のソリューション作成と、この組み合わせの指定は、`/new-solution` (`new_solution.py`) が行う。層の名前・種類 (`--layers logic:OrderLogic` / `--layer-kind lib` / `mfc-ext-dll` / `mfc-std-dll`) も、そちらで指定できる。

- DLL (`<Name>`) と、テスト exe (`<Name>Test`) を作り、`.sln` / `.slnx` に追加する。`--dry-run` で、内容だけを見られる。
- `.vcxproj.filters` も、あわせて生成する。`.h` は「ヘッダー ファイル」、`.cpp` は「ソース ファイル」、`.rc` は「リソース ファイル」フィルターに入れる (フィルター名・GUID は、日本語版 Visual Studio のウィザードが生成するものと同じ)。
  新しいファイルを追加するとき (手順 2.) は、`.vcxproj` だけでなく、この `.filters` にも、同じ対応で追加すること。
- `--uses <別のプロジェクト>`: そのフォルダを、インクルードパスに足す (ヘッダだけを使う。リンクしない)。ロジック DLL がデータ層のインターフェースを使う場合に付ける。
- 対応は、x64 の Debug / Release だけ。ソリューションに、x86 などの構成があっても、新しいプロジェクトは、そこには対応付けない。
- `.vcxproj` を作り直したいときは、フォルダと、ソリューションへの登録を、ユーザーに確認して消してから、やり直す (スクリプトは、既存を上書きしない)。
- **MFC 拡張 DLL を作るとき: `--kind mfc-ext-dll`** (`new_solution.py` では `--layer-kind mfc-ext-dll`。**メインが MFC のときだけ**。MFC のランタイムを持たない exe は、拡張 DLL を使えない)。Visual Studio の「MFC DLL」ウィザード (拡張 DLL) の出力に合わせて、次を作る。
  - DLL: `UseOfMfc=Dynamic`、`_AFXEXT` (`_USRDLL` は付けない)、`<Name>_EXPORTS`、プリコンパイル済みヘッダー (`pch.h` を Use、`pch.cpp` を Create、`dllmain.cpp` は NotUsing)、`framework.h` (`afxwin.h` / `afxext.h`)、`targetver.h`、`dllmain.cpp` (`AFX_EXTENSION_MODULE` / `AfxInitExtensionModule` / `CDynLinkLibrary` / `AfxTermExtensionModule` の定型コード)、ビルド確認用の `<Name>ModuleInfo.h/.cpp` (`.cpp` は先頭で `pch.h`)。
  - テスト exe: `UseOfMfc=Dynamic` (同じ共有 MFC ランタイム)。`_AFXEXT` は付けない。`--tests-only` で後からテストを足すときも、既存の DLL の `_AFXEXT` を見て、同じにする。
  - **ウィザードとの違い:** `.def` ファイル、`.rc` / `.rc2`、`Resource.h` は作らない (`__declspec` / `AFX_EXT_CLASS` で公開するので `.def` は不要。リソースを持つ DLL になったら、手で足す)。`framework.h` は、OLE・DB・DAO などを含まない最小限 (必要になったら足す)。`x86` の構成は作らない (x64 のみ)。
  - **公開の付け方:** `CObject` 派生クラスには `AFX_EXT_CLASS`、それ以外 (関数・値のクラス) には `<Name>_API`。新しい `.cpp` は、先頭で `#include "pch.h"` する (忘れると、`C1010` になる)。
  - **実機で未確認 (TEST-PLAN 2-25):** 生成した一式が、Visual Studio / MSBuild でビルドでき、テスト exe が実行できること。
- **MFC 標準 DLL を作るとき: `--kind mfc-std-dll`** (`new_solution.py` では `--layer-kind mfc-std-dll`。**メインは何でもよい** (MFC なしの exe からも使える))。Visual Studio の「MFC DLL」ウィザード (標準 DLL・共有 MFC) の出力に合わせて、次を作る。
  - DLL: `UseOfMfc=Dynamic`、`_USRDLL` (`_AFXEXT` は付けない)、`<NAME>_EXPORTS`、`pch.h` (Use) / `pch.cpp` (Create)、`<Name>.h` / `<Name>.cpp` (`C<Name>App : public CWinApp` と、グローバルな `theApp`。`dllmain.cpp` は作らない)、`framework.h` / `targetver.h`、ビルド確認用の `<Name>ModuleInfo.h/.cpp`。
  - **エクスポートする関数は、先頭 (オブジェクト変数の宣言よりも前) で `AFX_MANAGE_STATE(AfxGetStaticModuleState());` を呼ぶ** (共有 MFC のとき必須。呼ばないと、MFC のリソースやモジュールの状態が、呼び出し元の exe のものになる。MFC テクニカル ノート 33・58)。ビルド確認用の関数には、入れてある。
  - **MFC のオブジェクト (`CObject` 派生・`CString` など) を、DLL の境界で、受け渡さない** (標準 DLL は、MFC の型を共有しない)。必要なら、拡張 DLL (`mfc-ext-dll`)。公開は、関数と、値のクラス (`<Name>_API`)。
  - テスト exe: **MFC なし** (`UseOfMfc` なし)。標準 DLL は、MFC を自分で読み込む。`--tests-only` も同じ。
  - **ウィザードとの違い:** `.def`、`.rc` / `.rc2`、`Resource.h`、x86 の構成は作らない (`<Name>.h` は、`resource.h` を include しない)。リソースを持つ DLL になったら、手で足す。静的リンク (`UseOfMfc=Static`) は、選べない (共有 MFC のみ)。
  - **実機で未確認 (TEST-PLAN 2-26):** 生成した一式が、ビルドでき、MFC なしのテスト exe から、標準 DLL (共有 MFC) の関数を呼べること。
- **通常の DLL (既定) で、MFC の型が必要になったとき:** 後から拡張 DLL に変える手順は、上の「MFC 拡張 DLL のプロジェクト設定」に従って、`.vcxproj` を手で直す。この追加編集は、毎回、ユーザーに内容を示してから行う。

**作ったあと:**
1. `GTEST_VCPKG: no-baseline` なら、ウォッチャー経由で、`package_once.sh "vcpkg baseline" "vcpkg install"` を実行する (初回のみ)。
2. **ベースライン (ビルドと、ベースライン用の 1 件のテストが通ること) を確認する。** 通らなければ、環境や構成の問題を、先に直す。**この状態を作る前に、本物のテストを書かない。**
3. ビルド確認用の `<Name>ModuleInfo` とそのテストは、本物の機能とテストが入ったら、削除してよい (ユーザーに伝える)。
4. 通ったら、`cpp-test-first` の手順 (Red) に進む。

## 層の名前を、あとから変えるとき
層の名前は、既定 (`LogicLayer` / `DataLayer`) で作られる。変えるときは、**ユーザーの了承を得て**、次の箇所を、そろえて直す (一部だけ直すと、ビルドが通らなくなる)。

| 箇所 | 例 |
|---|---|
| フォルダ名、`.vcxproj` / `.vcxproj.filters` のファイル名 | `LogicLayer/LogicLayer.vcxproj` → `OrderLogic/OrderLogic.vcxproj` |
| `.sln` / `.slnx` の、プロジェクトのパスと名前 | `<Project Path="...">` |
| `.vcxproj` の `RootNamespace`、`<NAME>_EXPORTS` の定義 | `LOGICLAYER_EXPORTS` → `ORDERLOGIC_EXPORTS` |
| 公開マクロのヘッダと、マクロ名 | `LogicLayerApi.h` / `LOGICLAYER_API` → `OrderLogicApi.h` / `ORDERLOGIC_API` (使っている全ファイル) |
| ビルド確認用の `<Name>ModuleInfo.h/.cpp` と、関数名 | `LogicLayerModuleName` (あれば。本物の機能が入ったら、削除してよい) |
| テストのプロジェクト (`<Name>Test`) の、名前・フォルダ・`.vcxproj` | `LogicLayerTest` → `OrderLogicTest` (**名前は、`Test` で終わらせる**) |
| テストの `ProjectReference`、`AdditionalIncludeDirectories` (`$(ProjectDir)..\<Name>`) | ほかの DLL の、`--uses` 相当の参照も |
| `CLAUDE.md` の `- 層:` と、層の記述 | |

変更後は、必ず、ビルドと (テストありなら) 全テストが、通ることを確認する。

## よくある失敗

| 症状 | 原因 | 対処 |
|---|---|---|
| `LNK2019` (未解決の外部シンボル) | 新しいクラス・関数に、公開マクロがない | `<NAME>_API` を付ける |
| テスト exe の起動に失敗 (`ENV_ERROR`、終了コード `0xC0000135` など) | DLL が、exe と同じフォルダにない | 出力先を、そろえる (規約 1.) |
| `error LNK2038: mismatch detected for 'RuntimeLibrary'` | CRT (`/MD` と `/MT`) の不一致 | すべて、動的 CRT にそろえる |
| `PASSED` なのに、テストが走っていない | 新しい `Test*.cpp` が `.vcxproj` にない | 追加する |
| テストが、DLL の古い版を使っている | ビルドが、DLL を更新していない (参照の欠落) | テスト exe から DLL への `ProjectReference` を確認する |
| 実行時にクラッシュ、または `CObject` 派生クラスの型情報がおかしい (MFC 拡張 DLL) | `UseOfMfc` が `Dynamic` でない (静的リンク)、または `_AFXDLL`/`_AFXEXT` 定義や `AFX_MANAGE_STATE` の定型コードが不足 | 「MFC 拡張 DLL のプロジェクト設定」の項目を、すべて満たしているか確認する |
| `LNK2005: DllMain は既に ... で定義されています` (`mfcs1xx(u)(d).lib`) | `_USRDLL` と `_AFXEXT` を同時に定義している | プリプロセッサ定義から `_USRDLL` を外す |
| `afxdllx.h` 等、MFC のヘッダ内部で、原因不明の構文エラー (`BOOL`/`WINAPI` が未定義、など) | 2 つのことが考えられる: (1) 新しいファイルが `PrecompiledHeader: NotUsing` のまま `<afxwin.h>` を生で読み込んでいる (2) 新しいファイルが UTF-8 BOM なし・LF で保存されている | (1) `PrecompiledHeader` を `Use` にし、`pch.h` 経由にする (2) ファイルを、既存と同じ UTF-8 BOM + CRLF で保存し直す |
