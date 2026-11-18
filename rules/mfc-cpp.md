---
paths:
  - "**/*Dlg.cpp"
  - "**/*Dlg.h"
  - "**/*View.cpp"
  - "**/*View.h"
  - "**/*Doc.cpp"
  - "**/*Doc.h"
  - "**/MainFrm.cpp"
  - "**/MainFrm.h"
  - "**/*Frame.cpp"
  - "**/*Frame.h"
---

# MFC コーディング規約 (ユーザー共通)

対象: **MFC を使うコード** (MFC のメイン (`mfc` / `mfc-mdi` / `mfc-dialog`)、MFC 拡張 DLL・MFC 標準 DLL の層)。**MFC を使わない Win32・コンソール・DLL・静的ライブラリには、適用しない。** C++ の共通の規則 (書式・命名・ポインタ・COM・関数の大きさなど) は、`cpp-common.md` を先に守る。**プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、そちらを優先する。**

**読み込み:** 上の `paths` は、MFC のウィザードが作る、典型的なファイル名だけ。MFC のプロジェクトの `CLAUDE.md` が、この文書を読むよう指示する (生成物は、そう書く)。MFC を使う、ほかのファイル (層の `.cpp` など) を、先に編集するときは、この文書を読む。

## ビルド
- **既定は Unicode ビルド** (`_T()` / `CString`)。**MBCS (ANSI) も許容する** (`CString` が `CStringA` になる揺らぎは、画面モデルの契約に `CString` を出さず、MFC 側の境界の補助 `ToCString` / `ToWString` で吸収する。下の「検査・失敗・文章」)。MFC は動的リンク (共有 MFC。`UseOfMfc=Dynamic`)。

## Win32 API と MFC のメンバー
- **MFC のクラスの内側で、Win32 API を呼ぶときは、`::` が必須。** 同じ名前の MFC メンバー (`GetClientRect` `GetWindowRect` `SetWindowText` `MessageBox` `InvalidateRect` `GetDC` `ReleaseDC` `SelectObject` `DeleteObject` `CreateCompatibleDC` など) があると、`::` がないと、MFC のメンバー関数 (クラスの内側では、こちらが先に見つかる) を呼んでしまい、引数や動作が違う。
  ```cpp
  ::GetClientRect(hWnd, &rect);          // Win32 API (CWnd::GetClientRect ではない)
  CWnd::GetClientRect(&rect);            // これは MFC のメンバー (引数の形も違う)
  ```
- 初回の呼び出しには、`// Win32 API (CWnd::〜 ではない)` の短いコメントを添えてよい。
- 判断に迷うときは、「`CWnd` などに、同じ名前のメソッドがあるか」で見る。

## ポインタ (MFC)
- **スマートポインタを使わなくてよいもの** (MFC が、寿命を決めているオブジェクト):
  - `CWnd` 派生 (`PostNcDestroy` で自己削除するもの) と、ドキュメント・ビュー・フレーム (テンプレートが管理する `CDocument` `CView` `CFrameWnd`)。
  - `CObject` 派生のオブジェクトで、MFC のコレクション (`CTypedPtrArray` など) が所有するもの、`DECLARE_DYNCREATE` / `DECLARE_SERIAL` で動的に生成されるもの。
  - 判断は、「**そのオブジェクトの寿命を、MFC が決めているか**」。決めているなら、除外。

## MFC のクラスのメンバーへのアクセス
- **MFC のクラスの `public` / `protected` メンバー変数 (`CWnd::m_hWnd`、`CView::m_pDocument` (`protected`。派生クラスから触れる)、`CWinApp::m_pMainWnd` など) を、直接、読み書きしない。** ラッパー関数を使う。

  | 直接 (使わない) | ラッパー |
  |---|---|
  | `m_hWnd` | `GetSafeHwnd()` (ウィンドウがなくても、安全に `NULL` を返す) |
  | `m_pDocument` | `GetDocument()` (ビュー側。自分の型に、キャストして返す) |
  | `m_pMainWnd` | `AfxGetMainWnd()` |

  - `m_hWnd` を書き換える (代入) 代わりに、`Attach` / `Detach` を使う。
  - **ラッパー関数の実装そのものは、メンバーに触れてよい** (例: `GetDocument()` の定義の中の `m_pDocument`)。VS ウィザード生成の既存の行も、そのまま。新しく書く行から、この規則を適用する。
  - ラッパーがない `public` メンバーは、直接触らずに、ラッパー (アクセサ) を、自分のクラスに足せないかを、先に検討する。


