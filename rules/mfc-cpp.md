---
paths:
  - "**/*.cpp"
  - "**/*.h"
  - "**/*.hpp"
  - "**/*.cc"
  - "**/*.cxx"
---

# C++ / MFC コーディング規約 (ユーザー共通)

対象: Windows の C++ / MFC のプロジェクト全般の、自分で書くコード。**プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、そちらを優先する。** 詳細な書式は、プロジェクトの `.clang-format` が正 (なければ、`~/.claude/templates/cpp/` のひな形)。この文書は、機械で判定できない規則も含めた全文。

## 言語・ビルド
- C++20 (`LanguageStandard=stdcpp20`)。**プロジェクトの `.vcxproj` の設定を、先に確認する。** C++20 が未設定のプロジェクトで、C++20 のコードを足すときは、先に、標準を設定する。Unicode ビルド (`_T()` / `CString` / `std::wstring`)。MFC は動的リンク。
- **C++20 の機能 (`concept` `ranges` `<format>` `<span>` など) を、プロジェクトの言語標準が許す範囲で、積極的に活用する。**
- 上の設定を変えるときは、`.vcxproj` と、この文書の両方を直す。

## ファイルの形式
| 種類 | 文字コード | 改行 | インデント |
|---|---|---|---|
| 手書き・新規の `.cpp` / `.h` | UTF-8 (BOM 付き) | CRLF | スペース 4 |
| 既存で、Shift-JIS (CP932) のファイル | 変換するまでは、そのまま | そのまま | そのまま |
| VS ウィザード生成のファイル | そのまま | そのまま | そのまま |
| サードパーティのコード (ベンダ配布物・外部ライブラリのコピー) | 対象外 | 対象外 | 対象外 |

- ウィザード生成の書式は直さない (差分が、全行に広がるため)。機能の変更に必要な行だけを編集する。
- 新しい `.cpp` / `.h` は、手書きの形式で作る。Shift-JIS で保存しない。
- **Shift-JIS の既存ファイルは、編集の前に、UTF-8 (BOM 付き) へ変換する** (`~/.claude/scripts/convert_to_utf8_bom.py`。変換だけの、別のコミット)。変換するまでは、バイト列で編集する (文字列一致のエディタで、日本語のコメントを、壊さない)。プロジェクトの `CLAUDE.md` に、文字コードの注意があれば、従う。
- **ビルドイベントで、生成・コピーされるファイル (例: 共有の `include/`) は、直接、編集しない** (発行元を編集する)。どれが生成物かは、プロジェクトの `CLAUDE.md` を見る。
- `.editorconfig` の `charset` は、**変換が終わったフォルダにだけ**書く。EditorConfig には、CP932 を表す値がなく、`utf-8-bom` を全体に書くと、VS が、保存のときに、Shift-JIS のファイルを、意図せず変換する。

## 書式
- 括弧は Allman 形式 (開き括弧は、次の行の頭)。インデントはスペース 4。タブは使わない (ウィザード生成を除く)。
- 整形は `clang-format` で行う。`#include` の順序は、並べ替えない (`pch.h` は、最初)。

## コメント
- **コメントは、日本語で記述する** (必要に応じて、英語も可)。

## 命名
- 型・関数・名前空間: PascalCase。
- **ファイル名は、クラス名と一致させる** (例: クラス `ImageLoader` は、`ImageLoader.h` / `ImageLoader.cpp`)。
- **`C` で始めてよいのは、MFC / ATL の既存のクラスだけ** (`CWnd` `CString` `CDialog` `CArray`、ATL の `CComPtr` `CImage` `CHandle` など)。
  - 自分で作るクラスには、`C` 接頭辞を付けない。**クラスウィザードで作るクラスも同じ** (ウィザードの「クラス名」を、`C` なしの名前に直してから作る。例: `CMyDialog` ではなく `MyDialog`)。
  - MFC のクラスから派生しても、自分のクラスなら `C` を付けない (例: `CObject` 派生の `Shape`)。
  - `Chain` `Cache` `Color` `Circle` のように、**単語そのものが `C` で始まる名前は、そのまま使う** (接頭辞ではないため)。判断に迷うときは、「`C` を外しても意味が通るか」で見る (`CircleShape` は、外せない = 単語の一部。`CImageSerializer` は `ImageSerializer` として通じる = 接頭辞)。
  - 既存の `C` 付きの自作クラス (ウィザード生成の `CMainFrame` など) は、触らない限り、そのまま。リネームは、`m_` と同様に、別のコミットで行う。
