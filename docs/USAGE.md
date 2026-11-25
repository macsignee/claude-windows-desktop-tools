# 利用ガイド (どのコマンドを打つか・承認の言い方・困ったとき)

このガイドは、**使う人**向けです。設計の判断は [`DESIGN.md`](DESIGN.md)、Skill ごとの詳細は [`README.md`](../README.md) を見る。画面モデルの考え方は [`UI-MODEL-GUIDE.md`](UI-MODEL-GUIDE.md)。

あなたが打つのは、**`/` から始まるコマンド**だけです。それ以外の Skill (`auto-build`、`build-test-loop`、`mfc-check` など) は、依頼文 (「ビルドして」「先にテストを書いて」など) に合わせて、Claude が選びます。

## 1. どのコマンドを打つか (判断フロー)

### Q1. ソリューション (`.sln` / `.slnx`) は、もうあるか?

**ない (これから作る)**

| やりたいこと | 打つもの |
|---|---|
| 1 つのソリューションを作る (WPF / WinForms / MFC / Win32 / コンソール / DLL など) | `/new-solution` |
| 先に、仕様を固めてから作る | `/brainstorm` → `/update-from-ideas` → `/new-solution --spec <仕様書>` |
| 同じ題材で、種類違いの複数の候補 (WPF と WinForms など) を作って、比べる | `/new-solutions` |

- C++ で、テストあり (`--tests gtest`) のときは、作成のあとに、**GoogleTest (vcpkg) の準備** (`builtin-baseline` の固定と `gtest` の取得。初回は数分) が要ります。`/new-solution` を通せば、Claude が続けて実行します。スクリプトを直接実行したときは、「vcpkg の baseline を固定して」と頼みます (しないと、ビルドが `requires a manifest with a specified baseline` で止まります)。

**ある (すでに作ってある)** → Q2 へ。

### Q2. すでにあるソリューションで、何をしたいか?

