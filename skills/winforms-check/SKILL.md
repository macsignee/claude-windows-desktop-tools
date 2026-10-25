---
name: winforms-check
description: WinForms のプロジェクトの「コンパイルは通るが、実行時に壊れる / 規約に反する」部分 (InitializeComponent() の呼び忘れ、Designer.cs の Name の重複・変数名との不一致・Controls への入れ忘れ、InitializeComponent の中の制御構文、ロジック層・データ層・Presenter への WinForms の混入、層の参照の向き、DoEvents / Thread.Sleep / CheckForIllegalCrossThreadCalls、.Result / async void / 空の catch / throw ex / 曖昧な bool 名) を、静的に検査して、要約を返す手順。画面が空になる、UI テストが要素を探せない、Form / Designer / Presenter を編集した、Presenter に WinForms の型が混ざっていないか確かめたい、といった依頼で使う。Windows のウォッチャーは不要 (読み取りだけ)。
---

# WinForms の「見えない部分」の検査 (winforms-check)

WinForms は、`Form` と `*.Designer.cs` (デザイナーが書く `InitializeComponent()`) が、**呼び出しと名前で結ばれている**。
崩れても、コンパイルは通り、**「画面が空」「UI テストが要素を探せない」「スレッドの誤りが、黙って通る」**という形で現れる。
このスキルは、その対応と、規約 (`~/.claude/rules/winforms-csharp.md`) のうち機械で判定できる項目を、静的に検査する。ビルド (`auto-build`) とは別で、**ウォッチャーも、Windows も、要らない**。

コンパイルエラーになるもの (イベントハンドラーのメソッドの不足、フィールドの重複など) は、対象外。ビルドが教える (`CS` のエラー)。

## 実行

```bash
python3 -I <このSkillのフォルダ>/scripts/winforms_check.py "$PROJ"
```

- `$PROJ`: ソリューションまたはプロジェクトのフォルダ。以下の `.csproj` を、プロジェクトとして検査する。
- 読み取りだけ。ファイルは、変えない。C# は、UTF-8 (BOM あり・なし)・UTF-16・CP932 のどれでも読める。`obj/` `bin/` と、`*.g.cs` は、読まない (`*.Designer.cs` は、読む)。
- `--json <ファイル>` で、全件を JSON に書く。`--max-lines` で、出力の行数を変える (既定 40)。
- 層の判定は、プロジェクト名と、`.csproj` の `UseWindowsForms` / `OutputType` で決める。名前が違うときは、`--logic <名前>` / `--data <名前>` で指定する。

| 終了コード | 意味 | 次の行動 |
|---|---|---|
| 0 | error なし (warning はあるかもしれない) | warning を、読んで、判断する |
| 1 | error あり | 下記の方針で、直す |
| 2 | 引数が不正 | フォルダを確認する |
| 3 | 検査する対象がない (WinForms のプロジェクトも `Designer.cs` もない) | WinForms ではない。報告して終わり (WPF は `wpf-check`) |

## 出力の読み方
```
winforms-check: error 1 / warning 1 (3 projects: WfApp, LogicLayer, DataLayer)
[1] error   WFD001 MainForm のコンストラクターが、InitializeComponent() を呼んでいない (画面が空になる。例外も出ない)
      WfApp/Forms/MainForm.cs(9)
[2] warning WFD004 ClearButton (Button) が、どの Controls.Add / AddRange にも入っていない (画面に出ない)
      WfApp/Forms/MainForm.Designer.cs(64)
```
`[n]` は、重大度順 (error → warning)。2 行目は、`ファイル(行)` (`$PROJ` からの相対パス)。

## 検査の一覧と、直し方

