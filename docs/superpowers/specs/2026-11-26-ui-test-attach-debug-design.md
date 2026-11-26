# 設計: UI テストの仕組みで、デバッグのきっかけの UI 操作を実行する (アタッチモード)

作成: 2026-11-26。状態: 草稿 (ユーザーの承認待ち)。元の構想: `docs/HANDOFF-2026-11-25.md` 第 4-3 節 (案 A)。試作: `poc/attach-debug/`。

## 1. 目的と、その理由
VS のデバッガーで、止めたいコード (ロジックなど、UI の外) があるとき、そこへ到達するには、アプリの画面で、ボタンを押す・文字を入れる、といった操作が要ることが多い。この操作を、人が手でやらずに、**UI テストの仕組み (FlaUI) で自動実行**し、アプリがブレークポイントで止まったら、Claude が、`vs-debug` の `--inspect` / `--step` で、状態を調べる。

狙いは、**UI のバグを追うことではない**。UI 操作は、デバッグ対象のコードへ到達する「きっかけ」にすぎない。

## 2. ゴール・非ゴール・アンチゴール
**ゴール**
- (G1) `uitest_once.sh --attach <プロセス名>` の 1 回の依頼で、VS が起動したアプリに、UI テストがアタッチし、きっかけの操作を撃って、**待たずに終わる**。
- (G2) その後、ウォッチャーが空いていて、`vs_once.sh --inspect` / `--step` が、すぐ通る。
- (G3) WPF・WinForms・MFC の 3 つで動く。
- (G4) デバッグ中のアプリを、**殺さない・閉じない・再ビルドしない**。

**非ゴール**
- ウォッチャーの並行化 (案 B)。1 本のループのまま。
- UI テストが、ステップ実行の最中に、UI を操作し続けること。
- VS のデバッガーがアプリを起動しない、アプリ単独の実行での解析 (R15。別件)。

**アンチゴール (できても、失敗とみなすもの)**
- きっかけの後で、UI を読み続けて、時間切れまで待つテスト (ウォッチャーが、長く塞がる)。
- デバッグ中のアプリが、ツールの後始末で、終わってしまうこと。

## 3. 試作で分かったこと (2026-11-26。実機)
| | WPF (PS5) | MFC (UiLayerHost) |
|---|---|---|
| アタッチ (別プロセスの FlaUI) | 成功。52 ms | 成功。24 ms |
| きっかけの操作 | UIA の Invoke が 17 ms で返る | BM_CLICK を PostMessage が 0 ms で返る |
| 止まった後の UIA の読み取り | 5 秒待たされる | 5 秒待たされる |
| BM_CLICK を SendMessage (同期) | — | ハンドラが終わるまで待たされる (約 4 秒。VS で続行するまで) |

- UIA は、ブレークで止まった UI スレッドには、届かない。**きっかけを撃ったら、UI に触らずに終わる**のが、唯一の安全な形。
- ひな形の `UiDialogs.Click` は、すでに、PostMessage (MFC・WinForms のボタン) / DoDefaultAction・Invoke (WPF) を使うので、きっかけの操作は、固まらない。
- 試作は、ウォッチャーの外で動かした。**ウォッチャー経由の通しは、未確認。**

## 4. 検討した案
- **A. 順番に動かす (採用)**: `--break` → `--debug` (起動) → UI テストを「アタッチ」で実行 (きっかけを撃って終了) → ウォッチャーが空き、`--inspect` / `--step`。小〜中。
- B. ウォッチャーを並行にする: UI テストを待たずに、次のフラグを処理する。ループの作り直しで大きく、結果の混線・二重実行の対策が要る。不採用。
- C. UI テストが、操作を再現し、最後にアプリを開いたままにして、あとから VS をアタッチする: 最後の状態だけ見られ、ステップ実行ができない。ウォッチャーがテストの終了を待つ間、アタッチの依頼が通らない可能性。不採用。

きっかけの操作の用意は、**きっかけ専用の短いテストを、デバッグしたいときに書く** (ユーザーの決定)。既存の UI テストの流用は、きっかけの後の読み取りで、必ず時間切れになるので、しない。

## 5. 全体の流れ (Claude の手順)
```
1. vs_once.sh "$SLN" --break <パス>:<行> --debug --no-wait   # アプリを起動。ブレークを待たずに返す
2. (きっかけ専用のテストを書く)                              # 数行。[TestCategory("DebugTrigger")]
3. uitest_once.sh "$SLN" --attach <プロセス名>               # ビルドなし・強制終了なし。きっかけを撃って終了
4. vs_once.sh "$SLN" --inspect  /  --step over 5 --inspect   # 止まった状態を調べる
```

