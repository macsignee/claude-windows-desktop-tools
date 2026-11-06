#!/usr/bin/env bash
# test_guard_test.sh - test_guard.py を、疑似ソリューションで検証する (Windows も .NET も git も不要)。
#
# 基準を作ったあと、変更なし・無関係な変更・コメントだけの変更・文字コードと改行の変更では、指摘が出ないこと (誤検出がないこと) と、
# 禁止事項 (テストの削除、Ignore / DISABLED_ / Inconclusive / GTEST_SKIP、アサーションの削除・弱め、許容誤差・待ち時間の拡大など) を 1 つずつ入れたときに、
# 狙いのコードが出ることを確認する。
# Usage: tests/test_guard_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/build-test-loop/scripts/test_guard.py"
T="${TMPDIR:-/tmp}/tg_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
hasnt() { grep -qF -- "$2" <<<"$1" && echo 0 || echo 1; }
cnt() { grep -cF -- "$2" <<<"$1"; }

# ---------------------------------------------------------------- 基準のソリューション
make_base() {   # $1=フォルダ
    local D="$1"
    mkdir -p "$D/MyApp" "$D/MyAppTest" "$D/MyApp.Tests" "$D/MyApp.UITests"
    cat > "$D/MyApp/Calc.cs" <<'EOF'
namespace MyApp { public class Calc { public int Add(int a, int b) { return a + b; } } }
EOF
    cat > "$D/MyAppTest/TestGeometry.cpp" <<'EOF'
#include <gtest/gtest.h>
// EXPECT_EQ(0, 1) は、コメントなので、数えない。 [Ignore] DISABLED_Foo
TEST(Geometry, Add) {
    EXPECT_EQ(Add(1, 2), 3);
    EXPECT_NEAR(Len(1, 1), 1.414, 0.001);
}
TEST(Geometry, Sub) {
    EXPECT_EQ(Sub(3, 1), 2);
    ASSERT_TRUE(Ok());
}
class Fix : public ::testing::Test { protected: void SetUp() override { x = 1; } int x; };
TEST_F(Fix, Throws) {
    EXPECT_THROW(f(), std::runtime_error);
    EXPECT_EQ(x, 1);
}
EOF
    cat > "$D/MyApp.Tests/CalcTests.cs" <<'EOF'
using Microsoft.VisualStudio.TestTools.UnitTesting;
namespace MyApp.Tests
{
    [TestClass]
    public class CalcTests
    {
        private Calc _c;
        [TestInitialize] public void Init() { _c = new Calc(); }

        [TestMethod]
        public void Add_TwoNumbers_ReturnsSum()
        {
            Assert.AreEqual(3, _c.Add(1, 2));
            Assert.AreEqual(0.5, _c.Half(1), 0.01);
        }

        [TestMethod]
        [Timeout(5000)]
        public void Div_ByZero_Throws()
        {
            Assert.ThrowsException<DivideByZeroException>(() => _c.Div(1, 0));
            Assert.AreEqual(1, _c.One());
        }

        [TestMethod]
        public void Brace_InString_Works()
        {
            Assert.AreEqual("}{", _c.Brace);   // 文字列の中の波括弧
        }

        [TestMethod]
        public void Name_Set_Shown()
        {
            Assert.AreEqual("A", _c.Name);
            Assert.IsNotNull(_c);
        }
    }
}
EOF
    cat > "$D/MyApp.Tests/MyApp.Tests.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageReference Include="MSTest" Version="3.6.0" /></ItemGroup>
</Project>
EOF
    cat > "$D/MyApp.UITests/LoginUiTests.cs" <<'EOF'
using Microsoft.VisualStudio.TestTools.UnitTesting;
namespace MyApp.UITests
{
    [TestClass]
    public class LoginUiTests : UiTestBase
    {
        [TestMethod]
        public void Login_Valid_ShowsGreeting()
        {
            var w = WaitFor(() => Find("Greeting"), TimeSpan.FromSeconds(5));
            Assert.AreEqual("Hello", w.Name);
        }

        [TestMethod]
        [TestCategory("Preview")]
        public void Preview_Login() { Snap("login"); HoldForViewing("login"); }
    }
}
EOF
    echo "// 支援ファイル" > "$D/MyApp.UITests/UiDialogs.cs"
    cat > "$D/MyApp.Tests/Run.runsettings" <<'EOF'
<RunSettings><RunConfiguration><MaxCpuCount>1</MaxCpuCount></RunConfiguration></RunSettings>
EOF
}

