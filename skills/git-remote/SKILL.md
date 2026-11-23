---
name: git-remote
description: Git のリモートの操作 (push・fetch・状態の確認) を、Windows 側のウォッチャー (Windows の git.exe) に頼んで行う手順。「push して」「プッシュして」「fetch して」「リモートの状態を見て」「リモートに上げて」といった依頼で使う。認証は、Visual Studio の Git と同じ (Git Credential Manager) なので、GitHub 以外のリモート (Azure DevOps・GitLab・社内サーバー) でも通る。WSL の git からは、その認証が見えず、サンドボックスからリモートへも届かない。強制 push・ブランチやタグの削除・pull・merge は、持たない (ユーザーが VS で行う)。コミットは、この Skill ではなく、WSL の git (rules/git-wsl.md)。
---

# Git のリモートの操作 (push・fetch・状態)

> **パスの書き方:** `<Skill群>` = この Skill のフォルダ (Base directory) の 1 つ上。ほかの Skill も、そこにある。コマンドでは、実際のパスに置き換える。

Claude (WSL) は、リモートの認証 (Windows の Git Credential Manager。Visual Studio と同じ保管先) を、使えない。そこで、**ホスト側のウォッチャーに、Windows の `git.exe` での操作を、依頼する** (`trigger_git.flag`)。
**自分で `git push` / `git fetch` / `powershell.exe` を実行しない** (WSL の `git` では、認証が通らず、サンドボックスの外にも出られない)。同梱のスクリプトを使う。
コミットは、これまでどおり、WSL の `git` (ユーザーが頼んだときだけ。`rules/git-wsl.md`)。

## いつ使うか
- **ユーザーが「push して」と頼んだときだけ push する** (コミットと同じ。頼まれていないのに、作業の区切りで push しない)。
- 「fetch して」「リモートの状態を見て」(取り込みの要否の確認) は、頼まれたときに実行してよい。読み取りだけ・作業フォルダを変えない操作 (`--status`、`--fetch`) は、確認なしで使える。

## 手順
1. **状態を見る** (push の前に、見るのが原則。**ユーザーが、ブランチとリモート、または内容を指定して頼んだときは、省いてよい。** 例: 「`gr-test5` を `origin` に push して」。省いたときも、手順 2 の `--push` が、最後に、状態を返す。`BRANCH:` と `TO_PUSH:` を見て、頼まれた内容と違えば、すぐに、ユーザーに伝える。**省かないとき:** 初めての push、`main` / `master`、リモートが複数、頼まれた内容があいまい、現在のブランチが、頼まれたものと違うかもしれないとき。push は、取り消せない):
   ```bash
   bash <Skill群>/git-remote/scripts/git_once.sh <ソリューションのフォルダ> --status
   ```
   `BRANCH:` (現在のブランチ)・`UPSTREAM:` (上流)・`REMOTE:` (リモートと URL。認証情報は伏せる)・`AHEAD:` / `BEHIND:`・`TO_PUSH:` (push されるコミットの一覧)・`UNCOMMITTED:` (未コミットのファイル数。push はコミット済みの分だけを送る)。
   **状態を見たときは、ユーザーに、「`<ブランチ>` の N 件のコミットを、`<リモート>` に push します」と伝えてから、実行する** (内容が、頼まれたものと合っているか確かめる。合っていなければ、止まって聞く)。
2. **push する:**
   ```bash
   bash <Skill群>/git-remote/scripts/git_once.sh <ソリューションのフォルダ> --push
   ```
   - **初めての push (リモートに、同じ名前のブランチがない)** は、`--set-upstream` を付ける (リモートに、ブランチを作る。ユーザーに、一言、確認する)。リモートに、同じ名前のブランチが、すでにあるなら、`--set-upstream` なしでも push できる (`UPSTREAM: (not set; the branch origin/<名前> exists ...)` と出る。比べる先は、その `origin/<名前>`)。
   - **`UPSTREAM_PENDING:` と出たら:** push は成功している。上流 (`.git/config` への書き込み) は、**このコマンドの実行中は書けない** (Claude Code のサンドボックスが、`.git/config` への書き込みを禁じていて、実行中は `config.lock` が見える)。ウォッチャーが、**結果を返したあと**に、自分で設定する (数秒)。**数秒待って、`--status` で、`UPSTREAM:` を確かめる。** `.git/config.lock` を、消さない (本物のファイルではない)。
   - **リモートが複数ある・`origin` 以外のとき:** `--remote <名前>` (設定済みのリモート名だけ。URL は、受け付けない)。
   - **`main` / `master` へ push するとき:** ユーザーが、「main に push してよい」と、はっきり言ったときだけ `--allow-main` を付ける。言われていなければ、付けない (作業ブランチを切る案内をする)。