## MFC のコレクション
- **シリアライズするデータのコレクションは、標準ライブラリのコンテナではなく、MFC のコレクションを優先する** (`CArray` `CList` `CMap` `CTypedPtrArray` `CStringArray` など。`CArchive` で、そのまま読み書きできる)。判断は、「**その中身が、`CArchive` に書かれる・読まれるか**」。シリアライズしない内部の作業用データは、標準ライブラリのコンテナでよい。
- **MFC のコレクション (`CArray` `CList` `CMap` `CStringArray` `CTypedPtrArray` など) を、イテレータ (範囲 `for`、`std::ranges`) で操作できるようにする、ライブラリ・関数・クラスを使うことを、推奨する** (必須ではない。使わなくてもよい)。C++20 の反復子の要件を満たす `begin()` / `end()` (自由関数) を提供する形が、使いやすい。プロジェクトに、すでに、そのようなものがあれば、それを使う。
  ```cpp
  for (const auto& point : points)   // CArray<CPoint>
  {
      ...
  }
  ```
  - **一例:** 自作の `mfciterators.h` (`CArray` `CStringArray` `CList` `CMap` `CTypedPtrArray` などに対応し、`IsMFCArray` などの `concept` で、MFC のコレクションを判定する)。どれを使うかは、プロジェクトで決める (特定のファイルに、固定しない)。

## 名前 (MFC)
- クラスウィザードで作るクラスの名前は、ウィザードの「クラス名」を、`C` なしに直してから作る (`cpp-common.md` の命名)。MFC のクラスから派生しても、自分のクラスなら `C` を付けない (例: `CObject` 派生の `Shape`)。

## 名前空間と、CObject 派生のクラス
- **CObject 派生のクラスは、名前空間に入れない (グローバルに置く)。** `CDialog`・`CView`・`CDocument`・`CFrameWnd`・`CWinApp`・`CCmdTarget` など、MFC のクラスから派生したクラスは、すべて CObject 派生。
  - **理由:** MFC の実行時のクラス情報のマクロ (`DECLARE_DYNAMIC` / `IMPLEMENT_DYNAMIC` / `IMPLEMENT_SERIAL` / `RUNTIME_CLASS`) は、クラス名を、`class##class_name` や `_init_##class_name` のように、**トークンを連結**し、`#class_name` で**文字列にする**。名前空間つきの名前 (`ns::Foo`) を渡すと、`classns::Foo` になり、コンパイルできない。共有 MFC (`_AFXDLL`) の `RUNTIME_CLASS` は、たまたま通るが、静的 MFC では通らない。**実機で確認 (共有 MFC): `IMPLEMENT_DYNAMIC(app::CSampleDlg, CDialog)` は、`C3083 'classapp'` でビルドできない。マクロだけを、名前空間の中に書いても、`.cpp` の残りの定義 (コンストラクター・`BEGIN_MESSAGE_MAP` など) も、同じ名前空間に入れないと、通らない (実用的でない)。**また、実行時のクラス名 (`CRuntimeClass::m_lpszClassName`) には、名前空間が入らないので、**別の名前空間の、同名のクラスと、衝突する** (シリアライズは、クラス名の文字列で、クラスを復元する)。
  - **CObject 派生でないクラス** (ロジックのクラス、値のクラス、自由関数) は、名前空間に入れてよい。
- **CObject 派生のクラスには、`DECLARE_DYNAMIC` / `DECLARE_DYNCREATE` / `DECLARE_SERIAL` のどれかを書く** (宣言に、マクロがないクラスは、実行時のクラス情報が、基底クラスのものになり、正しい宣言ではない)。`.cpp` に、対応する `IMPLEMENT_DYNAMIC` / `IMPLEMENT_DYNCREATE` / `IMPLEMENT_SERIAL` を書く。**例外: `CWinApp` / `CWinThread` 派生** (アプリケーション・スレッドのクラス。ウィザードも、マクロを書かない)。
- (`mfc-check` の NSP001 / DEC001 が検査する。どちらも warning。)

## 画面モデルと MFC のダイアログ
画面モデルの考え方は、WPF (ViewModel)・WinForms と共通 (契約は、`winforms-view-model.md` の 2 章。MFC では、**役割の名前を `ScreenModel` と呼ぶ**)。Document/View は、対象外 (ただし、`CFormView` は、例外的に Document/View なので、更新の経路の表に載せる)。**SDI・MDI のメインのビュー (`CView`) だけが、画面モデルの例外。SDI・MDI のアプリでも、ダイアログ・`CFormView`・画面 DLL は、画面モデルで作る。業務の規則は、View・Document に書かず、ロジック層に置く。****共通部品 (`Observable`、`ValidationError`、`RepositoryException` (文章は `GetText()`)、`ToCString` / `ToWString` など) は、`add_ui_host.py` が生成する** (画面モデルは、ヘッダーだけ。ロジック層があればそこに、なければ UI DLL に置く)。

