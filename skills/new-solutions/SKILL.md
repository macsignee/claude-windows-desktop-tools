---
name: new-solutions
description: 作業フォルダの下に、同じ題材の、種類違いの複数のソリューション (WPF / WinForms / MFC など) を、候補として、まとめて作り、個別に比べる。`solutions.md` (候補の一覧) から作る。1 つのソリューションだけを作るときは、`/new-solution` を使う。「種類を変えて比べたい」「候補ごとにソリューションを作りたい」という依頼で使う。
argument-hint: "[create|sync-spec|resolve]"
disable-model-invocation: true
---

# 候補ごとのソリューションを作る (/new-solutions)

**まれな使い方。** 1 つのソリューションを作るなら、`/new-solution` を使う (こちらは、使わない)。
カレントは、**作業フォルダ** (例: `...\repos\ToDo`)。`.sln` / `.slnx` が、すでにあるフォルダでは、使わない (「ここは、1 つのソリューションです。`/new-solution` のテストの後付けなどを使います」と伝えて、止まる)。
個々の候補の作り方 (種類・層・テストの意味、`--tfm`、名前空間) は、`/new-solution` と同じ (`new_solution.py` の引数)。
**候補を作るスクリプトは、`/new-solution` の `scripts/` にある** (`~/.claude/skills/new-solution/scripts/new_solutions.py`)。

**同じ題材を、種類を変えて (WPF / WinForms / MFC など)、候補ごとのソリューションとして作り、個別に比べる**ためのモード。カレントは、**作業フォルダ** (例: `...\repos\ToDo`)。
`docs/` (壁打ちのメモ・仕様書) は、作業フォルダにたまる (**正本**)。候補は、その下のフォルダ (`<作業フォルダ>/<候補名>/`) に、独立したソリューションとして作られる。
**ウォッチャーは、候補ごとに 1 つ** (`run_watcher.cmd "<候補のフォルダ>"`)。ホスト側は、変わらない。

```
ToDo/   docs/ideas/  docs/specs/  solutions.md  TodoWpf/  TodoWin/  TodoMfc/
```

1. **`solutions.md` を作る・読む。** なければ、**会話で聞き取って、書く** (種類・層・テストは、候補ごとに質問。**テストは、必ず質問する**)。形:
   ```markdown
   - 仕様書: docs/specs/todo.md      (省略可。作業フォルダからの相対。全候補に取り込む)
   - 名前空間: todo                   (省略可。表の「名前空間」列で、候補ごとに変えられる)

   | 名前 | 種類 | 層 | テスト | UIテスト |
   |---|---|---|---|---|
   | TodoWpf | wpf | data,logic,viewmodel | mstest | none |
   | TodoMfc | mfc-dialog | logic | gtest | none |
   ```
   **質問の順序と、選択肢 (v2.24.1):**
   - **候補ごとに、まとめて聞く。** 順序は、`候補 1: 種類 → 層 → テスト → UIテスト` を終えてから、`候補 2: ...`。**候補をまたいで、項目ごとに並べない** (どの候補の質問か、分からなくなる)。質問の見出しに、**候補の名前**を入れる (例: 「TodoCore の層は?」)。
   - **共通の項目 (仕様書の有無、名前空間) は、最後に、まとめて聞く。**
   - 候補の数と名前の質問は、**選択肢の例を、exe の組み合わせだけにしない** (DLL を含む例 (例: `TodoWpf, TodoCore (dll)`) も、出す)。**「その他」の選択肢は、出さない** (入力欄は、画面が自動で付ける)。
   - 名前から種類が明らかな候補 (`TodoWpf` など) は、系統の質問を省き、種類の確認だけにしてよい。
   **種類の質問は、2 段階にする** (質問の画面は、選択肢が 4 つまで。種類は 10 個あるので、先頭の 4 つだけを出さない):
   1. 系統: 「.NET の画面つき (WPF / WinForms)」/「MFC (C++ の画面つき)」/「C++ の画面なし・ライブラリ (Win32 / コンソール / DLL / 静的ライブラリ)」/「C# のクラスライブラリ」。
   2. 系統の中の種類: `wpf` / `winforms`。`mfc` (SDI) / `mfc-mdi` / `mfc-dialog`。`win32` / `console` / `dll` / `lib`。(`csharp-dll` は、系統だけで決まる)。
   候補が複数あるときは、まず**候補の数と名前**を聞き、**候補ごとに**、2 段階で質問する。

   **種類 (`種類` 列) は、exe だけでなく、DLL も選べる:**

   | 種類 | 内容 | 層・テストの扱い |
   |---|---|---|
   | `wpf` / `winforms` | .NET の exe | 層 (data / logic / viewmodel)、`mstest`、`UIテスト` |
   | `mfc` / `mfc-mdi` / `mfc-dialog` / `win32` / `console` | C++ の exe | 層 (logic / data)、`gtest` |
   | `dll` / `lib` | C++ の DLL / 静的ライブラリ。**メイン自身が、テストの対象** | 層は `none` でもよい。`gtest` (テストの exe が付く)。`UIテスト` は、なし |
   | `csharp-dll` | C# のクラスライブラリ | 層は `none` でもよい。`mstest` |

   exe と DLL を、混ぜてよい (例: `TodoWpf` と `TodoCore` (`dll`) を、並べて比べる)。

   名前は、**フォルダ名 = ソリューション名** (英数字と `_`)。列は、`new_solution.py` の引数と同じ (任意の列: 層の種類・TFM・備考)。仕様書は、`/update-from-ideas` で、作業フォルダの `docs/specs/` に作る (**構成案は、使わない**)。