3. **fetch する (取り込みの要否の確認):** `--fetch` (すべてのリモート) または `--fetch <リモート名>`。作業フォルダは、変わらない。続けて、返ってきた `BEHIND:` を見る。
4. 結果 (`OK` / 失敗の種類) を、ユーザーに、報告する (push したブランチ・リモート・コミット数)。

`--fetch` と `--push` は、併用できる (fetch → push の順)。どの実行も、最後に、状態 (`--status` と同じ内容) を返す。

## 結果の読み方 (標準出力の 1 行目と終了コード)
| 1 行目 | rc | 意味と対応 |
|---|---|---|
| `OK` | 0 | 成功。`PUSHED:` / `FETCHED:` / `NOTHING_TO_PUSH:` と、状態が続く。`UPSTREAM_PENDING:` があれば、上は、そのあとの確認 |
| `FAILED` | 1 | 失敗。理由が続く (HEAD が切り離されている・上流がない・リモートがない、など)。理由に従って直すか、ユーザーに聞く |
| `BAD_ARGS` | 2 | 引数の形が不正 (強制 push などの引数は、ここで断られる) |
| `WATCHER_NOT_RUNNING` | 3 | ウォッチャーが動いていない、または古い (HOST_VERSION 2.102.0 以降が必要)。ユーザーに、`install.sh` での再配布と、ウォッチャーの再起動を頼む |
| `ENV_ERROR` | 4 | Windows 側に `git.exe` がない、など。ユーザーに伝える |
| `TIMEOUT` | 5 | 結果が出ない。**もう一度実行しない** (ネットワークか、サインインの待ちかもしれない)。報告して、止まる |
| `AUTH_REQUIRED` | 6 | **認証が要る。ユーザーが、Visual Studio (Git > プッシュ) で、1 回サインインする。** 終わったら、もう一度、この Skill で実行する。**認証情報 (トークン・パスワード・鍵) を、探さない・作らない・設定しない。** URL にトークンを埋め込む案も、出さない |
| `REJECTED` | 7 | リモートが拒否した (リモートに、手元にないコミットがある (non-fast-forward)・保護されたブランチ、など)。**強制 push はしない。** ユーザーに、状況 (`BEHIND:` の件数など) を伝え、取り込み (pull・merge・rebase) は、ユーザーが、VS で決める |

## 持たない操作 (頼まれても、この Skill では、しない)
- **強制 push** (`--force`・`--force-with-lease`)、ブランチ・タグの**削除**、`--tags`、`--mirror`: 引数として、断られる。必要な場面は、ユーザーが、VS で、判断して行う。
- **pull・merge・rebase:** 作業フォルダを書き換え、改行コード (`.gitattributes`) や `index.lock` の問題が絡むため、持たない。ユーザーが、VS で行う (`BEHIND:` が 0 より大きいときは、そう案内する)。
- **PR の作成・マージ:** この Skill の対象外 (リモートの種類ごとに違う)。

## なぜ、WSL の git と併用しても、安全か
- **push は、インデックスも作業フォルダも書き換えない。** 改行コードの違い (`.gitattributes` が、WSL の git と Windows の Git の差を、吸収している) も、`index.lock` の衝突も、起きない。コミットが済んだオブジェクトを、送るだけ。
- Visual Studio 自身の push も、Windows の Git。ウォッチャー経由でも、VS が、自分で押したのと同じ (新しい併用は、増えない)。
- 入力待ちをしない設定 (`GIT_TERMINAL_PROMPT=0`・`GCM_INTERACTIVE=never`) で実行する。サインインが要るときは、待たずに `AUTH_REQUIRED` で返す (画面にダイアログが出て、ウォッチャーが、固まることはない)。1 コマンドは、120 秒で、強制終了する。
- VS が Git を操作している間 (コミット・ブランチの切り替え・取得) は、`--fetch` も、待つ。`index.lock` が出たら、VS の操作の終わりを待つ (`rules/git-wsl.md`)。

## 注意
- 実行後、VS の「Git の変更」ウィンドウの、ブランチの先行・遅れの表示は、VS が、次の更新で、反映する (必要なら、ユーザーが、更新する)。
- 結果のファイル (`git_result.txt`・`git_output.txt`・`git_error.log`) は、ソリューションのフォルダに、作られる。コミットしない (`.gitignore` に、`git_*.txt` と `git_error.log` を足すか、ユーザーに確認する)。