### 画面モデルの必須と命名
- **画面モデルは、すべてのダイアログで必須 (例外なし)。** 表示専用や、入力が 1 つだけの単純なダイアログでも置く (ダイアログが、リポジトリ・Model を直接使う構成は、採らない)。計画には、画面モデルの行を、必ず書く。
- 名前は `<画面名>ScreenModel` (本物)、インターフェースは `<画面名>ScreenModelInterface`、Fake は `Fake<画面名>ScreenModel` (命名は `cpp-common.md`)。ダイアログは、コンストラクターで、インターフェースの参照を受け取る。
- **画面モデルは、ロジック層に置き、ウィンドウのラッパー (`CWnd`・`CDialog`・`CEdit` など。`HWND` も)、Document/View などの MFC のフレームワーク、リソース ID を使わない。** 一方、**`CString`、`CArray` などのコレクション、データを保持する、またはモデルを実装する CObject 派生のクラスは、ロジック層・データ層で使ってよい** (CObject 派生は、名前空間に入れず、`DECLARE_DYNAMIC` などを書く。上の規則)。コレクションの操作に拡張が必要なときは、別途、C++ のイテレーターの実装を足す。
- **`mfc-check` が検査する:** SCM001 (画面モデルが、ウィンドウのラッパー・`HWND`・Document/View を使う)、SCM002 (画面モデルが、リソース ID を使う)、LAY004 (ダイアログが、リポジトリを直接参照する)。いずれも warning。

### 操作の受け方
- ID ごとにハンドラを置き、ハンドラは画面モデルのメソッドを呼ぶ数行だけにする。
- 中で `switch (nID)` する 1 つのハンドラにはしない。メッセージマップとの対応が見えなくなり、`mfc-check` の整合の検査も効かなくなるため。
- まとめてよいのは、同じ意味の ID の並び (ラジオ群、数字キー) だけ。`ON_COMMAND_RANGE` 系で受け、`nID - ID_FIRST` を操作の引数にする。
- 画面モデルはリソース ID を知らない。ID と操作の対応は、ダイアログ側が持つ。
- 計画には、ハンドラの表 (ID / 通知 / ハンドラ / 画面モデルの操作 / 実行可否 / 更新の方法) を書く。
- `WM_NOTIFY` や `WM_HSCROLL` も同じ扱い。

### 更新の経路 (標準)
| 画面 | 画面 → 画面モデル | 画面モデル → 画面 |
|---|---|---|
| モーダルなダイアログ | OK のとき `UpdateData(TRUE)`、続けて `Commit()` | `OnInitDialog` と通知のとき `UpdateData(FALSE)` |
| `CFormView` | DDX。操作は ID ごとのハンドラ | 通知 → `UpdateAllViews` → `OnUpdate` |

### 更新の経路 (例外: 個別更新)
モードレスの即時反映、部分更新、DDX で書けないものは、次の 3 つを守れば許す。
1. 更新を `OnModelChanged(PropertyId)` の 1 か所に集める。通知は、変わったプロパティの識別を持つ。
2. 経路は、コントロール → 画面モデル → 通知 → コントロールにする。ハンドラが別のコントロールを直接書き換えない。
3. `SetWindowText` が `EN_CHANGE` を起こす再入を、更新中のフラグで防ぐ。

