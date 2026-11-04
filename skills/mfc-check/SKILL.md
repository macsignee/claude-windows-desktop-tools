---
name: mfc-check
description: MFC のプロジェクトの「コンパイルは通るが、実行時に壊れる」部分 (リソース ID の重複・未定義、メッセージマップとハンドラの不整合、ダイアログと DDX の不整合、層の依存の違反、MFC の DLL (拡張 DLL・標準 DLL) の設定の食い違い) を、静的に検査して、要約を返す手順。ボタンやメニューが反応しない、`.rc` / `resource.h` / メッセージマップを編集した、ライブラリ (DLL) に GUI の依存が混ざっていないか確かめたい、といった依頼で使う。Windows のウォッチャーは不要 (読み取りだけ)。
---

# MFC の「見えない部分」の検査 (mfc-check)

MFC は、メッセージマップ (`BEGIN_MESSAGE_MAP`) とリソース ID (`resource.h` / `.rc`) の対応が、**文字列とマクロで結ばれている**ため、
対応が崩れても、**コンパイルは通り、実行したときに、ボタンが反応しない・メニューが効かない**という形で現れる。
このスキルは、その対応を、静的に検査する。ビルド (`auto-build`) とは別で、**ウォッチャーも、Windows も、要らない**。

## 実行

```bash
python3 -I <このSkillのフォルダ>/scripts/mfc_check.py "$PROJ"
```

- `$PROJ`: ソリューションまたはプロジェクトのフォルダ。以下の `.vcxproj` を、プロジェクトとして検査する。
- 読み取りだけ。ファイルは、変えない。`.rc` は UTF-16 / UTF-8 (BOM) / CP932 のどれでも読める。
- 既定は、error と warning だけを出す。`--all` で、info (参考) も出す。`--json <ファイル>` で、全件を JSON に書く。
- 層の判定 (ロジック / データ) は、プロジェクト名の `Logic` / `Data` で決める。名前が違うときは、`--logic <名前>` / `--data <名前>` で指定する。

| 終了コード | 意味 | 次の行動 |
|---|---|---|
| 0 | error なし (warning はあるかもしれない) | warning を、読んで、判断する |
| 1 | error あり | 下記の方針で、直す |
| 2 | 引数が不正 | フォルダを確認する |
| 3 | 検査する対象がない (`.rc` もメッセージマップもライブラリもない) | MFC のプロジェクトではない。報告して終わり |

## 出力の読み方

```
mfc-check: error 1 / warning 1 (1 projects: GDiGraphicsSample)
[1] error   RES001 未定義の ID: ID_FOO (resource.h にない)
      GDiGraphicsSample.rc(173)
[2] warning MAP005 GDiGraphicsSampleView::OnFilePrintPreview: afx_msg で宣言されているが、メッセージマップに登録されていない
      GDiGraphicsSampleView.h(47)
```
- 見出し: 件数と、検査したプロジェクト。`[n]` は、重大度順 (error → warning → info)、同じ重大度の中では、プロジェクト・コード順。
- 2 行目は、`ファイル(行)`。ファイルは、`$PROJ` からの相対パス。
- 出力は最大 40 行。足りないときは、`--max-lines` を増やすか、`--json` を読む。

## 検査の一覧と、直し方