## 6. 部品ごとの設計
### 6-1. ウォッチャー (`host-tools/`)
- `trigger_uitest.flag` に、`attach=<プロセス名>` を足す (1 回ごとの指定。`ui-settings.ps1` の `ConvertFrom-UiSettingsText` / `Resolve-UiRun` に追加)。プロセス名は、`[A-Za-z0-9_.-]+` だけ。
- `attach=` のとき、**ビルドをしない** (デバッグ中の exe は、ロックされている)。UI テストのプロジェクトに、新しいきっかけのテストが入るので、**UI テストのプロジェクトだけをビルド**する (アプリ本体の exe は、触らない)。
- `attach=` のとき、**`Stop-SolutionProcesses` を、実行の前も後も、呼ばない** (アプリを殺さないため)。
- 環境変数 `UITEST_ATTACH_PROCESS=<プロセス名>` を、テストに渡す。実行後に消す。
- フィルターが指定されていなければ、`TestCategory=DebugTrigger` を使う。**`attach=` でない普通の UI テストの実行は、`DebugTrigger` を除く。**
- ウォッチャーの制限時間は、`attach=` のときは短く (既定 60 秒。`--ui-timeout` で変更可)。
- `HOST_VERSION` を上げる (再配布とウォッチャーの再起動が要る)。

### 6-2. `vs-debug` (`host-tools/lib/vs-ide.ps1`、`vs_once.sh`)
- `--debug` に、**`--no-wait`** を足す。アプリの起動を確かめたら、ブレークを待たずに返す (`$VsBreakWaitSec` を使わない)。結果に、`DEBUG_MODE: run` が出る。
- `--inspect` を単独で使う (ブレークで止まっているとき) は、今のまま。止まっていなければ `INSPECT_SKIP:`。

### 6-3. UI テストのひな形 (`skills/new-solution/scripts/add_ui_tests.py` の `BASE_CS` など。WPF・WinForms・MFC の 3 つ)
- `UiTestBase.StartApp`: 環境変数 `UITEST_ATTACH_PROCESS` があれば、`Application.Launch` の代わりに、**その名前のプロセスに `Application.Attach`** する。
  - プロセスの exe の場所が、**`UITEST_SOLUTION_DIR` の下**のものだけを選ぶ (無関係な同名プロセスに、アタッチしない)。見つからなければ、`AssertFailedException` (分かりやすい文言)。
  - メインウィンドウは、`UiDialogs.GetAppWindow` で取る (今と同じ)。
- `UiTestBase.StopApp`: アタッチモードでは、**閉じない・殺さない**。**スクリーンショットも、撮らない** (止まっていると UIA が固まる)。`Automation.Dispose()` だけ行う。
- **きっかけの後の手順の縛り:** `UiTestBase` に `protected void Trigger(Action fire)` を足す。`fire` を実行し、**その後、`Find` / `FindIn` が呼ばれたら、`AssertFailedException`** (「きっかけの後は、UI に触れない。止まったアプリは、UIA に応答しない」)。文章ではなく、**コードで縛る**。
- アタッチモードでない実行 (通常の UI テスト) では、`Trigger` は、`fire` を実行するだけ (縛りは、働かない)。
- きっかけ専用のテストの例 (ひな形に、コメントで載せる):
  ```csharp
  [TestMethod, TestCategory("DebugTrigger")]
  public void Trigger_ClearButton()
  {
      Find("NameTextBox").AsTextBox().Text = "太郎";
      Trigger(() => UiDialogs.Click(Find("ClearButton")));   // この後は、UI に触らない
  }
  ```

### 6-4. Skill と文書
- `vs-debug/SKILL.md`: 「UI 操作をきっかけにデバッグする」の節 (第 5 節の手順と、きっかけ専用のテストの書き方、できないこと)。
- `build-test-loop/references/ui-tests.md`: `--attach` と `DebugTrigger` の説明。
- `uitest_once.sh`: `--attach <プロセス名>` を追加 (`attach=` を flag に書く。プロセス名の検査。`--visible` が既定。`--separate` とは併用不可)。出力に、`ATTACHED:` / `TRIGGERED:` の行。
- `README.md` / `docs/USAGE.md` / `CHANGELOG.md` / `docs/TEST-PLAN.md` (実機確認の項)。

## 7. 制約
- ウォッチャーは、1 本のループで、フラグを順番に処理する (変えない)。
- アタッチモードの UI テストは、**ユーザーのデスクトップ** (`desktop=visible`)。VS が起動したアプリが、そこにあるため。別のデスクトップでは、見えない。
- マージは、ユーザーが行う。ホスト側を変えるので、`HOST_VERSION` と `VERSION` を上げ、再配布 (`install.sh --host-only` と `--skills-only`)、ウォッチャーの再起動が要る。
- 文だけで縛らず、**手順 (コード・スクリプトの検査) で縛る** (`new-solution` の手順 0 と同じ考え方)。
- テストを先に書く (`tests/*.sh`。ホスト側の疑似ウォッチャーのテストを含む)。