# ---------------------------------------------------------------- 道具
BASE="$T/base"; make_base "$BASE"
n=0
fresh() {   # 基準を、コピーして、snapshot する。$D を設定する
    n=$((n+1)); D="$T/case$n"; cp -r "$BASE" "$D"
    python3 -I "$S" snapshot "$D" >/dev/null
}
rep() {     # rep <相対パス> <旧> <新> : 必ず 1 か所だけ置換する
    python3 - "$D/$1" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, "rb").read().decode("utf-8")
assert s.count(a) == 1, "置換の対象が 1 か所でない: %r (%d)" % (a, s.count(a))
open(p, "wb").write(s.replace(a, b).encode("utf-8"))
PY
}
run() { out=$(python3 -I "$S" check "$D" --all 2>&1); rc=$?; }
expect() {  # expect <名前> <コード> <rc>
    ok "$1: $2 が出る" "$(has "$out" "$2")"
    ok "$1: rc=$3" "$([ "$rc" = "$3" ] && echo 1 || echo 0)"
}

CS=MyApp.Tests/CalcTests.cs
CPP=MyAppTest/TestGeometry.cpp
UI=MyApp.UITests/LoginUiTests.cs

# ---------------------------------------------------------------- 誤検出がないこと
fresh; run
ok "変更なし: rc=0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "変更なし: TMG が出ない" "$(hasnt "$out" "TMG")"
ok "基準に、支援ファイル (UiDialogs.cs) と、アプリのソースを入れない" "$(python3 -I - "$D/.claude-logs/test_guard_base/manifest.json" <<'PY'
import json, sys
f = json.load(open(sys.argv[1]))["files"]
print(1 if len(f) == 5 and not any("UiDialogs" in k or k.startswith("MyApp/") for k in f) else 0)
PY
)"

fresh; echo "// 変更" >> "$D/MyApp/Calc.cs"; run
ok "アプリのソースの変更: 指摘なし (rc=0)" "$([ "$rc" = 0 ] && [ "$(has "$out" TMG)" = 0 ] && echo 1 || echo 0)"

fresh; echo "// 変更" >> "$D/MyApp.UITests/UiDialogs.cs"; run
ok "支援ファイルの変更: 指摘なし" "$(hasnt "$out" "TMG")"

fresh; rep "$CS" "Assert.IsNotNull(_c);" "Assert.IsNotNull(_c); // Assert.AreEqual(0, 1); [Ignore] Assert.Inconclusive();"; run
ok "コメントだけの追加: 指摘なし" "$([ "$rc" = 0 ] && [ "$(hasnt "$out" TMG)" = 1 ] && echo 1 || echo 0)"
ok "コメントだけの追加でも、変更されたファイルには出る" "$(has "$out" "M MyApp.Tests/CalcTests.cs")"

fresh; python3 - "$D/$CS" <<'PY'
import sys
p = sys.argv[1]
s = open(p, "rb").read().decode("utf-8").replace("\n", "\r\n")
open(p, "wb").write(b"\xef\xbb\xbf" + s.encode("utf-8"))
PY
run
ok "BOM + CRLF への変更だけ: 指摘なし" "$([ "$rc" = 0 ] && [ "$(hasnt "$out" TMG)" = 1 ] && echo 1 || echo 0)"

fresh; cat >> "$D/$CS" <<'EOF'
// 新しいテスト
EOF
rep "$CS" "        [TestMethod]
        public void Name_Set_Shown()" "        [TestMethod]
        public void Brand_New_Test() { Assert.IsTrue(_c.Ok); }

        [TestMethod]
        public void Name_Set_Shown()"; run
ok "テストの追加: rc=0 で、TMG090 (追加 1 件)" "$([ "$rc" = 0 ] && [ "$(has "$out" "TMG090")" = 1 ] && [ "$(has "$out" "追加されたテスト 1 件")" = 1 ] && echo 1 || echo 0)"
ok "テストの追加: error / warning なし" "$(grep -qE '^TMG[0-9]+ error' <<<"$out" && echo 0 || echo 1)"