### 検査・失敗・文章 (C++ の書き方)
契約は `winforms-view-model.md` の 2 章のとおり (C# は、標準の `ValidationResult` を使う)。C++ では、**取得に `Get` を付け** (`GetFailure()`)、述語は `Is` / `Can` (`IsValid()`、`CanSave()`)。
- **文字列の型: 契約は `std::wstring`。** `CString` を、画面モデルの契約 (公開する文章・名前・状態) に出さない (MFC を使わないロジック層でも使える。`CString` の型が、プロジェクトの文字セットで揺らぐ (Unicode は `CStringW`、MBCS は `CStringA`) のも避けられる)。ロジック層・データ層の内部では、`CString` を使ってよい (MFC を許容する構成)。
- **MFC 側の境界の補助 (UI 層。ひな形が生成):**
  ```cpp
  inline CString ToCString(const std::wstring& s) { return CString(s.c_str(), static_cast<int>(s.size())); }
  inline std::wstring ToWString(const CString& s) { CStringW w(s); return std::wstring(w.GetString(), w.GetLength()); }
  ```
  Unicode では、コピーだけ。MBCS では、ANSI (CP_ACP) との変換で、**ANSI に表せない文字は `?` になる。** DDX のメンバー変数 (`CString`) と、画面モデルの `std::wstring` の間は、この 2 つで変換する。
- **検査:** `Validate()` が `std::vector<ValidationError>` (`ValidationResult` は別名) を返す (純粋)。`struct ValidationError { std::vector<int> properties; std::wstring message; };` (`properties` = 対象の欄の一覧。画面ごとの `PropertyId` の列挙を `int` にしたもの。**空 = 画面全体の誤り、先頭 = 主たる欄**)。テンプレートは使わない。`IsValid()` は `bool` (`Validate()` が空)。並びは、検査の規則を書いた順。等価の比較のため、`operator==` を定義する。
- **`Commit()` は `bool`。** 理由は、状態で読む (誤りは `Validate()`、失敗は `std::wstring GetFailure() const`。空 = 失敗なし)。`Failure` は、直近の失敗の文章で、次の編集、または次の `Commit()` の開始で消える。リポジトリは、ユーザー向けの文章 (`std::wstring`) を持つ例外 `RepositoryException` を投げ、画面モデルは、それだけを `Failure` にする (それ以外は、そのまま伝える)。
- **文章:** 画面モデルが、**日本語の文章を作ってよい。** C++20 の `std::format` (ワイド文字列。例: `std::format(L"名前は {} 文字以内で入力してください", max)`) で作る。**文章を作る処理は、画面モデルごとに 1 か所へまとめ** (名前空間 `Messages` の関数)、日本語のリテラルを、検査の規則のあちこちに書かない。リソース (`STRINGTABLE`) への移行は、必要になったとき (その 1 か所を置き換える)。

### 通知 (`Observable`)
- **画面モデルは、`Observable` を継承し、ハンドラーを受け付ける。** `Observable` は、テンプレートなしの小さなクラス (`std::function<void(int)>` のハンドラー): `int AddHandler(...)`、`void RemoveHandler(int id)`、保護された `void Raise(int property)`。`property` は、画面ごとの `PropertyId` (列挙) を `int` にしたもの。通知の識別と、誤りの対象の欄を、兼ねる (宣言の順序の例: 入力欄、表示、`CanXxx`、`IsValid`、`Failure`、`All`)。
- **複数の値を変える操作は、最後に `All` を 1 回通知する** (操作の途中の通知は、出てよい。ダイアログのハンドラーが、最後に全 `CanXxx` を再適用するので、実害は小さい)。`ChangeScope` や `ModelSubscription` のような、まとめる仕組みは、作らない。
- **ダイアログ側:** `OnInitDialog` で `AddHandler` (戻り値の id をメンバーに保持)、`OnDestroy` で `RemoveHandler`。基底ダイアログクラスは作らない。更新は `OnModelChanged(int)` に集め、**最後に、全 `CanXxx` を `EnableWindow` に適用する関数を、1 回呼ぶ** (`ON_UPDATE_COMMAND_UI` は、メニューとツールバー用に限る)。
- **確定時:** `UpdateData(TRUE)` からの画面モデルへの反映中は、更新中のフラグで `OnModelChanged` を抑える。`Commit()` が `false` のときだけ、通知 (`All`) で、表示を更新する。
- **スレッド:** **画面モデルは、UI スレッドからだけ呼ぶ** (別スレッドの処理は、結果を UI スレッドへ引き渡してから、画面モデルを呼ぶ)。別スレッドから通知が上がるのは、規約違反 (バグ) で、`PostMessage` の保険は作らない。

### Fake 画面モデルの切り替え
画面ごとに選ぶ。環境変数 `APP_FAKE_SCREENS` (画面名のカンマ区切り。`画面名:シナリオ名` も可)。**Debug のときだけ読む** (`InitInstance`。`APP_MODEL` と同じ)。ダイアログを開く側 (`InitInstance`) が、補助 `ScreenModelSelector.h` (Debug のときだけ読む) の結果を、**本物の画面モデルに、シナリオの初期状態として当てる** (Fake のクラスは、本物がまだない画面のつなぎだけ)。UI テスト側の設定と、Fake の存続時間は、`ui-test-first` の `references/model-switching.md`。