- **クラスのメンバー変数 (private / protected): `m_` + camelCase** (例: `m_color`)。ハンガリアン (`m_bFlag` `m_pView`) は、使わない。
- **`static` の (定数でない) メンバー変数にも、`m_` を付ける** (`static` かどうかで変えない。例: `static int m_instanceCount;`)。`static constexpr` は、下の規則 (すべて大文字、`m_` なし)。
- `struct` の公開データメンバー (集成体): 接頭辞なし (例: `Geometry::Point::position`)。`class` は、公開データメンバーを持たない (必要なら、`struct` にする)。
- ローカル変数・引数: camelCase。
- **`constexpr` 変数と `#define` で定義する名前は、すべて大文字** (単語の区切りは `_`)。例: `constexpr SIZE BOUNDS = { 20, 20 };`、`#define MAX_POINT_COUNT 64`、`static constexpr SizeType SIZE_TYPE_MAX = ULONG_MAX;`。
  - 対象は、**名前の付く値** (変数・定数・マクロ)。**関数の中のローカルな `constexpr` も含む** (例: `constexpr UINT FORMAT_SIZE = sizeof(CLSID);`)。`constexpr` の関数・クラス名は、PascalCase のまま。
  - `m_` は付けない (定数は、メンバー変数ではなく、定数として扱う)。`static constexpr` のクラスメンバーも、`m_` なしで、大文字。
  - `constexpr` / `#define` でない `const` 変数は、通常の変数の規則 (camelCase / `m_`)。定数にできる値は、`constexpr` を優先する。
  - 関数形式のマクロ (`#define MAKE_COLOR(r, g, b) ...`) も、すべて大文字。ただし、マクロより `constexpr` / `inline` 関数を優先する。
- **オーバーライドするメソッドは、`virtual <戻り値> <メソッド名>(...) override` と、`virtual` と `override` の両方を書く。** 例:
  ```cpp
  virtual void Serialize(CArchive& ar) override;
  virtual CRect GetBounds() const override;
  ```
  - `override` は、`const` などの修飾の後ろ。`virtual` だけ (`override` なし) のオーバーライドは書かない。新しく仮想にするメソッドは、`virtual` だけ。
  - デストラクタは、対象外 (`virtual ~Name()` のまま。`override` は付けない)。
  - クラスウィザード (「オーバーライドの追加」) が書く宣言は、`override` が付かない。**新しく追加した宣言には、手で `override` を足す** (既存の宣言は、触らない)。
  - `clang-tidy` を使う場合は、`modernize-use-override` (`virtual` を消す) を、無効にする。

## Win32 API の呼び出し
- **Win32 API を呼ぶときは、必ず、先頭に `::` を付ける。** MFC のクラスメソッドではなく、グローバルな Win32 API であることを、呼び出しの形で示す。
  ```cpp
  ::GetClientRect(hWnd, &rect);          // Win32 API (CWnd::GetClientRect ではない)
  ::MessageBox(hWnd, text, caption, MB_OK);
  CWnd::GetClientRect(&rect);            // これは MFC のメンバー (引数の形も違う)
  ```
- **特に、同じ名前の MFC メンバーがあるもの** (`GetClientRect` `GetWindowRect` `SetWindowText` `MessageBox` `InvalidateRect` `GetDC` `ReleaseDC` `SelectObject` `DeleteObject` `CreateCompatibleDC` など) は、`::` がないと、MFC のメンバー関数 (クラスの内側では、こちらが先に見つかる) を呼んでしまい、引数や動作が違う。初回の呼び出しには、`// Win32 API (CWnd::〜 ではない)` の短いコメントを添えてよい。
- クラスの外 (自由関数・名前空間の中) でも、同じ。`::` を付けるかどうかを、場所で変えない。
- `::` を付けないもの: マクロ (`RGB` `MAKELONG` `ASSERT` `TRACE` など。付けられない)、MFC / ATL のグローバル関数 (`AfxMessageBox` `AfxGetApp` など。`Afx` で始まる)、C / C++ 標準ライブラリ (`std::` / `strlen` など)、型・定数 (`HWND` `MB_OK` など)。
- 判断に迷うときは、「`CWnd` などに、同じ名前のメソッドがあるか」「引数に `HWND` / `HDC` などのハンドルを、直接渡しているか」で見る。ハンドルを直接渡すのは、たいてい Win32 API。