# ---------------------------------------------------------------- TMG001 テストの削除
fresh; rep "$CPP" "TEST(Geometry, Sub) {
    EXPECT_EQ(Sub(3, 1), 2);
    ASSERT_TRUE(Ok());
}" ""; run
expect "C++ のテストの削除" "TMG001" 1
ok "C++ のテストの削除: 消えたテスト名 (Geometry.Sub)" "$(has "$out" "Geometry.Sub")"

fresh; rm "$D/$CS"; run
expect "C# のファイルごとの削除" "TMG001" 1
ok "ファイルごとの削除: 4 件 (4 つのテスト) すべてを報告" "$([ "$(cnt "$out" "TMG001")" = 4 ] && echo 1 || echo 0)"
ok "ファイルごとの削除: 'D' で、変更されたファイルに出る" "$(has "$out" "D MyApp.Tests/CalcTests.cs")"

fresh; rep "$CS" "        [TestMethod]
        public void Name_Set_Shown()" "        public void Name_Set_Shown()"; run
expect "[TestMethod] を外した" "TMG001" 1
ok "[TestMethod] を外した: 1 件だけ (文字列の中の波括弧で、ずれない)" "$([ "$(cnt "$out" "TMG001")" = 1 ] && [ "$(has "$out" "CalcTests.Name_Set_Shown")" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- TMG002 無効化
fresh; rep "$CS" "        [TestMethod]
        public void Name_Set_Shown()" "        [TestMethod]
        [Ignore]
        public void Name_Set_Shown()"; run
expect "[Ignore]" "TMG002" 1

fresh; rep "$CS" "Assert.AreEqual(\"A\", _c.Name);" "Assert.Inconclusive(); Assert.AreEqual(\"A\", _c.Name);"; run
expect "Assert.Inconclusive" "TMG002" 1

fresh; rep "$CPP" "TEST(Geometry, Sub) {" "TEST(Geometry, DISABLED_Sub) {"; run
expect "DISABLED_ への名前の変更" "TMG002" 1
ok "DISABLED_: 'テストが消えた' とは言わない (TMG001 なし)" "$(hasnt "$out" "TMG001")"

fresh; rep "$CPP" "    ASSERT_TRUE(Ok());" "    GTEST_SKIP() << \"後で\";"; run
expect "GTEST_SKIP" "TMG002" 1

fresh; rep "$CS" "        public void Add_TwoNumbers_ReturnsSum()" "        [TestCategory(\"Slow\")]
        public void Add_TwoNumbers_ReturnsSum()"; run
expect "既存のテストへの [TestCategory]" "TMG002" 1

fresh; rep "$UI" "        public void Login_Valid_ShowsGreeting()" "        [TestCategory(\"Preview\")]
        public void Login_Valid_ShowsGreeting()"; run
expect "UI テストを Preview に移して、回帰から外す" "TMG002" 1

# ---------------------------------------------------------------- TMG003 / TMG004 アサーションの削除
fresh; rep "$CPP" "    EXPECT_EQ(Sub(3, 1), 2);
    ASSERT_TRUE(Ok());" ""; run
expect "アサーションがゼロ" "TMG003" 1

fresh; rep "$CPP" "    ASSERT_TRUE(Ok());" ""; run
expect "アサーションが減った" "TMG004" 0

fresh; rep "$UI" "            Assert.AreEqual(\"Hello\", w.Name);" ""; run
expect "UI テストのアサーションがゼロ" "TMG003" 1
ok "Preview テスト (アサーションなし) は、もとからゼロで、指摘しない" "$(hasnt "$out" "Preview_Login")"

# ---------------------------------------------------------------- TMG005 弱め
fresh; rep "$CS" "Assert.AreEqual(\"A\", _c.Name);" "Assert.AreNotEqual(\"B\", _c.Name);"; run
expect "AreEqual → AreNotEqual" "TMG005" 1

fresh; rep "$CPP" "EXPECT_EQ(Sub(3, 1), 2);" "EXPECT_NE(Sub(3, 1), 2);"; run
expect "EXPECT_EQ → EXPECT_NE" "TMG005" 1