| コード | 重大度 | 内容 | 直し方 |
|---|---|---|---|
| RES001 | error | 未定義の ID (コード・`.rc` で使っているが `resource.h` にない) | `resource.h` に `#define` を足す (値は、衝突しない値)。`_APS_NEXT_*` の値も、更新する。 |
| RES001 | warning | 名前付きリソース (`.rc` のリソース定義の名前が、`resource.h` にない) | 数値 ID で参照するなら、`resource.h` に足す。意図した名前付きリソースなら、そのまま。 |
| RES002 | error | コマンド ID の値が重複 | 片方の値を、`_APS_NEXT_COMMAND_VALUE` 以降の、空いた値に変える。 |
| RES003 | error | 同じダイアログ内で、コントロール ID の値が重複 | 片方を、`_APS_NEXT_CONTROL_VALUE` 以降の値に変える。 |
| RES004 | error | 同じ種類のリソースで、別の名前が同じ値 | 片方を、空いた値に変える。 |
| RES005 | info | `resource.h` にあるが、どこでも使われていない ID | ウィザードの残りのことが多い。消さなくてよい。 |
| MAP001 | error | マップのハンドラが、クラスに宣言されていない | ヘッダーに `afx_msg void OnXxx();` を足す (または、マップの綴りを直す)。 |
| MAP002 | error | ハンドラが、宣言だけで、定義がない | `.cpp` に定義を足す (または、宣言とマップの項目を消す)。 |
| MAP003 | error | `BEGIN_MESSAGE_MAP` があるが、クラスに `DECLARE_MESSAGE_MAP` がない | クラス宣言に `DECLARE_MESSAGE_MAP()` を足す。 |
| MAP004 | error | `DECLARE_MESSAGE_MAP` があるが、`BEGIN_MESSAGE_MAP` がない | `.cpp` に `BEGIN/END_MESSAGE_MAP` を足す (リンクエラーの原因)。 |
| MAP005 | warning | `afx_msg` の宣言が、マップに未登録 (呼ばれない) | マップに項目を足す。使わないなら、宣言を消す。 |
| MAP006 | warning | ハンドラの引数の数が、マクロの想定と違う | 想定の署名に直す (`ON_COMMAND` は引数なし、`ON_UPDATE_COMMAND_UI` は `CCmdUI*` など)。 |
| MAP007 | warning | 同じマップに、同じ ID の `ON_COMMAND` が重複 | 後ろのものは呼ばれない。不要な方を消す。 |
| MAP008 | info | ハンドラに `afx_msg` が付いていない | 動作に影響しない。 |
| UI001 | warning | `ON_COMMAND` の ID が、`.rc` のメニュー・アクセラレータ・ツールバーにない | メニューなどに項目を足す。コードから送る (`PostMessage`) 場合は、そのまま。 |
| UI002 | warning | コントロール通知の ID が、`.rc` のダイアログにない | ダイアログにコントロールを足す。コードで作る場合は、そのまま。 |
| UI003 | warning | `DDX_*` / `DDV_*` の ID が、`.rc` のどのダイアログにもない (ダイアログクラスと分からない場合) | ダイアログに足す。 |
| UI004 | warning | **UI テストのプロジェクト (`*.UITests`) があるとき**、ダイアログの**操作できるコントロール** (ボタン・エディット・コンボ・リスト・チェックボックス・`CONTROL` の button / edit など。静的テキスト・グループボックス・アイコンは、対象外) の ID が `IDC_STATIC` (`-1`) のまま、または、同じダイアログで ID が重複している (UI テストの **AutomationId = コントロール ID** なので、ID で探せない) | 固有の ID (`IDC_xxx`) を付ける (`resource.h` に、定義を足す)。ID を変えたら、コードの `DDX` / メッセージマップも、変える。 |
| DLG001 | error | `DDX_*` / `DDV_*` の ID が、**そのクラスのダイアログ** (`IDD`) にない | ダイアログにコントロールを足す (または、DDX の ID を直す)。実行時に、アサート (`Error: no data exchange control with ID 0x....`) や例外になる。**ただし、`DDX_Control` は、メンバーが接続済みなら、コントロールを探さないので、その場合は、何も起きない (参照は、誤りのまま)。** |
| DLG002 | error | ダイアログクラスの `IDD` が、`.rc` に DIALOG として存在しない (別の種類のリソースの場合も) | `.rc` にダイアログを足す (または、`IDD` を直す)。`DoModal` / `Create` が失敗する。 |
| DLG003 | error | `DDX_Control` のメンバーの型が、コントロールの種類と合わない (例: `EDITTEXT` に `CListCtrl`) | メンバーの型を、コントロールに合わせる (または、`.rc` のコントロールを直す)。実行時に、コントロールが期待どおりに動かない (症状は、コントロールの種類による)。 |
| DLG004 | warning | ダイアログのボタンに、ハンドラがない (押しても何も起きない) | `ON_BN_CLICKED` を足す。`IDOK` / `IDCANCEL` と、コードで使っている ID は、対象外。 |
| DLG005 | warning | ダイアログに、既定ボタン (`DEFPUSHBUTTON`) が複数ある | 1 つだけにする。 |
| DLG006 | warning | `OnInitDialog` が、基底クラスの `OnInitDialog` を呼んでいない | `CDialogEx::OnInitDialog();` を、先頭で呼ぶ (コントロールの初期化と DDX が、行われなくなる)。 |
| DLG007 | warning | `DoDataExchange` が、基底クラスの `DoDataExchange` を呼んでいない | `CDialogEx::DoDataExchange(pDX);` を、先頭で呼ぶ。 |
| DLG008 | info | 同じダイアログに、同じニーモニック (`&X`) が重複 | 動作に影響しない (キー操作が、混乱する)。 |
| DLG010 | warning | 同じメンバーを、別の ID に対して、複数の `DDX_Control` に渡している | メンバーを、ID ごとに分ける (コピー&ペーストの誤りに多い)。**2 回目以降は、実行時に何も起きず、警告も出ない** (MFC は、接続済みのメンバーを探さない)。`if` / `else` の分岐ごとに渡す書き方は、指摘しない。 |
| DLG009 | info | `AFX_DIALOG_LAYOUT` が、存在しないダイアログのもの | VS が残した不要な定義。消してよい (`.rc` を編集する注意に従う)。 |
| LAY001 | error | ライブラリ (DLL / lib) で、GUI のクラス (`CWnd` `CDialog` `AfxMessageBox` など) を使っている | UI の処理を、メイン側に移す。ロジックは、GUI に依存させない (`CLAUDE.md` の層の規則)。 |
| LAY002 | warning | ライブラリで、GUI のヘッダー (`afxwin.h` など) を include している (`pch.h` / `framework.h` は info。**MFC の DLL (拡張 DLL・標準 DLL) の層は、すべて info**) | 必要か確認する。MFC の DLL なら、意図した include なので、そのままでよい。 |
| LAY003 | error | プロジェクト参照の向きが、層 (UI → ロジック → データ) に反する | 参照を逆にするか、共通部分を下の層に移す。 |
| DLL001 | error | `_USRDLL` と `_AFXEXT` が、同じ構成で、両方定義されている | 標準 DLL (`_USRDLL`) か、拡張 DLL (`_AFXEXT`) の、どちらか 1 つにする。 |
| DLL002 | error | 拡張 DLL (`_AFXEXT`) だが、`UseOfMfc` が `Dynamic` でない | 拡張 DLL は、共有 MFC が必須。`UseOfMfc` を `Dynamic` にする。 |
| DLL003 | warning | `UseOfMfc` が有効だが、`_USRDLL` も `_AFXEXT` も定義されていない | 標準 DLL なら `_USRDLL`、拡張 DLL なら `_AFXEXT` を足す (`cpp-test-first` の `DLL-LAYOUT.md`)。 |
| DLL004 | warning | 標準 DLL (`_USRDLL` + MFC) に、`CWinApp` 派生のクラス (と、グローバルの `theApp`) がない | `CWinApp` 派生と `theApp` を足す。MFC の初期化 (`InitInstance`) が、行われない。 |
| DLL005 | error | 拡張 DLL に、`AfxInitExtensionModule` がない (`DllMain`) | `DllMain` で、`AfxInitExtensionModule` を呼ぶ。リソースや `CObject` の動的生成が、実行時に壊れる。 |
| DLL006 | warning | 拡張 DLL に、`new CDynLinkLibrary` または `AfxTermExtensionModule` がない | `DllMain` に足す (リソース チェーンへの追加と、終了時の後始末)。 |
| DLL007 | warning | **標準 DLL (共有 MFC)** の公開関数 (`<名前>_API` / `__declspec(dllexport)` の関数) が、先頭で `AFX_MANAGE_STATE` を呼んでいない | 関数の先頭 (オブジェクトの宣言よりも前) で、`AFX_MANAGE_STATE(AfxGetStaticModuleState());` を呼ぶ。MFC のリソースやモジュールの状態が、呼び出し元の exe のものになる。 |
| DLL008 | error | 拡張 DLL を参照する exe / DLL の `UseOfMfc` が `Dynamic` でない (MFC なしの exe も) | 参照する側も、`UseOfMfc=Dynamic` にする (MFC のランタイムが、2 つになるのを防ぐ)。テスト exe も、同じ。 |