| コード | 重大度 | 内容 | 直し方 |
|---|---|---|---|
| WFD001 | error | Form のコンストラクターが、`InitializeComponent()` を呼んでいない (コンストラクターがない場合も) | コンストラクターの先頭で、呼ぶ。**画面が空になる (例外も出ない)。** |
| WFD002 | error | `Designer.cs` に、同じ `Name` の文字列が、複数のコントロールにある | `Name` を、役割が分かる別の名前にする (変数名とそろえる)。**FindControl / AutomationId が、曖昧になる。** |
| WFD003 | warning | コントロールの `Name` の文字列が、変数名と違う | `Name` を変数名にそろえる (**UI テストの AutomationId は Name**)。 |
| WFD004 | warning | `Designer.cs` で作ったコントロールが、どの `Controls.Add` / `AddRange` にも入っていない | 親の `Controls.Add` に入れる。**画面に出ない。** (デザイナーで、配置し直すのが確実) |
| WFD005 | warning | UI テストのプロジェクト (`*.UITests`) があるとき、操作するコントロールに `Name` がない | `x.Name = "x";` を足す。**AutomationId が空になり、FlaUI が探せない。** |
| WFD006 | warning | `InitializeComponent()` を、`Designer.cs` 以外に書いている | `*.Designer.cs` に移す (デザイナーが開けなくなる・書き換える)。 |
| WFD007 | warning | `InitializeComponent()` の中に、`if` / `for` / `while` / `switch` / `try` がある | 宣言 (代入と `Add`) だけにする。処理は、コンストラクターの、`InitializeComponent()` のあとに書く。 |
| WFT001 | warning | `Application.DoEvents()` を使っている | `async` / `await` に分ける (再入で、状態が壊れる)。 |
| WFT002 | warning | Form / UserControl のコードで、`Thread.Sleep()` を呼んでいる | `await Task.Delay` にする (UI が固まる)。 |
| WFT003 | error | `Control.CheckForIllegalCrossThreadCalls = false` | 外す。別スレッドからは、`Invoke` / `BeginInvoke`、または `async` / `await`。 |
| WFL001 | error | ロジック層・データ層が、WinForms に依存している (`UseWindowsForms` / `-windows` / `System.Windows.Forms` / `System.Drawing` / `MessageBox` など) | UI の処理を、Form / `IView` の実装に移す。ロジックは、`net8.0` などの、Windows 非依存にする。 |
| WFL002 | warning | Presenter (`Presenters/` フォルダ、または名前が `Presenter` で終わる型) が、WinForms の型を使っている (`MessageBox` / `Form` / `Control` / `Application` など) | `IDialogService` などの、インターフェースに分ける (テストしにくい)。 |
| WFL003 | error | プロジェクト参照の向きが、層 (アプリ → ロジック → データ) に反する | 参照を逆にするか、共通部分を下の層に移す。 |
| WFL004 | warning | Form のコードで、`new XxxService()` / `Repository` / `Client` / `Provider` / `Gateway` を生成している | コンストラクターで、インターフェースを受け取る (組み立ては、`Program.cs`)。 |
| ASY001 | warning | `.Result` / `.Wait()` / `GetAwaiter().GetResult()` で、非同期処理を同期的に待っている | `await` にする (UI スレッドのデッドロック)。 |
| ASY002 | warning | イベントハンドラー (引数に `sender` または `EventArgs`) 以外の `async void` | `Task` を返す。 |
| EXC001 | warning | 空の `catch` | ログを書くか、再スローする。 |
| EXC002 | warning | `catch (Exception ex) { throw ex; }` | `throw;` にする。 |
| NAM001 | warning | `bool` に、`Flag` / `Status` / `Check` という名前を付けている | `IsXxx` / `HasXxx` / `CanXxx` にする。 |

## ループのルール
1. **Form / `Designer.cs` / Presenter / `.csproj` の参照を編集したら、編集のあとで、実行する。** 編集していない状態で再実行しない。
2. error は、すべて直す。warning は、**自分が今回編集した箇所に関係するもの**だけ直し、ほかは、報告に 1 行で添える (無関係な修正はしない)。
3. 直したら、再実行して、error が減ったことを確認する。**最大 3 回**。同じ error が残るなら、停止して、原因 (誤検出の疑いを含む) を報告する。
4. error がなければ (終了コード 0)、続けて、ビルドとテスト (`auto-build` / `build-test-loop`) に進んでよい。
5. **検査を通すために、コントロールやイベントを消さない。** 直すのは、名前・呼び出し・置き場所。画面の機能を減らして、指摘を消すのは、ユーザーの許可が要る。

## 編集のときの注意
- **`*.Designer.cs` は、デザイナーが書き直すファイル。** 手で直すときは、`InitializeComponent()` の形 (`// 名前` のコメント、`SuspendLayout` / `ResumeLayout`) を保つ。**Visual Studio でデザイナーを開いて、保存すると、書き直される** ことを、ユーザーに伝える。
- イベントハンドラーの名前を変えるときは、`Designer.cs` の `+=` と、Form のメソッドを、**同時に**直す (食い違うと、ビルドで `CS0103`)。
- `Name` を変えたら、**UI テスト (`*.UITests`) の `Find("...")` も、同時に直す** (AutomationId が変わる)。
- `.csproj` の編集は、ユーザーの確認が要る設定のことがある (`docs/RECOMMENDED-SETTINGS.md`)。文字コードと改行 (UTF-8 の BOM、CRLF) を、変えない。

## 誤検出と限界
- **静的解析**。実行はしない。**通ったことは、動くことを意味しない** (見た目・レイアウト・DPI・データの中身は、対象外)。
- **C# の解析は、軽い字句解析。** コメントと文字列を除いて、正規表現と括弧の対応で見る。`Designer.cs` の `InitializeComponent()` は、VS が書く形 (`x = new T();`、`x.Name = "x";`、`parent.Controls.Add(x)`) を前提にする。**手で書き換えて、形を崩した** `Designer.cs` では、誤検出・見逃しがある。
- WFD004 は、**確実に `Control` である型の一覧** (`Button` / `TextBox` / `Panel` など) だけを見る。`Timer` / `ToolTip` / `ImageList` などの、Control でないものと、一覧にない型は、見ない。
- WFL001 / WFL002 は、**`using` と、型の名前 (`MessageBox` / `Control` / `Form` など) の字面**で判定する。同名の自作の型があると、誤検出になる。
- 層の判定は、**名前の推定:** `Logic` / `Domain` / `Core` / `Presenters` → ロジック、`Data` → データ、`UseWindowsForms` の exe → アプリ。テストプロジェクト (`Test` / `Tests` で終わる) は、層の検査の対象外 (共通の規則 (ASY / EXC / NAM) も、見ない)。外れるときは、`--logic` / `--data` で指定する。
- **実プロジェクトでの検証は、まだ。** 疑似のソリューションと、`new-solution` が作ったものでは、誤検出なし。実プロジェクトで誤検出を見つけたら、報告に書き (どのコードの、どの書き方か)、ユーザーに伝える。