fresh; rep "$CPP" "EXPECT_EQ(Add(1, 2), 3);" "EXPECT_TRUE(true);"; run
expect "常に成功する条件 (EXPECT_TRUE(true))" "TMG005" 1

fresh; rep "$CS" "Assert.AreEqual(1, _c.One());" "Assert.IsTrue(true); Assert.IsTrue(_c.Ok);"; run
expect "Assert.IsTrue(true)" "TMG005" 1

# ---------------------------------------------------------------- TMG006 許容誤差
fresh; rep "$CPP" "1.414, 0.001" "1.414, 0.5"; run
expect "EXPECT_NEAR の許容誤差を広げた" "TMG006" 0

fresh; rep "$CS" "_c.Half(1), 0.01" "_c.Half(1), 1"; run
expect "Assert.AreEqual の delta を広げた" "TMG006" 0

fresh; rep "$CS" "_c.Half(1), 0.01" "_c.Half(1), 0.001"; run
ok "許容誤差を、狭めた: 指摘なし" "$(hasnt "$out" "TMG006")"

# ---------------------------------------------------------------- TMG007 待ち
fresh; rep "$CS" "[Timeout(5000)]" "[Timeout(600000)]"; run
expect "[Timeout] の延長" "TMG007" 0

fresh; rep "$CS" "        [Timeout(5000)]
" ""; run
expect "[Timeout] の削除" "TMG007" 0

fresh; rep "$CS" "Assert.AreEqual(\"A\", _c.Name);" "System.Threading.Thread.Sleep(3000); Assert.AreEqual(\"A\", _c.Name);"; run
expect "Thread.Sleep の追加" "TMG007" 0

fresh; rep "$UI" "TimeSpan.FromSeconds(5)" "TimeSpan.FromSeconds(120)"; run
expect "WaitFor の待ち時間の延長" "TMG007" 0

# ---------------------------------------------------------------- TMG008 握りつぶし / 例外の期待の削除
fresh; rep "$CS" "Assert.AreEqual(\"A\", _c.Name);" "try { Assert.AreEqual(\"A\", _c.Name); } catch (System.Exception) { }"; run
expect "try/catch の追加" "TMG008" 0

fresh; rep "$CS" "Assert.ThrowsException<DivideByZeroException>(() => _c.Div(1, 0));" ""; run
expect "ThrowsException の削除" "TMG008" 0

fresh; rep "$CPP" "    EXPECT_THROW(f(), std::runtime_error);
" ""; run
expect "EXPECT_THROW の削除" "TMG008" 0

# ---------------------------------------------------------------- TMG009 プロジェクト・設定
fresh; rep "MyApp.Tests/MyApp.Tests.csproj" "<ItemGroup><PackageReference" "<ItemGroup><Compile Remove=\"CalcTests.cs\" /><PackageReference"; run
expect "Compile Remove" "TMG009" 1

fresh; rep "MyApp.Tests/Run.runsettings" "<MaxCpuCount>1</MaxCpuCount>" "<MaxCpuCount>1</MaxCpuCount><TestCaseFilter>Name~X</TestCaseFilter>"; run
expect ".runsettings の TestCaseFilter" "TMG009" 1

fresh; rep "MyApp.Tests/MyApp.Tests.csproj" "3.6.0" "3.7.0"; run
expect "パッケージの版の変更 (review)" "TMG011" 0
ok "パッケージの版の変更: error なし" "$(grep -qE '^TMG[0-9]+ error' <<<"$out" && echo 0 || echo 1)"

# ---------------------------------------------------------------- TMG010 / TMG011 review
fresh; rep "$CS" "Assert.AreEqual(3, _c.Add(1, 2));" "Assert.AreEqual(4, _c.Add(1, 2));"; run
expect "期待値の書き換え (review)" "TMG010" 0
ok "期待値の書き換え: 変更前後の行を並べる" "$([ "$(has "$out" "- Assert.AreEqual(3, _c.Add(1, 2));")" = 1 ] && [ "$(has "$out" "+ Assert.AreEqual(4, _c.Add(1, 2));")" = 1 ] && echo 1 || echo 0)"

fresh; rep "$CS" "_c = new Calc();" "_c = new Calc { Fake = true };"; run
expect "[TestInitialize] の変更 (review)" "TMG011" 0

