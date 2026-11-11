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
- Unicode ビルド (`_T()` / `CString`)。MFC は動的リンク (共有 MFC。`UseOfMfc=Dynamic`)。

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
  - **理由:** MFC の実行時のクラス情報のマクロ (`DECLARE_DYNAMIC` / `IMPLEMENT_DYNAMIC` / `IMPLEMENT_SERIAL` / `RUNTIME_CLASS`) は、クラス名を、`class##class_name` や `_init_##class_name` のように、**トークンを連結**し、`#class_name` で**文字列にする**。名前空間つきの名前 (`ns::Foo`) を渡すと、`classns::Foo` になり、コンパイルできない。共有 MFC (`_AFXDLL`) の `RUNTIME_CLASS` は、たまたま通るが、静的 MFC では通らない。また、実行時のクラス名 (`CRuntimeClass::m_lpszClassName`) には、名前空間が入らないので、**別の名前空間の、同名のクラスと、衝突する** (シリアライズは、クラス名の文字列で、クラスを復元する)。
  - **CObject 派生でないクラス** (ロジックのクラス、値のクラス、自由関数) は、名前空間に入れてよい。
- **CObject 派生のクラスには、`DECLARE_DYNAMIC` / `DECLARE_DYNCREATE` / `DECLARE_SERIAL` のどれかを書く** (宣言に、マクロがないクラスは、実行時のクラス情報が、基底クラスのものになり、正しい宣言ではない)。`.cpp` に、対応する `IMPLEMENT_DYNAMIC` / `IMPLEMENT_DYNCREATE` / `IMPLEMENT_SERIAL` を書く。**例外: `CWinApp` / `CWinThread` 派生** (アプリケーション・スレッドのクラス。ウィザードも、マクロを書かない)。
- (`mfc-check` の NSP001 / DEC001 が検査する。どちらも warning。)