| やりたいこと | 打つもの・頼み方 |
|---|---|
| **層・テスト・画面を持つ DLL・UI テストを、足す** | `/add-project` (層 / テスト / 画面 + ホスト / UI テスト / プラットフォーム (C++ の Win32 など) / 共通の MSBuild 設定) |
| **混在のソリューションは、`/add-project` で作る** (WPF に C++ の DLL を足す、C++ に C# のライブラリを足す、など) | まず、片方の言語で `/new-solution` を打ち、`/add-project` で、もう片方の層を足す。`/new-solution` は、言語が混ざる指定 (WPF に `--tests gtest` や `--layer-kind`、C++ に `--tests mstest`) を、エラーで止めて、そう案内する。**WPF から C++ を呼ぶ参照は、扱わない** (C++ と C# の間の参照は、`add_reference.py` が断る) |
| **機能を作る** (仕様書から。計画 → 承認 → テスト先行 → 実装 → 検証) | `/add-feature [仕様書のパス]` (別リポジトリ `claude-spec-workflow`) |
| 機能の仕様を、整理したい・追加のアイデアを、仕様書に反映したい | `/brainstorm` → `/update-from-ideas` (`claude-spec-workflow`) |
| 画面を、プロンプトで作りながら、UI テストを先に書く (**手書きのスケッチや、画面の写真を渡して、作ることもできる**) | `/ui-test-first [作りたい画面の説明]` (画像は、チャットに貼る。Claude が、部品の一覧を見せて、決まらないことを、確認する) |
| 先にテストを書いて、Red を確認したい (TDD) | 「先にテストを書いて」「TDD で」と頼む (`cpp-test-first` / `csharp-test-first`) |
| ビルドだけ、確かめたい・エラーを直したい | 「ビルドして」(`auto-build`) |
| ビルドとテストを通したい | 「テストまで通して」(`build-test-loop`) |
| **1 つの層だけ**、ビルドとテストを回したい (ほかの層の失敗に、止められたくない) | 「`OrderLogic` だけ、ビルドとテストを回して」(`--project OrderLogic`。テストは `OrderLogicTest` / `OrderLogic.Tests` と推測。UI テストは `OrderLogic.UITests`) |
| MFC / WPF / WinForms の、実行時に壊れる所を、静的に調べたい | 「`mfc-check` して」など (`mfc-check` / `wpf-check` / `winforms-check`) |
| ライブラリ (NuGet・vcpkg・GitHub のソース) を、足したい | 「○○を追加して」(`add-package`) |
| Visual Studio で、ソリューションを開く・ブレークポイントを置く・デバッグ実行する | 「Visual Studio で開いて」「ブレークポイントを置いて」「デバッグを実行して」(`vs-debug`) |
| コミットしたものを、リモートに push したい (fetch・状態の確認も) | 「push して」「fetch して」(`git-remote`) |
| 画面を、UI ガイドラインに沿って、設計・レビューしたい | 「画面をレビューして」(`ui-design-review`) |
| 旧い構成 (Presenter 中心) の WinForms の画面を、画面モデルの構成へ移したい | [`MIGRATION-SCREEN-MODEL.md`](MIGRATION-SCREEN-MODEL.md) の手順で、1 画面ずつ頼む (**移さなくても動く。急がない**) |

### 前提 (ビルドとテストをするとき)
Windows 側で、**ウォッチャー** (`run_watcher.cmd`) を、対象のプロジェクトのフォルダで、起動しておく。ビルドとテストは、ウォッチャー経由でしか、実行できない。静的検査 (`mfc-check` など) と、ソリューションの作成・層の追加は、ウォッチャーがなくても、できる。

**ウォッチャーの版:** 1 つの層だけ回す (`--project`) には 2.98.0 以降、Visual Studio の操作 (`vs-debug`) には 2.90.0 以降が要る。古いときは、結果の末尾に `NOTE:` が出る (下の「3」)。ホスト側を配り直して (`install/install.sh`)、ウォッチャーを再起動する。

### 新しい Skill を使えないとき
Skill を配布したあと (`install/install.sh --skills-only`) は、**Claude Code のセッションを、新しく起動する。** 起動中のセッションには、反映されない。ホームの `~/.claude/skills/` に配っても、プロジェクトの `.claude/skills/` に配っても (`--skills-dir`。README の「5-2」)、同じ。

## 2. 承認と差し戻しの言い方

`/new-solution`、`/add-project`、`/update-from-ideas`、`/add-feature` は、**案を示して、承認を得るまで、何も作らない・書かない**。承認は、決まったコマンドではなく、ふつうの会話で伝える。

### 承認するとき
**はっきりした肯定の返事**を書く。

```
はい、この内容で進めてください
承認します。次に進めてください
OK、この案で足してください
```

### 承認にならない返事
次のものは、**承認として扱われない** (Claude は、案を直して、もう一度、承認を求める)。

- 案への質問や修正 (「ここはどうなる?」「名前を変えて」)。
- **ほかの質問への答え** (例: 案が出ているときに、「参照する層は LogicLayer です。」だけを返す)。
- 「案を見せて」「確認だけ」。

### 直してほしいとき (差し戻し)
承認せずに、**どこを・どう直すか**を、具体的に伝える。Claude が、直して、もう一度、案を示す。納得できたら、改めて承認する。

```
参照先を LogicLayer に変えてください
テストは、なしにしてください
名前を ReportView にしてください
```

### やめたいとき
承認しなければ、何も作られない。はっきり、やめる場合は、そう伝える。

```
承認しません。案の確認だけです。中止してください。
```

### 承認のあとで、間違いに気づいたとき
会話で、「○○を直して」と伝える。作られたファイルは、そのまま残るので、直しを依頼する。**Git のリポジトリなら、`git status` と `git diff` で、変わった所を、確かめられる。**

### 確認の依頼に、「進めてよい」を混ぜない
案の内容を、確かめたいだけのとき (例: 「diff を示してください」) は、「同一なら、そのまま進めてください」のような、承認の文を、**一緒に書かない**。承認として受け取られ、そのまま実行される。確かめたいことと、承認は、分けて書く。

## 3. 困ったとき

ウォッチャーの細かい症状 (`ENV_ERROR`、文字化け、テストの `TIMEOUT` など) は、[`host-tools/README.md` の「7. トラブルシューティング」](../host-tools/README.md) に、一覧がある。ここでは、**使うときに、よく迷う点**だけを書く。

| こんなとき | どうなる・どうする |
|---|---|
| `WATCHER_NOT_RUNNING` と出る | ウォッチャーが、起動していない。対象のプロジェクトのフォルダで、`run_watcher.cmd` を起動する (15 秒、フラグが回収されないと、この結果になる) |
| ビルドやテストが、長い間、進まない | ウォッチャーのウィンドウを、確認する。タイトルに `選択` と出ていたら、コンソールを、クリックしたため、出力が止まっている。Enter か Esc で、再開する。テストが `TIMEOUT` なら、`host-tools/README.md` を見る |
| `NOTE: 版の不一致` と出る | 警告だけで、結果には、影響しない。ウォッチャーが、**ホスト側が最後に変わった版より古い**ときだけ出る。ウォッチャーが古いのが原因なので、`install/install.sh` (引数なし) で、ホスト側を配り直し、ウォッチャーを再起動する。Skill だけを配ったときは、出ない |
| 新しい Skill が出ない・動きが古い | 配布したあと、セッションを、新しく起動したか、確認する。配布されたかは、`~/.claude/skills/<Skill 名>/VERSION` で、わかる |
| `--project` を付けたのに、`NOTE: ... プロジェクト単位 (project=) で処理していない` と出る | ウォッチャーが古い (2.98.0 より前)。古いウォッチャーは、`project=` を読まず、**ソリューション全体を処理する** (結果は出るが、層だけではない)。`install/install.sh` で配り直し、ウォッチャーを再起動する |
| `ENV_ERROR` で、`no project named 'XXX'` と出る | `--project` の名前が、ソリューションにない。出力に、ソリューションにあるプロジェクトの名前の一覧が出る。**ソースの問題ではない**ので、Claude は、直さずに止まる。名前を直して、もう一度 |
| `ENV_ERROR` で、`no test project for 'XXX'` と出る | その層に、テストのプロジェクトがない (`XXXTest` / `XXX.Tests` を探した)。テストなしの層 (メインのアプリなど) は、ビルドだけならできる (「`XXX` だけビルドして」)。テストが要るなら、`/add-project tests` で足す |
| `MSB4126` (無効なソリューション構成 `Debug\|x64` など) が出る | ソースの問題ではない。(1) ウォッチャーの Platform が、ソリューションと食い違っている (`Win32` のソリューションを、`x64` のウォッチャーで)。(2) **.NET だけの `.slnx` に C++ の層を足した**とき、`.slnx` に `x64` の構成がない (v2.98.2 以降の `/add-project` は、足す。古い版で足したなら、`.slnx` の `<Configurations>` に `<Platform Name="x64" />` を足す) |
| ビルドが `requires a manifest with a specified baseline` で止まる | GoogleTest (vcpkg) の準備が、まだ。「vcpkg の baseline を固定して」と頼む (`package_once.sh "<フォルダ>" --timeout 1800 "vcpkg baseline" "vcpkg install"`。初回は数分) |
| ビルドが `__MSBUILD_COMMON_DIR_NOT_SET__\Common.props` が見つからない、で止まる | 共通の MSBuild 設定の場所 (環境変数 `MSBUILD_COMMON_DIR`) が、Windows 側に設定されていない。設定して、Visual Studio とウォッチャーを起動し直す。または、`/add-project common` の案内に従う (README の「3-2」) |
| `/コマンド` を打っても、反応しない | スラッシュ専用の Skill (`/new-solution`、`/add-project`、`/new-solutions`、`/ui-test-first`) は、依頼文では、起動しない。スペルとスラッシュを確認し、配布とセッションの再起動も確認する |
| 案が、気に入らない | **承認しないことが正解**。直したい点を、具体的に伝える (上の「2」) |
| 途中で、やめたい | 「中止してください」と伝える。`/add-project` などは、承認の前なら、何も作られていない。Esc でも、中断できる |
| ビルドエラーやテスト失敗が、直らない | Claude が、原因を読んで、自動で直し、繰り返す。同じ失敗が続くと、**止めどき**で、報告して止まる。ログは、プロジェクトのフォルダの `.claude-logs/` (`build.log`、`test.log`) と、`build_error.log` にある |
| 画面のファイルが、勝手に書き換わった | `/add-project` の「切り出し」(アプリの中の `ViewModels/` を、層へ移す) は、**案に、削除と書き換えが、明記され、承認のあとにだけ**行われる。利用者が編集したファイルが、1 つでもあるときは、**どのファイルも、削除せず**、止まって聞く |
| どの Skill が動いたか、知りたい | 結果の末尾の `RESULT_INFO:` (どの実行の結果か) を見る |

### それでも解決しないとき
状況を、そのまま、会話で伝える (「テストが○○で落ちる」「案のここが不安」)。エラーの原文を、貼ると、次の一手を、提案できる。

### リモートに push する・fetch する (`git-remote`)

「push して」「fetch して」「リモートの状態を見て」と頼みます (ウォッチャー 2.102.0 以降。ウォッチャーの再起動が要ります)。

- **Windows の `git.exe` で実行します。** 認証は、Visual Studio の Git と同じ (Git Credential Manager) なので、GitHub 以外のリモートでも通ります。WSL の `git` の認証は、使いません。
- **push は、あなたが頼んだときだけ**です。実行の前に、Claude は、状態 (ブランチ・リモート・push される予定のコミット) を、伝えます (ブランチとリモートを指定して頼んだときは、省くことがあります。結果に、同じ内容が出ます)。
- **`AUTH_REQUIRED` と返ってきたら:** Visual Studio の「Git > プッシュ」で、1 回、サインインしてください (以降は、Claude からも通ります)。Claude は、認証情報を探したり、作ったりしません。
- **`main` / `master` へは、push しません** (「main に push してよい」と言ったときを除く)。強制 push・ブランチやタグの削除は、持ちません。
- **pull・merge・rebase は、Claude は、しません。** `BEHIND:` (リモートの先行) が出たら、VS で、取り込みます。
- 結果のファイル (`git_result.txt` など) は、ソリューションのフォルダに作られます (`/new-solution` が作る `.gitignore` に入っています。既存のものには、手で足します)。

### Visual Studio を、Claude に操作させるとき (`vs-debug`)

「Visual Studio で開いて」「ブレークポイントを置いて」「デバッグを実行して」と頼みます (ウォッチャー 2.90.0 以降。README の「2-8」)。

- **ブレークポイントを置くだけでは、実行しません。** 実行は、**「デバッグを実行して」と言ったときだけ**です。実行の前に、ビルドが成功している必要があります。
- **デバッグ中は、Claude は、ビルド・テスト・編集をしません** (exe がロックされるため)。止めるのは、あなたの操作です (Shift+F5)。
- **Visual Studio で、未保存の編集があるファイルは、Claude は、編集しません。** 保存 (Ctrl+S) してもらうか、別のファイルを進めるかを、聞かれます。Claude の編集を、VS に取り込むには、VS の設定 (ツール → オプション → 環境 → ドキュメント →「ファイルが外部で変更された場合は、保存されていない変更がない限り、自動的に読み込む」) を、有効にしておくと、手間がありません。
- **ステップ実行で、バグを探させられます** (ウォッチャー 2.101.0 以降)。**「ステップ実行して」「バグを探して」** と頼みます。Claude は、ブレークで止め、F10 (ステップ オーバー)・F11 (ステップ イン)・Shift+F11 (ステップ アウト)・F5 (続行) で進めて、**1 歩ごとの場所と、変わった変数**を読み、期待とずれる所を探して、原因の候補を報告します。
  - **あなたが、求めたときだけ**です。**1 回の依頼で、合計 30 歩まで**で、超えそうなときは、続けてよいかを聞かれます。同じ場所に 3 回戻ったら、止まります。
  - **式の値も見られます** (ウォッチ)。**読み取りだけ**で、代入や `++` は断られます。関数の呼び出しは、了承なしには、使いません。
  - **アプリの処理は、実際に進みます** (ファイルへの書き込みや通信も、実行されます)。副作用のある処理の手前では、確認を求められます。
  - **デバッグの停止 (Shift+F5) は、あなたの操作です** (Claude は、停止の操作を持ちません)。原因が分かったら、報告して止まるので、止めてから、直しを頼んでください。
  - モーダルダイアログ (メッセージボックスなど) が出て進まないときは、`STEP_TIMEOUT` と返ります。ダイアログを操作してから、続けてください。
- **VS が 2 つ以上、同じソリューションで開いている**と、止まって、どちらで続けるかを聞かれます。
- **デバッグのログと、止まった状態を、Claude に解析させられます** (ウォッチャー 2.99.0 以降)。VS でデバッグを走らせたまま (または、ブレークで止めたまま)、**「デバッグのログを見て」「止まっている変数を見て」** と頼みます。Claude は、出力ウィンドウの「デバッグ」ペイン (`Debug.WriteLine`・`Trace`・`OutputDebugString`・`TRACE`) の最後の行と、止まった時点の例外・呼び出し履歴・ローカル変数を、読み取って、解析します。VS は、起動も、前面への切り替えもされません。
  - **`Console.WriteLine` は、出力ウィンドウに出ません** (WinForms・WPF)。アプリが自分でファイルに書くログは、そのファイルの場所を伝えます。
  - ログには、**個人情報などが含まれうる**ので、Claude は、解析に必要な行だけを引用します。全文は、ソリューションのフォルダの `vs_debug_output.txt` に残ります (生成するソリューションでは、`.gitignore` 済み)。

### Visual Studio と WSL の、両方で、Git を操作するとき

同じリポジトリを、Visual Studio (Windows の Git) と、WSL の Claude (WSL の `git`) の、両方で操作するときの決まりです。詳しくは、`rules/git-wsl.md` (配布すると `~/.claude/rules/git-wsl.md`)。

- **改行は、`.gitattributes` が決めます** (`* text=auto eol=crlf`)。リポジトリの中は LF、作業フォルダは CRLF。どちらの Git で操作しても、同じ結果です。`.gitattributes` がないリポジトリには、`new_solution.py <フォルダ> --add-gitattributes` で足します。
- **WSL の `git` は、リポジトリごとに、設定します:** `core.autocrlf false`、`core.fileMode false`、`user.name` / `user.email` (VS の設定は、WSL から見えません)。
- **コミットの前に、`git status --short` と `git diff --stat`。** ほとんど全部のファイルが「変更」に見えるときは、改行かモードの違いです (`git ls-files --eol <ファイル>`、`git diff --ignore-cr-at-eol --stat`)。そのままコミットせず、Claude に、まとめて直させず、確かめてから、決めます。
- **同時に、触りません。** VS が Git を操作している間は、WSL の `git` を動かさない (`index.lock`)。WSL でブランチを切り替えたら、VS で「すべて再読み込み」します。
- **プッシュ・取得・PR・マージは、あなたが、VS で行います** (サンドボックスから、GitHub へは、届きません)。Claude が、コミットするのは、頼んだときだけです。

## 4. Token を使いすぎるとき

ウォッチャーと連携して作業すると、Token が、想定より多く出ることがある。**測った結果 (2026-11-24、WPF の TDD の Red まで、14 ターン)** と、効く順の対処を、まとめる。

### どこで使うか (測定)
- **費用の中心は、「文脈の大きさ × ターン数」**。Claude は、毎ターン、これまでの全部を読み直す (単価は安いが、量が大きい)。1 つのセッションに、いくつも作業を詰めると、後半ほど、1 ターンが重くなる (この開発のセッションは、219 ターンで、文脈が 30 万トークンまで伸びた)。
- **新しいセッションの直後が、約 45〜49k トークン**。うち約 31k は、Claude Code 本体 (システムとツール) で、減らせない。残りは、Skill の一覧 (約 8〜10k)、エージェントの一覧 (約 3k)、プロジェクトの `CLAUDE.md` (約 3〜5k)。
- **作業を始めると、固定の読み込みが入る。** Skill の本文 (`csharp-test-first` で約 11.6k)、規約 (`.cs` を読むと `csharp-common.md` が約 5.9k)。Red までの増加の約 77% は、これだった (実際の作業は約 5k)。

### 効く順の対処
1. **作業ごとに、新しいセッションを始める** (または `/clear`)。文脈が 10 万トークンを超える前に区切ると、読み直しが、小さく済む。確認用フォルダの作業は、「1 機能 = 1 セッション」が目安。
2. **確認用フォルダでは、使わないプラグインを止める。** そのフォルダの `.claude/settings.json` に書くと、**そのフォルダだけ**に効く (ほかには、影響しない)。実測で、新しいセッションの直後が、**49.3k → 45.1k (約 8.5% 減)** になった (Skill 72 → 54 本、エージェント 18 → 0 本)。

   ```json
   {
     "enabledPlugins": {
       "superpowers@anthropic-plugin-directory": false,
       "pr-review-toolkit@anthropic-plugin-directory": false,
       "feature-dev@anthropic-plugin-directory": false,
       "code-simplifier@anthropic-plugin-directory": false,
       "claude-security@anthropic-plugin-directory": false,
       "playwright@anthropic-plugin-directory": false,
       "context7@anthropic-plugin-directory": false
     }
   }
   ```

   止めるものは、あなたが使うものに合わせて選ぶ (上は、TDD・ビルド・デバッグだけを行うフォルダの例。名前は、`~/.claude/settings.json` の `enabledPlugins` にある)。
3. **古い `CLAUDE.md` は、長いまま。** v2.105.0 から、`/new-solution` が作る `CLAUDE.md` は短い (WPF + ロジック層 + UI テストで、7,034 → 4,498 文字)。すでにあるソリューションの「UI テスト (FlaUI)」の節は、`add_ui_tests.py --refresh-claude-md` で、新しい版にできる。
4. **ウォッチャーを、先に起動しておく。** 起動していないと、`WATCHER_NOT_RUNNING` のあとの報告と再実行で、4 ターンほど増える (測定では、14 ターンのうち 4 ターン)。

### 測り方
- 新しいセッションの直後に `/context` を実行すると、内訳 (System prompt / System tools / Memory files / Skills / Messages) が見える。作業のあとに、もう一度実行すると、増えた分が分かる。**Claude が 1 回の依頼で自動で進んでいる最中は、`/context` を打てない**ので、途中の量が知りたいときは、セッションのログ (`~/.claude/projects/<フォルダ>/*.jsonl`) の、ターンごとの `usage` を集計する。
- **セッションのログを集計する:** `tools/token_report.py` が、ログ (`~/.claude/projects/<作業フォルダの / を - にした名前>/<セッション ID>.jsonl`) を読み、合計・文脈の大きさ・Skill と規約の読み込み・ツールの結果の量を出す。フォルダを渡すと、いちばん新しいログを読む。`--timeline` を付けると、ターンごとの文脈の増減と、使ったツールが並ぶ (文脈が急に増えたターンを探せる)。
  ```bash
  python3 -I tools/token_report.py --timeline ~/.claude/projects/-mnt-c-Workspace-macsignee-source-repos-ClaudePlayground-PS5
  ```
  出力は、`TURNS:`・`TOTAL:`・`CONTEXT:`・`SKILL:`・`MEMORY:`・`TOOL:` の行 (`--timeline` では `T<番号>` の行も)。ログの形式は、Claude Code の版で変わりうる (読めない行は、読み飛ばす)。