fresh; rep "$CPP" "void SetUp() override { x = 1; }" "void SetUp() override { x = 2; }"; run
expect "SetUp の変更 (review)" "TMG011" 0

# ---------------------------------------------------------------- 基準の更新 (承認)・終了コード・出力
fresh; rep "$CS" "Assert.AreEqual(\"A\", _c.Name);" "Assert.AreNotEqual(\"B\", _c.Name);"; run
ok "(前提) 弱めた → error" "$([ "$rc" = 1 ] && echo 1 || echo 0)"
python3 -I "$S" snapshot "$D" >/dev/null; run
ok "承認 → snapshot のやり直し → 指摘なし" "$([ "$rc" = 0 ] && [ "$(hasnt "$out" TMG)" = 1 ] && echo 1 || echo 0)"

fresh; rep "$CS" "Assert.AreEqual(\"A\", _c.Name);" "Assert.AreNotEqual(\"B\", _c.Name);"
python3 -I "$S" check "$D" --json "$T/out.json" >/dev/null
ok "--json: 指摘が、JSON で書かれる" "$(python3 -I - "$T/out.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
print(1 if any(f["code"] == "TMG005" for f in j["findings"]) and j["changed"] else 0)
PY
)"

fresh; rep "$CS" "Assert.AreEqual(\"A\", _c.Name);" "Assert.AreNotEqual(\"B\", _c.Name);"
out=$(python3 -I "$S" check "$D" --max-lines 3);
ok "--max-lines: 省略の行が出る" "$(has "$out" "行を省略")"

fresh; rep "$CS" "Assert.AreEqual(\"A\", _c.Name);" "Assert.AreNotEqual(\"B\", _c.Name);"; run
ok "出力の先頭は、要約の 1 行" "$(head -n1 <<<"$out" | grep -qE '^test_guard: error [0-9]+ / warning [0-9]+ / review [0-9]+' && echo 1 || echo 0)"
ok "error があると、取るべき行動を出す" "$(has "$out" "snapshot をやり直す")"

E="$T/empty"; mkdir -p "$E"
out=$(python3 -I "$S" check "$E" 2>&1); rc=$?
ok "基準がない: rc=3" "$([ "$rc" = 3 ] && [ "$(has "$out" "snapshot")" = 1 ] && echo 1 || echo 0)"
out=$(python3 -I "$S" snapshot "$E" 2>&1); rc=$?
ok "テストファイルがない: snapshot は rc=3" "$([ "$rc" = 3 ] && echo 1 || echo 0)"
out=$(python3 -I "$S" check "$T/no_such_dir" 2>&1); rc=$?
ok "フォルダがない: rc=2" "$([ "$rc" = 2 ] && echo 1 || echo 0)"
python3 -I "$S" bogus "$E" >/dev/null 2>&1; rc=$?
ok "不正なモード: rc=2" "$([ "$rc" = 2 ] && echo 1 || echo 0)"

# 検査は、読み取りだけ: check は、テストファイルを変えない
fresh; h1=$(cat "$D/$CS" "$D/$CPP" | sha1sum); python3 -I "$S" check "$D" >/dev/null; h2=$(cat "$D/$CS" "$D/$CPP" | sha1sum)
ok "check は、テストファイルを変えない" "$([ "$h1" = "$h2" ] && echo 1 || echo 0)"