## ループのルール
1. **`.rc` / `resource.h` / メッセージマップ / ライブラリの構成を編集したら、編集のあとで、実行する。** 編集していない状態で再実行しない。
2. error は、すべて直す。warning は、**自分が今回編集した箇所に関係するもの**だけ直し、ほかは、報告に 1 行で添える (無関係な修正はしない)。info は、読まない。
3. 直したら、再実行して、error が減ったことを確認する。**最大 3 回**。同じ error が残るなら、停止して、原因 (誤検出の疑いを含む) を報告する。
4. error がなければ (終了コード 0)、続けて、ビルド (`auto-build`) に進んでよい。ビルドが通っても、この検査の warning は、残りうる。

## 編集のときの注意
- **ウィザード生成の `.rc` は、UTF-16 (BOM 付き) のことが多い。** 文字列一致のエディタ (Edit ツールなど) は、UTF-16 を正しく扱えないことがある。`.rc` を編集するときは、Python で `open(path, 'rb').read().decode('utf-16')` を試し、バイト列として読み書きし、`utf-16` (BOM 付き) で書き戻す。
- `resource.h` の `_APS_NEXT_*` (次に割り当てる値) を、手で ID を足したあとに、更新する (VS のリソースエディタは、これを使って、次の ID を決める)。
- ウィザード生成のクラスのメッセージマップは、書式を直さない。
- **VS のウィザード (「イベント ハンドラーの追加」など) で足した直後は、未保存のファイルがある。** ウィザードは、編集を、エディタ上で行い、保存するまで、ディスクに書かない。チェッカーは、**ディスク**を読むので、保存前は、「マップにあるが、宣言がない」(MAP001) など、一時的な不整合が出る。**ユーザーに、「すべて保存」(Ctrl+Shift+S) を頼んでから、再実行する。** 保存後も残る場合に、初めて、本物の不整合として、扱う。
- **VS は、`Resource.h` を `resource.h` (小文字) として、保存し直すことがある。** Windows では、同じファイルだが、git は、別の名前として扱い、`git status` に、`M Resource.h` と `?? resource.h` が、同時に出る。**ファイル名の大文字小文字は、AI が、勝手に直さず、ユーザーに伝える** (`git restore` では、名前が戻らないことがある)。

