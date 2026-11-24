---
paths:
  - "**/.gitattributes"
  - "**/*.sln"
  - "**/*.slnx"
---

# Git: Visual Studio (Windows) と WSL の、両方で、操作するときの決まり

対象: Windows のフォルダ (`/mnt/c/...`) の、リポジトリを、Visual Studio (Windows の Git) と、WSL の `git` の、両方で操作するとき。**この規約は、Git のコマンドを、実行するときに、読む。**

## 改行・文字コードは、`.gitattributes` が決める
- `.gitattributes` の `* text=auto eol=crlf`: **リポジトリの中は LF、作業フォルダは CRLF** (VS の既定)。`.sh` は LF。WSL の `git` と、Windows の Git の、どちらで操作しても、同じ結果になる (`core.autocrlf` より、`.gitattributes` が優先される)。
- **`.gitattributes` がなければ、足す:** `/new-solution` Skill の `scripts/new_solution.py <フォルダ> --add-gitattributes` (最小版。ユーザーに確認してから)。
- 文字コード (UTF-8 の BOM など) は、Git は変換しない。**既存のファイルを編集するとき、BOM と改行を変えない。**

## WSL の `git` の設定 (リポジトリごと。ユーザーに確認してから)
- `git config core.autocrlf false` (`.gitattributes` に任せる)、`git config core.fileMode false` (`/mnt/c` には実行ビットがなく、全ファイルが「モード変更」に見えるのを避ける)。
- `git config user.name` / `user.email`: VS (Windows) の設定は、WSL から見えない。未設定だと、`empty ident name` で、コミットできない。
- `dubious ownership` が出たら、`git config --global --add safe.directory <リポジトリのパス>`。

## コミットの前に、必ず確認する
1. `git status --short` と `git diff --stat`。
2. **ほとんど全部のファイルが「変更」に見えるとき:** 改行かモードの違い。`git ls-files --eol <ファイル>` (正しい状態は `i/lf w/crlf`)、`git diff --ignore-cr-at-eol --stat` (差が消えるなら、改行だけ) で確かめる。**そのまま、コミットしない。まとめて直さない** (`git add --renormalize .` も同じ)。ユーザーに聞く。
3. 新しく作ったファイルは、LF・BOM なしになる。**規約 (UTF-8 BOM 付き・CRLF) に合わせる** (C++ の `.cpp` / `.h` / `.rc` は、ビルド前に、自動で BOM 付きになる)。`git add` の警告 (`LF will be replaced by CRLF`) は、無害だが、作業フォルダには LF が残る。
4. **Claude Code のサンドボックスの空ファイルを、コミットに入れない。** サンドボックスは、書き込みを禁じるファイル (`.bashrc`・`.bash_profile`・`.zshrc`・`.zprofile`・`.profile`・`.gitconfig`・`.gitmodules`・`.ripgreprc`・`.mcp.json`・`.vscode`・`.idea`・`.claude/*` など) に `/dev/null` を重ねる。**Claude Code のコマンドが動いている間は、これらが、作業フォルダに、空 (0 バイト) のファイルとして見える** (`git status` に、`??` や `D` で出る)。
   - ステージは、**名前を指定して**する (`git add -A` / `git add .` を使わない)。
   - **`git status` に、これらが出ていたら、ユーザーに伝える。** VS の「すべてコミット」では、空のファイルが、コミットに入る (実機: 23 件が入り、push された)。
   - すでにコミットされて `D` になっているときは、**「元に戻す」を押さず**、削除をコミットする。再発の防止は、そのクローンの `.git/info/exclude` に、その名前を足す。
   - そのプロジェクトが、`.mcp.json` や `.vscode` を、本当に管理しているとき (中身のあるファイル) は、対象外。

## 同時に、触らない
- **VS が Git を操作している間 (コミット・ブランチの切り替え・取得) は、WSL の `git` を動かさない** (`index.lock`)。`Unable to create '.git/index.lock'` が出たら、VS の操作の終わりを待つ。ロックファイルは、`git` のプロセスが動いていないと、確かめてから、消す。
- WSL で `git switch` / `git restore` したら、**VS で「すべて再読み込み」し、Git の変更ウィンドウを更新するよう、ユーザーに伝える。**
- **`git commit` は、ユーザーが頼んだときだけ。**
- **プッシュ・fetch・リモートの状態の確認は、`git-remote` Skill (`git_once.sh`) で行う。** WSL の `git` では、リモートの認証 (Windows の Git Credential Manager。VS と同じ) が見えず、サンドボックスからも、リモートへ届かない。Skill は、ウォッチャーに、Windows の `git.exe` で実行させる (GitHub 以外のリモートでも、VS と同じ認証で通る)。**プッシュは、ユーザーが頼んだときだけ。** 強制プッシュ・削除・`main` / `master` への直接のプッシュ (ユーザーが言ったときを除く) は、しない。
- **pull・merge・rebase・PR・マージは、ユーザー (VS)。** 作業フォルダを書き換えるため (改行コードと `index.lock` の問題)。`git-remote` の結果に `BEHIND:` があれば、ユーザーに、案内する。

## 取り込み (pull・merge・rebase) は、ユーザーが VS で行う。運用
**`git-remote` に pull は、持たせない (見送り。ユーザーの決定、2026-11-24)。** 作業フォルダを書き換えるため、VS の未保存の編集との衝突・マージの衝突・取り込んだコードのビルドなどの危険が、設計では消せない。次の運用で補う。

**Claude の動き:**
- `git pull` / `git merge` / `git rebase` を、WSL でも、実行しない。「最新にして」と頼まれたら、実行せず、下の手順を案内する。
- `--fetch` と `--status` で `BEHIND:` (リモートの先行) を見て、件数をユーザーに伝える。`REJECTED` (non-fast-forward) のときも同じ。`AHEAD:` と `BEHIND:` が、どちらも 0 より大きければ、分岐していることを伝える。
- ユーザーが「pull した」と言ったら、**以前に読んだファイルは古いと見て、読み直す。** `--status` で `BEHIND: 0` を確かめる。ビルドは、頼まれてから (勝手に始めない)。
- **衝突の最中** (`MERGE_HEAD` やリベースの途中、`<<<<<<<` の印があるファイル) は、そのファイルを、編集・ビルド・コミットしない。ユーザーが、VS で解決したと言うまで、待つ。

**ユーザーが VS で pull するときの手順 (案内する内容):**
1. 手元の変更を、先にコミットする (コミットは、Claude に頼んでもよい)。VS で開いているファイルを、すべて保存する。
2. デバッグ中でなく、ビルドも走っていないこと。
3. 先に「フェッチ」して、VS の履歴で、**取り込まれるコミットと変更を見る。**
4. 手元に、リモートにないコミットがなく、リモートが先行しているだけ (fast-forward) なら、そのまま「プル」。分岐しているときは、内容を見て、マージかリベースかを、ユーザーが決める。
5. 衝突したら、VS の画面で解決する。
6. 終わったら、Claude に「pull した」と伝える。