## 8. ビルダーに任せること
- `Resolve-UiRun` の戻り値の形、テストの書き方 (`tests/` の既存の流儀に従う)。
- UI テストのプロジェクトだけをビルドする方法 (`dotnet build <proj>` か、`dotnet test` の既定のビルドか)。
- `attach=` と `filter=` の併用の細部。
- 文言と、エラー文の言葉。

## 9. 私 (Claude) の判断として決めたこと (確認してほしい)
- フラグの名前は `attach=<プロセス名>`、環境変数は `UITEST_ATTACH_PROCESS`、カテゴリは `DebugTrigger`、メソッドは `Trigger`。
- `attach=` は、既定で `desktop=visible` (別のデスクトップは、不可)。
- `attach=` のときの制限時間の既定は 60 秒。
- アタッチ先のプロセスは、`UITEST_SOLUTION_DIR` の下の exe だけ。
- きっかけの後の `Find` を、`AssertFailedException` にする (縛り)。
- **(読み手の確認への答え。いずれも、ビルダーが、この方針で進めてよい)**
  - **後始末で固まらないこと:** アタッチモードの `StopApp` は、**UIA を、一切、呼ばない**。`Automation.Dispose()` も呼ばない (テストのプロセスは、すぐ終わるので、解放は、OS に任せる)。スクリーンショット・ウィンドウの一覧も撮らない。通常の実行にある、UIA を使う後処理 (ウォッチャーのスクリーンショットの一覧など) が、アタッチモードで動かないことを、実装で確かめる。**通しの実機確認 (第 10 節 2) が、これの最終の確認。**
  - **きっかけの操作が、ブレークで固まる場合:** `Trigger` は、`fire` を、別のタスクで実行し、**最大 3 秒待つ**。戻らなければ、「ブレークで止まったと見なして」、戻る (固まっても、テストは、固まらない)。WPF の `UiDialogs.Click` は、すでに、DoDefaultAction を別スレッドで 1 秒待つので、同じ考え方。
  - **`ATTACHED:` / `TRIGGERED:` は、テストが `ui-trace.txt` に書く** (`UiTrace.Write`)。`uitest_once.sh` が、既存の操作の記録の行の読み取りと同じに、それを拾って出す。
  - **起動の待ち:** `--no-wait` は、アプリのプロセスが、実行中 (`run`) になったら返る。**アタッチ側が、プロセスと、メインウィンドウを、最大 15 秒、探し直す** (`UiDialogs.GetAppWindow` と同じ長さ)。
  - **同名のプロセスが 2 つ以上:** 選ばず、**失敗** (PID の一覧を出す)。
  - **UI テストのプロジェクトは、アプリを `ProjectReference` していない** (PS5.UITests の `csproj`・`add_ui_tests.py` で確認済み。exe は、`AppLocator` が、外から探す)。だから、UI テストのプロジェクトだけのビルドで、アプリの exe は、触られない。
  - **古いひな形で作られた既存のソリューション:** 移行はしない。`attach=` で実行したのに、`ui-trace.txt` に `ATTACHED:` の行がなければ、`uitest_once.sh` が **`ATTACH_UNSUPPORTED:`** (「`add_ui_tests.py` の新しい版で、`UiTestBase.cs` を更新する」) を出して失敗にする (アプリが 2 つ起動してしまった場合も、これで気づく)。
  - **制限時間を超えたとき:** ウォッチャーは、今のとおり、テストのプロセス (testhost) の木だけを `taskkill /T /F` する (`tests.ps1`)。デバッグ中のアプリは、その子ではないので、殺されない。`Stop-SolutionProcesses` は、タイムアウトの経路でも、アタッチモードでは、呼ばない。
  - **実機確認の範囲:** 自動テスト (`tests/*.sh`) では 3 つのひな形のすべてを確かめ、実機では WPF と MFC を確認する (WinForms は、ひな形のコードの確認まで。希望があれば、実機も)。

## 10. 実機での確認 (完了の条件)
1. WPF (`PS5`)・MFC (`MfcScope` の `UiLayerHost`)・WinForms のどれかで、第 5 節の 4 手順が、通しで動く。
2. 手順 3 の後、**`--inspect` が、すぐ通り、止まった場所とローカル変数が出る** (ウォッチャーが空いている)。
3. **アプリが、手順 3 の後も、生きている** (殺されていない)。
4. きっかけの後に `Find` を呼ぶテストは、すぐ、分かりやすい文言で失敗する。
5. 普通の UI テストの実行 (`attach=` なし) が、今までと同じに動き、`DebugTrigger` を実行しない。