## ポインタとメモリ管理
- **所有するポインタは、スマートポインタ (`std::unique_ptr` を既定、共有が要るときだけ `std::shared_ptr`) で持つ。** 生成は `std::make_unique` / `std::make_shared`。COM のインターフェースは `CComPtr<T>` (下の「COM のポインタ」)。生ポインタに戻す前に、「スマートポインタで書けないか」を検討する。
- **所有しないポインタ** (借りているだけ。`nullptr` を取りうる) は、生ポインタでよい。`nullptr` を取らないなら、参照 (`T&`) にする。
- **スマートポインタを使わなくてよいもの** (MFC が、寿命を決めているオブジェクト):
  - `CWnd` 派生 (`PostNcDestroy` で自己削除するもの) と、ドキュメント・ビュー・フレーム (テンプレートが管理する `CDocument` `CView` `CFrameWnd`)。
  - `CObject` 派生のオブジェクトで、MFC のコレクション (`CTypedPtrArray` など) が所有するもの、`DECLARE_DYNCREATE` / `DECLARE_SERIAL` で動的に生成されるもの。
  - 判断は、「**そのオブジェクトの寿命を、MFC が決めているか**」。決めているなら、除外。
- **`new` / `malloc` / `calloc` (と、同等の確保) で作ったポインタを、生のまま返す関数には、宣言部に、後始末の注意のコメントを付ける。** 解放の方法 (`delete` / `delete[]` / `free` / `::GlobalFree` など) も書く。
  ```cpp
  // 注意: 内部で new[] している。戻り値は、呼び出し側が、必ず delete[] で解放すること。
  BYTE* CreateBuffer(UINT size);
  ```
  - コメントは、**ヘッダの宣言**の直前に書く (定義側ではなく。呼び出す人が見る場所)。
  - 戻り値を `std::unique_ptr` にすれば、所有権が型で分かるので、このコメントは要らない。**まず、`unique_ptr` で返せないかを検討する** (C のコールバックや、MFC の規約で、生ポインタが必要な場合に、コメントで対応する)。
- **生ポインタ・ハンドル (`HGLOBAL` `HBITMAP` `HDC` など) を、所有してメンバー変数に持つクラスは、RAII で実装する** (コンストラクタで確保し、デストラクタで解放する。`std::unique_ptr` + カスタムデリータ、または、専用の小さなラッパークラス)。
  - コピーできないクラスは、コピーを `= delete` にし、必要ならムーブを実装する。
  - **外部から受け取った (所有しない) ポインタ・ハンドルは、対象外。** 所有しないメンバーには、`// 非所有` とコメントを付ける (例: `CGdiObject* m_gdiObject; // 非所有`)。

## COM のポインタ
- **COM のインターフェースのポインタは、必ず `CComPtr<T>` (ATL。`<atlbase.h>`) で持つ。** `IStream*` `IMultiLanguage3*` `IXmlReader*` などを、生のまま、ローカル変数・メンバー変数・戻り値にしない。WRL (`Microsoft::WRL::ComPtr`) や `_com_ptr_t` は使わない (`CComPtr` に統一する)。
  ```cpp
  CComPtr<IStream> stream;
  ::CreateStreamOnHGlobal(handle, FALSE, &stream);        // 出力引数は、CComPtr のアドレスで受ける (自動で解放される)
  CComPtr<IMultiLanguage3> mlang;
  mlang.CoCreateInstance(CLSID_CMultiLanguage, nullptr, CLSCTX_INPROC_SERVER);
  ```
- **解放は、`CComPtr` に任せる。** `Release()` を、自分で呼ばない。`delete` もしない。
- **COM のインターフェースを返す関数は、`CComPtr<T>` で返す** (所有権が型で分かる。「後始末の注意」のコメントは要らない)。
- **別のインターフェースへの変換は、`QueryInterface` を使い、`CComPtr` で受ける** (`CComQIPtr<T>` も可)。生ポインタを受けて、自分で `Release()` しない。
- **外から受け取った生のポインタを、所有するときは、`Attach` で `CComPtr` に渡す** (所有権が、移る場合のみ)。借りただけなら、`CComPtr` に入れる (`AddRef` される)か、そのまま借りる。
- **借りるだけの関数の引数は、生の `T*` でよい** (所有しない。呼び出し側は、`ptr` を、そのまま渡す)。保持する・戻り値にする場合は、`CComPtr` にする。
- `CComPtr` をメンバーに持つクラスは、コピーできるかを、決めて書く (コピーしないなら、`= delete` にする)。

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

