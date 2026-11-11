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

## 同時に、触らない
- **VS が Git を操作している間 (コミット・ブランチの切り替え・取得) は、WSL の `git` を動かさない** (`index.lock`)。`Unable to create '.git/index.lock'` が出たら、VS の操作の終わりを待つ。ロックファイルは、`git` のプロセスが動いていないと、確かめてから、消す。
- WSL で `git switch` / `git restore` したら、**VS で「すべて再読み込み」し、Git の変更ウィンドウを更新するよう、ユーザーに伝える。**
- サンドボックスから GitHub へは、届かない。**`git commit` は、ユーザーが頼んだときだけ。プッシュ・取得・PR・マージは、ユーザー (VS)。**