## UI デザインガイドラインの検査
この検査は、**実行時に壊れる部分**を見る。画面の**設計** (ボタンの並び・既定のボタン・アクセスキー・アクセシブル名・DPI・色・メッセージなど) は、UI デザインガイドラインで、`/ui-design-review` が扱う (`ui_guideline_check.py` は、MFC の画面の、一部の規則を、静的に検査する)。

## 誤検出と限界
- **静的解析**。実行はしない。マクロで生成した ID や、複雑な `#ifdef` は、解釈できないことがある (誤検出のときは、報告に書く)。
- 標準の ID (`ID_FILE_*` `ID_EDIT_*` `ID_APP_*` `AFX_*` `IDOK` など) は、`afxres.h` を読まず、名前の規則 (接頭辞) で判定する。
- 基底クラスのハンドラ (`ON_COMMAND(ID_X, &CWinApp::OnFileNew)` のように、別のクラスで修飾したもの) は、宣言・定義の検査から外す。
- **継承したハンドラ:** プロジェクト内の基底クラスが宣言・定義していれば、派生クラスのマップに書いてよい (`ON_WM_KEYDOWN()` を、基底の `OnKeyDown` で受けるなど)。MFC の基底が持つ `ON_WM_xxx` の既定のハンドラは、宣言がなくても、合法なので、指摘しない。
- **入れ子のクラス** (`BEGIN_MESSAGE_MAP(Outer::Inner, CEdit)`) と、宣言の末尾の `final` / `override` / `= 0` は、解釈できる。
- `AFX_DIALOG_LAYOUT` の見出しと、`DESIGNINFO` の中の ID は、VS のメタデータなので、「使用」に数えない。
- `ON_WM_xxx` は、代表的なもの (`ON_WM_SIZE` など) だけ、引数の数を検査する。ほかは、名前の一致だけを見る。
- コードで、動的に作るダイアログやコントロールは、UI001〜UI003 と DLG004 の、誤検出になりうる (その ID を、マップの外で使っていれば、除く)。
- **ダイアログクラスの判定:** 基底が `CDialog` / `CDialogEx` / `CPropertyPage` / `CFormView` / `CDHtmlDialog` (派生の派生も含む)。ダイアログの ID は、`enum { IDD = ... }` か、コンストラクタの基底の初期化 (`CDialogEx(IDD_X)`) から読む。どちらもなければ、そのクラスのダイアログ検査 (DLG001〜DLG004) は、行わない。
- **DLG010 (同じメンバーの、複数の `DDX_Control`):** `DoDataExchange` の中で、`else` / `case` / `default` をまたぐ 2 つの呼び出しは、分岐ごとの書き方として、除く。
- **`DDX_Control` の型の検査 (DLG003) は、MFC 標準のコントロールクラス** (`CEdit` `CListCtrl` `CComboBox` など) **だけ。** 自作の派生クラスは、判定しない。
- **DLG004 (ボタンのハンドラ) は、`ON_*_RANGE` があるクラスでは、行わない。** 親ウィンドウがコマンドを受ける設計 (モードレスなど) は、誤検出になりうる。
- 層の判定は、プロジェクト名 (`Logic` / `Data`) と、`.vcxproj` の種類による。テストプロジェクト (名前が `Test` で終わる) は、対象外。
- **MFC の DLL の検査 (DLL001〜DLL008):** `.vcxproj` の `UseOfMfc` と `PreprocessorDefinitions` (構成ごと) と、ソースの文字列で判定する。`.def` でエクスポートする関数、`extern "C"` でマクロなしの関数は、DLL007 の対象外 (公開の関数は、`<名前>_API` / `__declspec(dllexport)` のマクロで探す)。クラスのメンバー関数 (`class <名前>_API Foo`) も、DLL007 の対象外 (自由関数だけ)。静的 MFC (`UseOfMfc=Static`) の標準 DLL は、`AFX_MANAGE_STATE` が不要なので、DLL007 を出さない。プロパティシート (`.props`) で定義した `_AFXEXT` などは、読まない。