## コレクションと反復
- **シリアライズするデータのコレクションは、標準ライブラリのコンテナではなく、MFC のコレクションを優先する** (`CArray` `CList` `CMap` `CTypedPtrArray` `CStringArray` など。`CArchive` で、そのまま読み書きできる)。判断は、「**その中身が、`CArchive` に書かれる・読まれるか**」。シリアライズしない内部の作業用データは、標準ライブラリのコンテナでよい。
- **ループは、極力、イテレータ (範囲 `for`) で書く。** 添字 (`for (int i = 0; i < n; ++i)`) は、添字そのものが必要なときだけ。
- **MFC のコレクション (`CArray` `CList` `CMap` `CStringArray` `CTypedPtrArray` など) を、イテレータ (範囲 `for`、`std::ranges`) で操作できるようにする、ライブラリ・関数・クラスを使うことを、推奨する** (必須ではない。使わなくてもよい)。C++20 の反復子の要件を満たす `begin()` / `end()` (自由関数) を提供する形が、使いやすい。プロジェクトに、すでに、そのようなものがあれば、それを使う。
  ```cpp
  for (const auto& point : points)   // CArray<CPoint>
  {
      ...
  }
  ```
  - **一例:** 自作の `mfciterators.h` (`CArray` `CStringArray` `CList` `CMap` `CTypedPtrArray` などに対応し、`IsMFCArray` などの `concept` で、MFC のコレクションを判定する)。どれを使うかは、プロジェクトで決める (特定のファイルに、固定しない)。
- **コンテナ (標準ライブラリのもの、`std::span`、MFC のコレクション) の操作には、`<algorithm>` の関数ではなく、`std::ranges` と `views` を使う** (例: `std::find_if` ではなく `std::ranges::find_if`、`std::ranges::sort`、`std::views::filter` / `transform`)。
  - イテレータで操作できるコレクションは、`std::ranges` と `views` が、そのまま使える。

## テンプレート
- **複雑な SFINAE (`std::enable_if` など) や、特殊化を、極力避ける。** 型の条件は、`concept` と `requires` で書く。分岐は、`if constexpr` か、オーバーロードで書く。
  ```cpp
  template <typename T>
  concept Drawable = requires(T& t, CDC& dc) { t.Draw(dc); };

  template <Drawable T>
  void DrawAll(CDC& dc, T& shape);
  ```
- **`concept` の名前は、UpperCamelCase** (例: `Drawable` `IsMFCArray`)。

## 関数の大きさ
- **1 つの関数は、30 行程度を目標にする。最悪でも 100 行までに収める。** 数えるのは、関数の先頭の行から、閉じ括弧までの全行 (空行・コメントを含む)。
- 30 行を超えそうなら、**意味のまとまりごとに、関数に切り出す** (例: 検証・変換・描画を分ける)。100 行を超える関数は、書かない (対象外は、下記のものだけ)。
- 切り出した関数にも、同じ規則を適用する。引数が増えすぎる (目安: 5 つ超) 場合は、構造体にまとめるか、クラスのメンバーにする。
- **既存の長い関数を、機能の変更のついでに、まとめて分割しない。** 変更する関数が 100 行を超えている場合は、その関数だけを、別のコミットで先に分割する (動作を変えない。テストを通す)。
- 対象外: VS ウィザード生成の関数 (`OnInitDialog` など。書式を変えない規則に従う) と、サードパーティのコード。ウィザード生成の関数に、長い処理を追加しない (別の関数に書いて、呼び出す)。
- 機械の確認: プロジェクトの `.clang-tidy` (ひな形は `~/.claude/templates/cpp/`) の `readability-function-size` (`LineThreshold: 100`) で、上限を判定する (30 行の目標は、人が見る。数え方は、ツールの定義に従う)。

## 既存コードの扱い
- 触らないクラスのメンバー変数は、リネームしない。`m_` への一括リネームは、**別のコミット**で、そのプロジェクトのテスト (なければ、確認用のプログラム) を実行して、結果を確認しながら行う。
- 既存の `constexpr` 名と、`override` のない仮想関数のオーバーライドも、触らない限り、そのまま。直すときは、別のコミットで行う (名前の変更は、使用箇所を、すべて直す)。
- 既存の、所有する生ポインタ・ハンドルのメンバー、生ポインタを返す関数のコメントの不足、`m_` のない公開メンバーの直接アクセスも、触らない限り、そのまま。直すときは、別のコミットで行う。
- 既存の、生の COM ポインタ (所有するもの) を `CComPtr` に直すのも、機能の変更と混ぜず、別のコミットにする。
- コメントアウトされたコードと、名前のスペルミスは、頼まれるまで直さない。直すときは、別のコミットにする。