# --- 段階 2 (v2.24.5): test_guard_note.sh が、`TEST_GUARD:` の行を出す。終了コードは、常に 0
N="$ROOT/skills/build-test-loop/scripts/test_guard_note.sh"
fresh; rm -rf "$D/.claude-logs/test_guard_base"   # 基準なし → 何も出さない (snapshot を促さない)
out=$(bash "$N" "$D"); rc=$?
ok "note: 基準がない → 何も出さない (rc 0)" "$([ -z "$out" ] && [ "$rc" = 0 ] && echo 1 || echo 0)"
python3 -I "$S" snapshot "$D" >/dev/null
out=$(bash "$N" "$D"); rc=$?
ok "note: 無変更 → TEST_GUARD: OK (rc 0)" "$([ "$(has "$out" 'TEST_GUARD: OK (error 0 / warning 0 / review 0)')" = 1 ] && [ "$rc" = 0 ] && echo 1 || echo 0)"
sed -i 's/EXPECT_EQ(Add(1, 2), 3)/EXPECT_NE(Add(1, 2), 3)/' "$D/$CPP"
out=$(bash "$N" "$D"); rc=$?
ok "note: アサーションを弱めた → TEST_GUARD: ERROR + TMG005 の行 (rc 0)" "$([ "$(has "$out" 'TEST_GUARD: ERROR')" = 1 ] && [ "$(has "$out" 'TMG005')" = 1 ] && [ "$(has "$out" '元に戻すか、止まって確認')" = 1 ] && [ "$rc" = 0 ] && echo 1 || echo 0)"
ok "note: 最初の行が TEST_GUARD: で始まる" "$([ "$(head -n 1 <<<"$out" | cut -c1-12)" = 'TEST_GUARD: ' ] && echo 1 || echo 0)"
fresh; python3 -I "$S" snapshot "$D" >/dev/null
sed -i 's/Thread.Sleep(10)/Thread.Sleep(20)/' "$D/$CS" 2>/dev/null
out=$(bash "$N" "$D")
ok "note: error がなければ、ERROR を出さない" "$([ "$(has "$out" 'TEST_GUARD: ERROR')" = 0 ] && echo 1 || echo 0)"
out=$(bash "$N" "$T/no_such_dir"); rc=$?
ok "note: フォルダがない → 何も出さない (rc 0)" "$([ -z "$out" ] && [ "$rc" = 0 ] && echo 1 || echo 0)"
BT="$ROOT/skills/build-test-loop/scripts/build_test_once.sh"; UT="$ROOT/skills/build-test-loop/scripts/uitest_once.sh"
ok "build_test_once.sh は、終了時に note を呼ぶ (UI テストの流れでは呼ばない)。uitest_once.sh は、末尾と早期終了で呼ぶ" "$(grep -q 'test_guard_note.sh' "$BT" && grep -q 'BUILD_TEST_FLAG:-' "$BT" && [ "$(grep -c 'test_guard_note.sh' "$UT")" -ge 2 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- audit: テストの中身が空洞でないか (v2.57.0)
D="$T/AuditOk"; make_base "$D"
out="$(python3 "$S" audit "$D" 2>&1)"; rc=$?
ok "audit: 基準のソリューション (健全なテスト) は、error 0 (rc=0)。誤検出がない" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0')" = 1 ] && echo 1 || echo 0)"
ok "audit: [TestCategory(\"Preview\")] の目視確認のテスト (アサーションなし) は、対象外 (指摘しない)" "$(hasnt "$out" "Preview_Login")"
ok "audit: 点検したテストの件数を出す (--all で TQ090)" "$(python3 "$S" audit "$D" --all 2>&1 | grep -q 'TQ090' && echo 1 || echo 0)"
D="$T/AuditBad"; mkdir -p "$D/MyAppTest" "$D/MyApp.Tests"
cat > "$D/MyAppTest/TestA.cpp" <<'EOF'
#include <gtest/gtest.h>
TEST(A, Good) { EXPECT_EQ(Add(1, 2), 3); }
TEST(A, None) { Add(1, 2); }
TEST(A, Trivial) { EXPECT_TRUE(true); }
TEST(A, Weak) { EXPECT_NE(Make(), nullptr); }
TEST(A, Calc) { EXPECT_EQ(Total(a), Total(a)); }
TEST(A, Helper) { VerifyOrder(x); }
TEST(A, Throws) { EXPECT_THROW(f(), std::runtime_error); }
EOF
cat > "$D/MyApp.Tests/CalcTests.cs" <<'EOF'
[TestClass] public class CalcTests {
 [TestMethod] public void Good() { Assert.AreEqual(3, new Calc().Add(1, 2)); }
 [TestMethod] public void None() { var c = new Calc(); c.Add(1, 2); }
 [TestMethod] public void Both() { Assert.AreEqual(Sut.Compute(x), Other.Compute(x)); }
 [TestMethod] [ExpectedException(typeof(System.Exception))] public void Exc() { Boom(); }
}
EOF
out="$(python3 "$S" audit "$D" --all 2>&1)"; rc=$?
ok "audit: rc=1 (error あり)。点検したテスト 11 件" "$([ $rc = 1 ] && [ "$(has "$out" '点検したテスト 11 件')" = 1 ] && echo 1 || echo 0)"
ok "audit: TQ001 (アサーションなし) を、C++ と C# の両方で検出。件数 2" "$([ "$(cnt "$out" 'TQ001 error')" = 2 ] && [ "$(has "$out" 'A.None')" = 1 ] && [ "$(has "$out" 'CalcTests.None')" = 1 ] && echo 1 || echo 0)"
ok "audit: TQ002 (EXPECT_TRUE(true))、TQ003 (EXPECT_NE だけ)" "$([ "$(has "$out" 'TQ002 error   MyAppTest/TestA.cpp::A.Trivial')" = 1 ] && [ "$(has "$out" 'TQ003 warning MyAppTest/TestA.cpp::A.Weak')" = 1 ] && echo 1 || echo 0)"
ok "audit: TQ004 (期待値も実測値も呼び出し。C++ と C# の 2 件)、TQ011 (ヘルパーだけ)" "$([ "$(cnt "$out" 'TQ004 review')" = 2 ] && [ "$(has "$out" 'TQ011 review  MyAppTest/TestA.cpp::A.Helper')" = 1 ] && echo 1 || echo 0)"
ok "audit: 健全なテスト (Good)、例外を期待するテスト (Throws、ExpectedException の Exc) は、指摘しない" "$([ "$(has "$out" 'A.Good')" = 0 ] && [ "$(has "$out" 'CalcTests.Good')" = 0 ] && [ "$(has "$out" 'A.Throws')" = 0 ] && [ "$(has "$out" 'CalcTests.Exc')" = 0 ] && echo 1 || echo 0)"
python3 "$S" audit "$D" --json "$T/audit.json" >/dev/null 2>&1
ok "audit: --json に、テスト件数と指摘を書く" "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(1 if d['tests']==11 and len(d['findings'])>=7 else 0)" "$T/audit.json")"
mkdir -p "$T/AuditNone"; python3 "$S" audit "$T/AuditNone" >/dev/null 2>&1; r3=$?
python3 "$S" audit "$T/nonexistent" >/dev/null 2>&1; r2=$?
ok "audit: テストがない = rc=3、フォルダがない = rc=2" "$([ $r3 = 3 ] && [ $r2 = 2 ] && echo 1 || echo 0)"
before="$(find "$D" -type f | sort | xargs md5sum | md5sum)"; python3 "$S" audit "$D" >/dev/null 2>&1
ok "audit: 何も書かない (基準のコピーも作らない。.claude-logs もない)" "$([ "$(find "$D" -type f | sort | xargs md5sum | md5sum)" = "$before" ] && [ ! -e "$D/.claude-logs" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- audit と変異の確認の手順 (v2.57.0): 文書の整合
MC="$ROOT/skills/build-test-loop/references/mutation-check.md"
ok "mutation-check.md がある。形の検査 (audit) と変異の確認の 2 段階、必ず元に戻す、ユーザーの了承、上限 3 件、生き残ったときの扱い、実施しないときの明記" "$(r=1; for k in 'test_guard.py audit' '変異の確認' '必ず、元に戻す' 'ユーザーに、実装を、一時的に壊すことを、伝えて、了承を得る' '最大 3 件' '生き残った' '変異の確認は、していない' 'cmp '; do grep -qF -- "$k" "$MC" || r=0; done; echo $r)"
ok "build-test-loop / cpp-test-first / csharp-test-first の SKILL.md が、audit と mutation-check.md へ案内している" "$(r=1; for f in "$ROOT/skills/build-test-loop/SKILL.md" "$ROOT/skills/cpp-test-first/SKILL.md" "$ROOT/skills/csharp-test-first/SKILL.md"; do grep -q 'test_guard.py audit' "$f" && grep -q 'references/mutation-check.md' "$f" || r=0; done; echo $r)"
ok "test_guard.py の説明 (先頭) に audit の使い方と TQ001〜TQ011 がある" "$(r=1; for k in 'test_guard.py audit' 'TQ001' 'TQ002' 'TQ003' 'TQ004' 'TQ011'; do head -n 50 "$S" | grep -qF -- "$k" || r=0; done; echo $r)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