2. **案を示して、了承を得る (必ず止まる)。**
   ```bash
   python3 ~/.claude/skills/new-solution/scripts/new_solutions.py create "$PWD" --dry-run
   ```
   候補ごとの、種類・層・テスト・作るファイル・仕様書の取り込みを、要約して見せる。**1 つでも不正なら、何も作られない** (終了コード 2)。
3. **作成する** (`--dry-run` を外す)。すでに `.slnx` がある候補は、触らない (行を足して、再実行すると、足した分だけ作られる)。**自分で、`.slnx` や `.vcxproj` を手書きしない。**
   - 仕様書 (と「元:」のメモ) が、各候補の `docs/` に取り込まれ、**ハッシュが、候補の `docs/specs/.spec-sync.json` に、記録される。**
   - 全候補の `CLAUDE.md` に、「## 比較の候補」の節 (自動生成。候補の一覧と、仕様書の扱い) が、書かれる・更新される。
   - **GoogleTest (vcpkg) の仕上げと、最初のベースライン確認は、`create` では、しない** (候補ごとのウォッチャーが要る)。**候補を扱うときに行う。** `gtest` の候補で、`create` の出力に `GTEST_VCPKG: no-baseline` と出たら、その候補のウォッチャーを起動してから、次を実行する (自分でフラグを置かない。長いので、`run_in_background: true`、完了通知を待つ。`$候補` は、`resolve` で決めたパス)。**調査 (Explore) に回らず、この手順を使う:**
     ```bash
     bash ~/.claude/skills/add-package/scripts/package_once.sh "$候補" --timeout 1800 "vcpkg baseline" "vcpkg install"
     ```
     結果の表は、`add-package` Skill の「手順 2: vcpkg」と同じ。`GTEST_VCPKG: present` なら、仕上げは要らない。
4. **次の手順を、伝える** (出力に、候補ごとの、Windows のパスと `run_watcher.cmd` のコマンドが出る)。**候補の数だけ、ウォッチャーを起動してもらう** (まとめて起動するなら、`run_watchers.cmd "<作業フォルダ>"`。候補ごとに別のウィンドウで `run_watcher.cmd` を起動する。`/list` を付けると、一覧だけ)。
5. **仕様を更新したとき:** 作業フォルダの仕様書 (正本) を直し (`/update-from-ideas`)、`new_solutions.py sync-spec "$PWD" --dry-run` で、確認してから、`sync-spec` で反映する。
   **候補側で、編集されたコピーは、上書きされず、「衝突」と報告される** (終了コード 1)。ユーザーに、どちらを残すかを、確認する (候補側が不要なら、そのコピーを消して、再度 `sync-spec`)。**テストケースの種 (`*.cases.md`) は、更新されない** (チェック済みを守る)。各候補の `/add-feature` の計画で、見直す。
6. **個別の検討:** 対象の候補は、`new_solutions.py resolve "$PWD" [<候補名>]` で決める (ほかの Skill の `$SLN_DIR` も、同じ)。**候補ごとに、`build-test-loop` / `/add-feature` などを、独立して進める。他の候補は、読まない・書かない。**

## しないこと
- 作業フォルダそのものを、ソリューションにしない (`.slnx` を作らない)。
- ユーザーの了承なしの作成。`テスト` の、黙った既定値の採用。
- `git commit` / `git push` / `git init`。
