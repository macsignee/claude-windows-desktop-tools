---
name: mfc-check
description: MFC のプロジェクトの「コンパイルは通るが、実行時に壊れる」部分 (リソース ID の重複・未定義、メッセージマップとハンドラの不整合、ダイアログと DDX の不整合、層の依存の違反) を、静的に検査して、要約を返す手順。ボタンやメニューが反応しない、`.rc` / `resource.h` / メッセージマップを編集した、ライブラリ (DLL) に GUI の依存が混ざっていないか確かめたい、といった依頼で使う。Windows のウォッチャーは不要 (読み取りだけ)。
---

# MFC の「見えない部分」の検査 (mfc-check)

MFC は、メッセージマップ (`BEGIN_MESSAGE_MAP`) とリソース ID (`resource.h` / `.rc`) の対応が、**文字列とマクロで結ばれている**ため、
対応が崩れても、**コンパイルは通り、実行したときに、ボタンが反応しない・メニューが効かない**という形で現れる。
このスキルは、その対応を、静的に検査する。ビルド (`cpp-auto-build`) とは別で、**ウォッチャーも、Windows も、要らない**。

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
| DLG001 | error | `DDX_*` / `DDV_*` の ID が、**そのクラスのダイアログ** (`IDD`) にない | ダイアログにコントロールを足す (または、DDX の ID を直す)。実行時に、アサートや例外になる。 |
| DLG002 | error | ダイアログクラスの `IDD` が、`.rc` に DIALOG として存在しない (別の種類のリソースの場合も) | `.rc` にダイアログを足す (または、`IDD` を直す)。`DoModal` / `Create` が失敗する。 |
| DLG003 | error | `DDX_Control` のメンバーの型が、コントロールの種類と合わない (例: `EDITTEXT` に `CListCtrl`) | メンバーの型を、コントロールに合わせる (または、`.rc` のコントロールを直す)。実行時に、コントロールが期待どおりに動かない (症状は、コントロールの種類による)。 |
| DLG004 | warning | ダイアログのボタンに、ハンドラがない (押しても何も起きない) | `ON_BN_CLICKED` を足す。`IDOK` / `IDCANCEL` と、コードで使っている ID は、対象外。 |
| DLG005 | warning | ダイアログに、既定ボタン (`DEFPUSHBUTTON`) が複数ある | 1 つだけにする。 |
| DLG006 | warning | `OnInitDialog` が、基底クラスの `OnInitDialog` を呼んでいない | `CDialogEx::OnInitDialog();` を、先頭で呼ぶ (コントロールの初期化と DDX が、行われなくなる)。 |
| DLG007 | warning | `DoDataExchange` が、基底クラスの `DoDataExchange` を呼んでいない | `CDialogEx::DoDataExchange(pDX);` を、先頭で呼ぶ。 |
| DLG008 | info | 同じダイアログに、同じニーモニック (`&X`) が重複 | 動作に影響しない (キー操作が、混乱する)。 |
| DLG009 | info | `AFX_DIALOG_LAYOUT` が、存在しないダイアログのもの | VS が残した不要な定義。消してよい (`.rc` を編集する注意に従う)。 |
| LAY001 | error | ライブラリ (DLL / lib) で、GUI のクラス (`CWnd` `CDialog` `AfxMessageBox` など) を使っている | UI の処理を、メイン側に移す。ロジックは、GUI に依存させない (`CLAUDE.md` の層の規則)。 |
| LAY002 | warning | ライブラリで、GUI のヘッダー (`afxwin.h` など) を include している (`pch.h` / `framework.h` は info) | 必要か確認する。MFC 拡張 DLL の `framework.h` なら、そのままでよいことが多い。 |
| LAY003 | error | プロジェクト参照の向きが、層 (UI → ロジック → データ) に反する | 参照を逆にするか、共通部分を下の層に移す。 |

## ループのルール
1. **`.rc` / `resource.h` / メッセージマップ / ライブラリの構成を編集したら、編集のあとで、実行する。** 編集していない状態で再実行しない。
2. error は、すべて直す。warning は、**自分が今回編集した箇所に関係するもの**だけ直し、ほかは、報告に 1 行で添える (無関係な修正はしない)。info は、読まない。
3. 直したら、再実行して、error が減ったことを確認する。**最大 3 回**。同じ error が残るなら、停止して、原因 (誤検出の疑いを含む) を報告する。
4. error がなければ (終了コード 0)、続けて、ビルド (`cpp-auto-build`) に進んでよい。ビルドが通っても、この検査の warning は、残りうる。

## 編集のときの注意
- **ウィザード生成の `.rc` は、UTF-16 (BOM 付き) のことが多い。** 文字列一致のエディタ (Edit ツールなど) は、UTF-16 を正しく扱えないことがある。`.rc` を編集するときは、Python で `open(path, 'rb').read().decode('utf-16')` を試し、バイト列として読み書きし、`utf-16` (BOM 付き) で書き戻す。
- `resource.h` の `_APS_NEXT_*` (次に割り当てる値) を、手で ID を足したあとに、更新する (VS のリソースエディタは、これを使って、次の ID を決める)。
- ウィザード生成のクラスのメッセージマップは、書式を直さない。

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
- **`DDX_Control` の型の検査 (DLG003) は、MFC 標準のコントロールクラス** (`CEdit` `CListCtrl` `CComboBox` など) **だけ。** 自作の派生クラスは、判定しない。
- **DLG004 (ボタンのハンドラ) は、`ON_*_RANGE` があるクラスでは、行わない。** 親ウィンドウがコマンドを受ける設計 (モードレスなど) は、誤検出になりうる。
- 層の判定は、プロジェクト名 (`Logic` / `Data`) と、`.vcxproj` の種類による。テストプロジェクト (名前が `Test` で終わる) は、対象外。
