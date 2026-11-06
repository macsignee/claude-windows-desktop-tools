#!/usr/bin/env bash
# wpf_check_test.sh - wpf_check.py を、疑似プロジェクトで検証する (Windows も .NET も不要)。
#
# 正常なプロジェクト (CommunityToolkit.Mvvm の ViewModel、DataTemplate、外部の辞書、結合した辞書、d:DataContext など) で、
# 指摘が 1 件も出ないこと (誤検出がないこと) と、そこに 1 か所ずつ不具合を入れたときに、狙いのコードが出ることを確認する。
# Usage: tests/wpf_check_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/wpf-check/scripts/wpf_check.py"
T="${TMPDIR:-/tmp}/wpfc_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }

# ---------------------------------------------------------------- 正常なプロジェクト
make_clean() {   # $1=フォルダ
    local D="$1"
    mkdir -p "$D/WpfApp/Themes" "$D/MyApp.ViewModels" "$D/MyApp.Logic"
    cat > "$D/WpfApp/WpfApp.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\MyApp.ViewModels\MyApp.ViewModels.csproj" />
  </ItemGroup>
</Project>
EOF
    cat > "$D/MyApp.ViewModels/MyApp.ViewModels.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><ProjectReference Include="..\MyApp.Logic\MyApp.Logic.csproj" /></ItemGroup></Project>
EOF
    cat > "$D/MyApp.Logic/MyApp.Logic.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>
EOF
    cat > "$D/MyApp.Logic/OrderService.cs" <<'EOF'
namespace MyApp.Logic;

public class OrderService
{
    public decimal Total(decimal price, int qty) => price * qty;
}
EOF
    cat > "$D/MyApp.ViewModels/MainViewModel.cs" <<'EOF'
using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MyApp.Logic;

namespace MyApp.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly OrderService _service = new();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(TotalText))]
    private int _quantity = 1;

    [ObservableProperty]
    private string name = "";

    [ObservableProperty]
    private bool _isBusy;

    public ObservableCollection<ItemViewModel> Items { get; } = new();

    public ItemViewModel? Selected { get; set; }

    public string TotalText => $"{_service.Total(100m, Quantity)}";

    [RelayCommand]
    private void Save()
    {
        // "}" in a comment and a string {
        Name = "}{";
    }

    [RelayCommand]
    private async Task LoadAsync()
    {
        await Task.Delay(1);
    }
}

public class ItemViewModel : ObservableObject
{
    private string _title = "";
    public string Title { get => _title; set => SetProperty(ref _title, value); }
    public decimal Price { get; init; }
}
EOF
    cat > "$D/WpfApp/App.xaml" <<'EOF'
<Application x:Class="WpfApp.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             StartupUri="MainWindow.xaml">
    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="Themes/Colors.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MaterialDesignThemes.Wpf;component/Themes/Foo.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <BooleanToVisibilityConverter x:Key="BoolToVis" />
        </ResourceDictionary>
    </Application.Resources>
</Application>
EOF
    cat > "$D/WpfApp/App.xaml.cs" <<'EOF'
using System.Windows;

namespace WpfApp;

public partial class App : Application
{
}
EOF
    cat > "$D/WpfApp/Themes/Colors.xaml" <<'EOF'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <SolidColorBrush x:Key="PrimaryBrush" Color="Blue" />
    <Style x:Key="TitleStyle" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource PrimaryBrush}" />
    </Style>
</ResourceDictionary>
EOF
    cat > "$D/WpfApp/MainWindow.xaml" <<'EOF'
<Window x:Class="WpfApp.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:vm="clr-namespace:MyApp.ViewModels;assembly=MyApp.ViewModels"
        mc:Ignorable="d"
        d:DataContext="{d:DesignInstance Type=vm:MainViewModel, IsDesignTimeCreatable=True}"
        Title="Main">
    <Window.Resources>
        <Style x:Key="Local" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}" />
    </Window.Resources>
    <StackPanel>
        <TextBox Text="{Binding Name, UpdateSourceTrigger=PropertyChanged}" />
        <TextBox Text="{Binding Quantity}" />
        <TextBlock Text="{Binding TotalText}" Style="{StaticResource TitleStyle}" Foreground="{DynamicResource PrimaryBrush}" />
        <TextBlock Text="{Binding TotalText, Mode=OneWay}" Visibility="{Binding IsBusy, Converter={StaticResource BoolToVis}}" />
        <Button Content="Save" Command="{Binding SaveCommand}" Style="{StaticResource Local}" />
        <Button Content="Load" Command="{Binding LoadCommand}" />
        <TextBox Text="{Binding Selected.Title}" />
        <ListBox ItemsSource="{Binding Items}">
            <ListBox.ItemTemplate>
                <DataTemplate DataType="{x:Type vm:ItemViewModel}">
                    <TextBlock Text="{Binding Title}" ToolTip="{Binding Price}" />
                </DataTemplate>
            </ListBox.ItemTemplate>
        </ListBox>
        <ListBox ItemsSource="{Binding Items}">
            <ListBox.ItemTemplate>
                <DataTemplate>
                    <TextBlock Text="{Binding Whatever}" />
                </DataTemplate>
            </ListBox.ItemTemplate>
        </ListBox>
        <TextBlock Text="{Binding ElementName=Foo, Path=Nothing}" />
    </StackPanel>
</Window>
EOF
    cat > "$D/WpfApp/MainWindow.xaml.cs" <<'EOF'
using System.Windows;
using MyApp.ViewModels;

namespace WpfApp;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel();
    }
}
EOF
}

# edit <プロジェクトの根> <ファイル> <古い文字列> <新しい文字列>   (古い文字列が、ちょうど 1 回あること)
edit() {
    python3 - "$1/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, (p, s.count(old), old)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}

# mutate <名前> -> $T/<名前> に、正常なプロジェクトの複製を作る
mutate() { cp -r "$T/clean" "$T/$1"; }
check() { python3 -I "$S" "$@"; }

make_clean "$T/clean"

# ---------------------------------------------------------------- 1. 正常: 指摘なし
out="$(check "$T/clean" --all --json "$T/clean.json")"; rc=$?
ok "clean: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "clean: header says error 0 / warning 0" "$(has "$out" 'wpf-check: error 0 / warning 0')"
ok "clean: no findings under --all except info (BND900 is allowed)" "$([ "$(grep -c '^\[' <<<"$out")" = "$(grep -c ' info    ' <<<"$out")" ] && echo 1 || echo 0)"
ok "clean: 3 projects checked, stats counted" "$(python3 -c "
import json,sys
d=json.load(open('$T/clean.json')); s=d['stats']
sys.exit(0 if s['xaml']==3 and s['bindings']>=10 and s['resources']>=4 else 1)" && echo 1 || echo 0)"

# ---------------------------------------------------------------- 2. バインディング
mutate b1; edit "$T/b1" WpfApp/MainWindow.xaml 'Text="{Binding TotalText}" Style' 'Text="{Binding TotalTxt}" Style'
out="$(check "$T/b1")"; rc=$?
ok "BND001: typo in the path -> error, rc=1" $([ $rc = 1 ] && [ "$(has "$out" 'BND001')" = 1 ] && echo 1 || echo 0)
ok "BND001: suggests the near name (TotalText)" "$(has "$out" 'もしかして: TotalText')"
ok "BND001: location is the XAML line of the binding" "$(has "$out" 'WpfApp/MainWindow.xaml(16)')"

mutate b2; edit "$T/b2" WpfApp/MainWindow.xaml 'Command="{Binding SaveCommand}"' 'Command="{Binding Save}"'
out="$(check "$T/b2")"
ok "BND001: Command bound to a method name -> says it is a method" "$([ "$(has "$out" 'BND001')" = 1 ] && [ "$(has "$out" 'のメソッド')" = 1 ] && echo 1 || echo 0)"

mutate b3; edit "$T/b3" MyApp.ViewModels/MainViewModel.cs 'public ItemViewModel? Selected { get; set; }' 'public ItemViewModel? Selected { get; set; }
    public string Memo = "";'
edit "$T/b3" WpfApp/MainWindow.xaml '<TextBox Text="{Binding Selected.Title}" />' '<TextBox Text="{Binding Memo}" />'
out="$(check "$T/b3")"
ok "BND002: public field -> error" "$([ "$(has "$out" 'BND002')" = 1 ] && [ "$(has "$out" 'public フィールド')" = 1 ] && echo 1 || echo 0)"

mutate b4; edit "$T/b4" WpfApp/MainWindow.xaml 'Text="{Binding TotalText, Mode=OneWay}"' 'Text="{Binding TotalText, Mode=TwoWay}"'
out="$(check "$T/b4")"; rc=$?
ok "BND003: explicit TwoWay to a read-only property -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'BND003')" = 1 ] && [ "$(has "$out" 'error   BND003')" = 1 ] && echo 1 || echo 0)"

mutate b5; edit "$T/b5" WpfApp/MainWindow.xaml '<TextBlock Text="{Binding TotalText}" Style' '<TextBox Text="{Binding TotalText}" Style'
out="$(check "$T/b5")"; rc=$?
ok "BND003: TextBox.Text (default TwoWay) to a read-only property -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   BND003')" = 1 ] && echo 1 || echo 0)"

mutate b6; edit "$T/b6" MyApp.ViewModels/MainViewModel.cs 'public class ItemViewModel : ObservableObject' 'public class ItemViewModel'
edit "$T/b6" MyApp.ViewModels/MainViewModel.cs 'public string Title { get => _title; set => SetProperty(ref _title, value); }' 'public string Title { get => _title; set { _title = value; } }'
out="$(check "$T/b6")"
ok "BND004: ViewModel without INotifyPropertyChanged -> warning" "$([ "$(has "$out" 'warning BND004')" = 1 ] && [ "$(has "$out" 'ItemViewModel が INotifyPropertyChanged を実装していない')" = 1 ] && echo 1 || echo 0)"

mutate b7; edit "$T/b7" WpfApp/MainWindow.xaml 'Command="{Binding LoadCommand}"' 'Command="{Binding Quantity}"'
out="$(check "$T/b7")"
ok "CMD001: Command bound to an int -> warning" "$([ "$(has "$out" 'warning CMD001')" = 1 ] && echo 1 || echo 0)"

mutate b8; edit "$T/b8" MyApp.ViewModels/MainViewModel.cs 'public partial class MainViewModel : ObservableObject' 'public partial class MainViewModel : SomeExternalBase'
edit "$T/b8" WpfApp/MainWindow.xaml 'Text="{Binding TotalText}" Style' 'Text="{Binding Nothing}" Style'
out="$(check "$T/b8" --all)"; rc=$?
ok "unknown external base: no BND001 (cannot know), BND900 (info) says so" "$([ $rc = 0 ] && [ "$(has "$out" 'BND001')" = 0 ] && [ "$(has "$out" 'BND900')" = 1 ] && [ "$(has "$out" 'SomeExternalBase')" = 1 ] && echo 1 || echo 0)"

mutate b9; edit "$T/b9" WpfApp/MainWindow.xaml 'Text="{Binding TotalText}" Style' 'Text="{Binding TotalTxt}" Style'
edit "$T/b9" WpfApp/MainWindow.xaml.cs '        DataContext = new MainViewModel();
' ''
out="$(check "$T/b9")"; rc=$?
ok "design-time only DataContext (d:DataContext): a wrong path is a warning, not an error" "$([ $rc = 0 ] && [ "$(has "$out" 'warning BND001')" = 1 ] && echo 1 || echo 0)"

mutate b10; edit "$T/b10" WpfApp/MainWindow.xaml.cs 'DataContext = new MainViewModel();' 'DataContext = this;'
edit "$T/b10" WpfApp/MainWindow.xaml 'Text="{Binding TotalText}" Style' 'Text="{Binding Nothing}" Style'
out="$(check "$T/b10" --all)"; rc=$?
ok "DataContext = this: the code-behind class derives from Window (external base) -> cannot know its members: no error, BND900 (info)" "$([ $rc = 0 ] && [ "$(has "$out" 'BND001')" = 0 ] && [ "$(has "$out" 'BND900')" = 1 ] && [ "$(has "$out" 'MainWindow の基底クラス (Window)')" = 1 ] && echo 1 || echo 0)"

mutate b11; edit "$T/b11" WpfApp/MainWindow.xaml '<DataTemplate>
                    <TextBlock Text="{Binding Whatever}" />' '<DataTemplate DataType="{x:Type vm:ItemViewModel}">
                    <TextBlock Text="{Binding Whatever}" />'
out="$(check "$T/b11")"
ok "DataTemplate with DataType: binding checked against the item type" "$([ "$(has "$out" 'ItemViewModel にプロパティ "Whatever"')" = 1 ] && echo 1 || echo 0)"

mutate b12; edit "$T/b12" MyApp.ViewModels/MainViewModel.cs 'private bool _isBusy;' 'private bool isBusyFlag;'
out="$(check "$T/b12")"
ok "[ObservableProperty] field name -> property name (isBusyFlag -> IsBusyFlag); the old IsBusy is gone -> error" "$([ "$(has "$out" 'MainViewModel にプロパティ "IsBusy"')" = 1 ] && echo 1 || echo 0)"

mutate b13; edit "$T/b13" MyApp.ViewModels/MainViewModel.cs 'private async Task LoadAsync()' 'private async Task Reload()'
out="$(check "$T/b13")"
ok "[RelayCommand] async Task LoadAsync -> LoadCommand; renamed method -> LoadCommand is missing -> error" "$([ "$(has "$out" '"LoadCommand"')" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 3. リソース
mutate r1; edit "$T/r1" WpfApp/MainWindow.xaml 'Style="{StaticResource TitleStyle}"' 'Style="{StaticResource TitleStyl}"'
out="$(check "$T/r1")"; rc=$?
ok "RES001: missing key, but an external dictionary exists -> warning (not certain)" "$([ $rc = 0 ] && [ "$(has "$out" 'warning RES001')" = 1 ] && [ "$(has "$out" '外部の辞書')" = 1 ] && echo 1 || echo 0)"

mutate r2; edit "$T/r2" WpfApp/MainWindow.xaml 'Style="{StaticResource TitleStyle}"' 'Style="{StaticResource TitleStyl}"'
edit "$T/r2" WpfApp/App.xaml '                <ResourceDictionary Source="pack://application:,,,/MaterialDesignThemes.Wpf;component/Themes/Foo.xaml" />
' ''
out="$(check "$T/r2")"; rc=$?
ok "RES001: missing key, no external dictionary -> error, rc=1" "$([ $rc = 1 ] && [ "$(has "$out" 'error   RES001')" = 1 ] && [ "$(has "$out" 'TitleStyl')" = 1 ] && echo 1 || echo 0)"

mutate r3
python3 - "$T/r3/WpfApp/Themes/Colors.xaml" <<'PY'
import sys
p = sys.argv[1]
open(p, "w", encoding="utf-8").write('''<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Style x:Key="TitleStyle" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource PrimaryBrush}" />
    </Style>
    <SolidColorBrush x:Key="PrimaryBrush" Color="Blue" />
</ResourceDictionary>
''')
PY
out="$(check "$T/r3")"; rc=$?
ok "RES002: forward reference inside one dictionary -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   RES002')" = 1 ] && [ "$(has "$out" 'WpfApp/Themes/Colors.xaml(4)')" = 1 ] && echo 1 || echo 0)"

mutate r4; edit "$T/r4" WpfApp/Themes/Colors.xaml '    <Style x:Key="TitleStyle" TargetType="TextBlock">' '    <SolidColorBrush x:Key="PrimaryBrush" Color="Red" />
    <Style x:Key="TitleStyle" TargetType="TextBlock">'
out="$(check "$T/r4")"; rc=$?
ok "RES003: duplicate x:Key in one dictionary -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   RES003')" = 1 ] && [ "$(has "$out" 'PrimaryBrush')" = 1 ] && echo 1 || echo 0)"

mutate r5; edit "$T/r5" WpfApp/MainWindow.xaml 'Foreground="{DynamicResource PrimaryBrush}"' 'Foreground="{DynamicResource PrimaryBrsh}"'
edit "$T/r5" WpfApp/App.xaml '                <ResourceDictionary Source="pack://application:,,,/MaterialDesignThemes.Wpf;component/Themes/Foo.xaml" />
' ''
out="$(check "$T/r5")"; rc=$?
ok "RES004: DynamicResource with an undefined key -> warning" "$([ $rc = 0 ] && [ "$(has "$out" 'warning RES004')" = 1 ] && echo 1 || echo 0)"

mutate r6; edit "$T/r6" WpfApp/App.xaml 'Source="Themes/Colors.xaml"' 'Source="Themes/Colours.xaml"'
out="$(check "$T/r6")"; rc=$?
ok "RES005: MergedDictionaries Source that does not exist -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   RES005')" = 1 ] && [ "$(has "$out" 'Colours.xaml')" = 1 ] && echo 1 || echo 0)"

mutate r7
mkdir -p "$T/r7/WpfApp/Converters"
cat > "$T/r7/WpfApp/Converters/NotAConverter.cs" <<'EOF'
namespace WpfApp.Converters;

public class NotAConverter
{
}
EOF
edit "$T/r7" WpfApp/App.xaml 'xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"' 'xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:conv="clr-namespace:WpfApp.Converters"'
edit "$T/r7" WpfApp/App.xaml '<BooleanToVisibilityConverter x:Key="BoolToVis" />' '<BooleanToVisibilityConverter x:Key="BoolToVis" />
            <conv:NotAConverter x:Key="Bad" />'
edit "$T/r7" WpfApp/MainWindow.xaml 'Converter={StaticResource BoolToVis}' 'Converter={StaticResource Bad}'
out="$(check "$T/r7")"; rc=$?
ok "CNV001: Converter is a class that does not implement IValueConverter -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   CNV001')" = 1 ] && echo 1 || echo 0)"

mutate r8; python3 - "$T/r8/WpfApp/MainWindow.xaml.cs" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("    public MainWindow()", "    public MainWindow(int unused) : this()\n    {\n    }\n\n    public MainWindow()"))
PY
out="$(check "$T/r8")"
ok "UI001: a delegating constructor is fine when another one calls InitializeComponent" "$([ "$(has "$out" 'UI001')" = 0 ] && echo 1 || echo 0)"

mutate r9; edit "$T/r9" WpfApp/Themes/Colors.xaml 'Value="{StaticResource PrimaryBrush}"' 'Value="{StaticResource FromCode}"'
cat > "$T/r9/WpfApp/Boot.cs" <<'EOF'
using System.Windows;

namespace WpfApp;

public static class Boot
{
    public static void Init()
    {
        Application.Current.Resources["FromCode"] = new System.Windows.Media.SolidColorBrush();
    }
}
EOF
edit "$T/r9" WpfApp/App.xaml '                <ResourceDictionary Source="pack://application:,,,/MaterialDesignThemes.Wpf;component/Themes/Foo.xaml" />
' ''
out="$(check "$T/r9")"
ok "keys added from code (Resources[\"X\"] = ...) are known: no RES001" "$([ "$(has "$out" 'RES001')" = 0 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 4. 画面の起動
mutate u1; edit "$T/u1" WpfApp/MainWindow.xaml.cs '        InitializeComponent();
' ''
out="$(check "$T/u1")"; rc=$?
ok "UI001: constructor without InitializeComponent() -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   UI001')" = 1 ] && [ "$(has "$out" 'WpfApp/MainWindow.xaml.cs(')" = 1 ] && echo 1 || echo 0)"

mutate u2; edit "$T/u2" WpfApp/App.xaml 'StartupUri="MainWindow.xaml"' 'StartupUri="Main.xaml"'
out="$(check "$T/u2")"; rc=$?
ok "APP001: StartupUri that does not exist -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   APP001')" = 1 ] && [ "$(has "$out" 'Main.xaml')" = 1 ] && echo 1 || echo 0)"

mutate u3; printf '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Grid></Window>' > "$T/u3/WpfApp/Broken.xaml"
out="$(check "$T/u3" --all)"; rc=$?
ok "XAML001: broken XML is reported as info, the rest is still checked (rc=0)" "$([ $rc = 0 ] && [ "$(has "$out" 'XAML001')" = 1 ] && [ "$(has "$out" 'Broken.xaml')" = 1 ] && echo 1 || echo 0)"
out="$(check "$T/u3")"
ok "XAML001 is hidden without --all" "$([ "$(has "$out" 'XAML001')" = 0 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 4b. UI テスト (UI002)
mutate ui1; mkdir -p "$T/ui1/MyApp.UITests"
printf '%s' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0-windows</TargetFramework></PropertyGroup></Project>' > "$T/ui1/MyApp.UITests/MyApp.UITests.csproj"
out="$(check "$T/ui1")"; rc=$?
ok "UI002: with a *.UITests project, controls without AutomationId -> warning (rc=0)" "$([ $rc = 0 ] && [ "$(has "$out" 'warning UI002')" = 1 ] && [ "$(has "$out" 'WpfApp/MainWindow.xaml')" = 1 ] && echo 1 || echo 0)"
ok "UI002: not reported without a UITests project (the clean fixture)" "$([ "$(has "$(check "$T/clean")" 'UI002')" = 0 ] && echo 1 || echo 0)"
mutate ui2; cp -r "$T/ui1/MyApp.UITests" "$T/ui2/MyApp.UITests"
find "$T/ui2/WpfApp" -name '*.xaml' -exec sed -i -E 's/<(TextBox|PasswordBox|ComboBox|CheckBox|RadioButton|ListBox|ListView|DataGrid|Slider|TreeView|TabControl|Button|ToggleButton|RepeatButton)([ >/]|$)/<\1 AutomationProperties.AutomationId="x"\2/' {} +
out="$(check "$T/ui2")"
ok "UI002: AutomationId / x:Name given -> no UI002" "$([ "$(has "$out" 'UI002')" = 0 ] && echo 1 || echo 0)"

# UI004: UI テストがあるとき、CheckBox を Click だけで受けている
mutate ui3; cp -r "$T/ui1/MyApp.UITests" "$T/ui3/MyApp.UITests"
printf '%s' '<Window x:Class="WpfApp.ClickWindow" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><StackPanel><CheckBox AutomationProperties.AutomationId="a" Click="OnA" /><CheckBox AutomationProperties.AutomationId="b" Click="OnB" Checked="OnB" Unchecked="OnB" /></StackPanel></Window>' > "$T/ui3/WpfApp/ClickWindow.xaml"
out="$(check "$T/ui3")"; rc=$?
ok "UI004: a CheckBox handled only by Click (with a UITests project) -> one warning (rc=0)" "$([ $rc = 0 ] && [ "$(has "$out" 'warning UI004')" = 1 ] && [ "$(echo "$out" | grep -c 'UI004')" -le 2 ] && echo 1 || echo 0)"
ok "UI004: not reported without a UITests project" "$([ "$(has "$(check "$T/clean")" 'UI004')" = 0 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 5. 層
mutate l0; edit "$T/l0" MyApp.ViewModels/MyApp.ViewModels.csproj '<TargetFramework>net8.0</TargetFramework>' '<TargetFramework>net8.0-windows</TargetFramework><UseWPF>true</UseWPF>'
out="$(check "$T/l0")"; rc=$?
ok "LAY001: ViewModel project with UseWPF -> error (WS13: was missed)" "$([ $rc = 1 ] && [ "$(has "$out" 'error   LAY001')" = 1 ] && [ "$(has "$out" 'MyApp.ViewModels')" = 1 ] && echo 1 || echo 0)"
mutate l1; edit "$T/l1" MyApp.Logic/MyApp.Logic.csproj '<TargetFramework>net8.0</TargetFramework>' '<TargetFramework>net8.0-windows</TargetFramework><UseWPF>true</UseWPF>'
out="$(check "$T/l1")"; rc=$?
ok "LAY001: logic project with UseWPF -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   LAY001')" = 1 ] && [ "$(has "$out" 'MyApp.Logic')" = 1 ] && echo 1 || echo 0)"

mutate l2; cat > "$T/l2/MyApp.Logic/Notifier.cs" <<'EOF'
using System.Windows;

namespace MyApp.Logic;

public class Notifier
{
    public void Show() => MessageBox.Show("hi");
}
EOF
out="$(check "$T/l2")"; rc=$?
ok "LAY001: logic code using System.Windows / MessageBox -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'MyApp.Logic/Notifier.cs(1)')" = 1 ] && echo 1 || echo 0)"

mutate l3; edit "$T/l3" MyApp.ViewModels/MainViewModel.cs '    [RelayCommand]
    private void Save()
    {' '    [RelayCommand]
    private void Save()
    {
        MessageBox.Show("saved");'
out="$(check "$T/l3")"; rc=$?
ok "LAY002: ViewModel using MessageBox -> warning only" "$([ $rc = 0 ] && [ "$(has "$out" 'warning LAY002')" = 1 ] && echo 1 || echo 0)"

mutate l4; edit "$T/l4" MyApp.Logic/MyApp.Logic.csproj '<PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>' '<PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup><ItemGroup><ProjectReference Include="..\MyApp.ViewModels\MyApp.ViewModels.csproj" /></ItemGroup>'
out="$(check "$T/l4")"; rc=$?
ok "LAY003: logic -> viewmodel reference (wrong direction) -> error" "$([ $rc = 1 ] && [ "$(has "$out" 'error   LAY003')" = 1 ] && [ "$(has "$out" 'MyApp.Logic (logic) が MyApp.ViewModels (vm)')" = 1 ] && echo 1 || echo 0)"

mutate l5; edit "$T/l5" MyApp.ViewModels/MyApp.ViewModels.csproj '<ProjectReference Include="..\MyApp.Logic\MyApp.Logic.csproj" />' '<ProjectReference Include="..\WpfApp\WpfApp.csproj" />'
out="$(check "$T/l5")"
ok "LAY003: viewmodel -> UI exe reference -> error" "$([ "$(has "$out" 'MyApp.ViewModels (vm) が WpfApp (ui)')" = 1 ] && echo 1 || echo 0)"

mutate l6; mv "$T/l6/MyApp.Logic" "$T/l6/Domain"; mv "$T/l6/Domain/MyApp.Logic.csproj" "$T/l6/Domain/Domain.csproj"
edit "$T/l6" MyApp.ViewModels/MyApp.ViewModels.csproj '..\MyApp.Logic\MyApp.Logic.csproj' '..\Domain\Domain.csproj'
edit "$T/l6" Domain/Domain.csproj '<TargetFramework>net8.0</TargetFramework>' '<TargetFramework>net8.0-windows</TargetFramework>'
out="$(check "$T/l6")"
ok "layer name 'Domain' is recognised as logic (LAY001 for -windows TFM)" "$([ "$(has "$out" 'error   LAY001')" = 1 ] && echo 1 || echo 0)"
out="$(check "$T/l6" --data Domain)"
ok "--data Domain overrides the name-based guess (the -windows check still applies)" "$([ "$(has "$out" 'data 層の Domain')" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 6. 出力と終了コード
mutate o1
python3 - "$T/o1/WpfApp/MainWindow.xaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
extra = "".join(f'        <TextBlock Tag="{{Binding Many{i}}}" />\n' for i in range(60))
open(p, "w", encoding="utf-8").write(s.replace("    </StackPanel>", extra + "    </StackPanel>"))
PY
n="$(check "$T/o1" | wc -l)"
ok "output capped at 40 lines (got $n)" "$([ "$n" -le 40 ] && echo 1 || echo 0)"
check "$T/o1" --json "$T/o1.json" >/dev/null
ok "json keeps all findings (>= 60)" "$(python3 -c "
import json,sys
d=json.load(open('$T/o1.json')); sys.exit(0 if len(d['findings'])>=60 and d['counts']['error']>=60 else 1)" && echo 1 || echo 0)"
out="$(check "$T/o1" --max-lines 10 | wc -l)"
ok "--max-lines 10 respected" "$([ "$out" -le 10 ] && echo 1 || echo 0)"

mkdir -p "$T/none"; printf 'namespace X { class A {} }\n' > "$T/none/A.cs"
out="$(check "$T/none")"; rc=$?
ok "no WPF project / xaml -> rc=3" "$([ $rc = 3 ] && [ "$(has "$out" 'nothing to check')" = 1 ] && echo 1 || echo 0)"
out="$(check "$T/nonexistent")"; rc=$?
ok "bad directory -> rc=2" "$([ $rc = 2 ] && [ "$(has "$out" 'BAD_ARGS')" = 1 ] && echo 1 || echo 0)"

# ファイルを変更していないこと (読み取り専用)
before="$(cd "$T/clean" && find . -type f -exec md5sum {} + | sort | md5sum)"
check "$T/clean" --all >/dev/null
after="$(cd "$T/clean" && find . -type f -exec md5sum {} + | sort | md5sum)"
ok "read-only: no files changed" "$([ "$before" = "$after" ] && echo 1 || echo 0)"

# BOM 付き UTF-8 / CRLF の XAML と C# (Visual Studio が保存する形式) でも、同じ結果
mutate w1
python3 - "$T/w1" <<'PY'
import os, sys
for cur, _, fs in os.walk(sys.argv[1]):
    for f in fs:
        if f.endswith((".xaml", ".cs")):
            p = os.path.join(cur, f)
            s = open(p, encoding="utf-8").read().replace("\n", "\r\n")
            open(p, "wb").write(b"\xef\xbb\xbf" + s.encode("utf-8"))
PY
out="$(check "$T/w1")"; rc=$?
ok "BOM + CRLF files: still no findings on the clean project" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"
edit_crlf_bind() { python3 - "$T/w1/WpfApp/MainWindow.xaml" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read().decode("utf-8-sig")
open(p, "wb").write(b"\xef\xbb\xbf" + b.replace("{Binding TotalText}", "{Binding TotalTxt}", 1).encode("utf-8"))
PY
}
edit_crlf_bind
out="$(check "$T/w1")"
ok "BOM + CRLF: line numbers are still right (line 16)" "$([ "$(has "$out" 'WpfApp/MainWindow.xaml(16)')" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 7. WPF プログラミング規約の、機械で判定できる項目
VMF=MyApp.ViewModels/MainViewModel.cs
ANCHOR='public ItemViewModel? Selected { get; set; }'
addvm() {  # $1=複製の名前 $2=追加するメンバー (ViewModel のクラスの中に入れる)
    edit "$T/$1" "$VMF" "$ANCHOR" "$ANCHOR
$2"
}
mutate c1; addvm c1 '    public void Pick() { var dialog = new OpenFileDialog(); dialog.ShowDialog(); }'
out="$(check "$T/c1")"; rc=$?
ok "ViewModel using OpenFileDialog -> LAY002 (warning, rc=0)" "$([ $rc = 0 ] && [ "$(has "$out" 'warning LAY002')" = 1 ] && echo 1 || echo 0)"
mutate c2; edit "$T/c2" "$VMF" 'using MyApp.Logic;' 'using MyApp.Logic;
using WpfApp.Views;'
out="$(check "$T/c2")"
ok "ViewModel referring to the Views namespace -> LAY002" "$([ "$(has "$out" 'warning LAY002')" = 1 ] && [ "$(has "$out" 'using WpfApp.Views;')" = 1 ] && echo 1 || echo 0)"
mutate c3; addvm c3 '    private readonly CustomerService _service = new CustomerService();'
out="$(check "$T/c3")"
ok "DI001: ViewModel creating a Service itself" "$([ "$(has "$out" 'warning DI001')" = 1 ] && [ "$(has "$out" 'new CustomerService(')" = 1 ] && echo 1 || echo 0)"
mutate c3b; addvm c3b '    public ItemViewModel Make() => new ItemViewModel();'
out="$(check "$T/c3b")"
ok "DI001: creating a plain ViewModel / value object is fine (no finding)" "$([ "$(has "$out" 'DI001')" = 0 ] && echo 1 || echo 0)"
mutate c4; addvm c4 '    public void Load() { var customers = LoadAsync().Result; }'
out="$(check "$T/c4")"
ok "ASY001: .Result" "$([ "$(has "$out" 'warning ASY001')" = 1 ] && echo 1 || echo 0)"
mutate c4b; addvm c4b '    public void Load(Task task) { task.Wait(); }'
ok "ASY001: .Wait()" "$([ "$(has "$(check "$T/c4b")" 'warning ASY001')" = 1 ] && echo 1 || echo 0)"
mutate c4c; addvm c4c '    public void Load(System.Threading.Tasks.Task<int> t) { var r = t.GetAwaiter().GetResult(); }'
ok "ASY001: GetAwaiter().GetResult()" "$([ "$(has "$(check "$T/c4c")" 'warning ASY001')" = 1 ] && echo 1 || echo 0)"
mutate c4d; addvm c4d '    public int Pick(System.ComponentModel.RunWorkerCompletedEventArgs args) { return (int)args.Result; }'
ok "ASY001: an unrelated .Result (e.g. RunWorkerCompletedEventArgs.Result) is not reported" "$([ "$(has "$(check "$T/c4d")" 'ASY001')" = 0 ] && echo 1 || echo 0)"
mutate c5; addvm c5 '    private async void Reload() { await Task.Delay(1); }'
out="$(check "$T/c5")"
ok "ASY002: async void that is not an event handler" "$([ "$(has "$out" 'warning ASY002')" = 1 ] && [ "$(has "$out" 'Reload')" = 1 ] && echo 1 || echo 0)"
mutate c5b; addvm c5b '    private async void Window_Loaded(object sender, EventArgs e) { await Task.Delay(1); }'
ok "ASY002: an async void event handler (sender, EventArgs) is allowed" "$([ "$(has "$(check "$T/c5b")" 'ASY002')" = 0 ] && echo 1 || echo 0)"
mutate c6; addvm c6 '    public void A() { try { Name = "x"; } catch { } }
    public void B() { try { Name = "y"; } catch (Exception) { /* ignore */ } }'
out="$(check "$T/c6")"
ok "EXC001: empty catch, also when it only holds a comment (2 findings)" "$([ "$(grep -c 'EXC001' <<<"$out")" = 2 ] && echo 1 || echo 0)"
mutate c6b; addvm c6b '    public void A() { try { Name = "x"; } catch (Exception ex) { System.Diagnostics.Debug.WriteLine(ex); } }'
ok "EXC001: a catch with a body is fine" "$([ "$(has "$(check "$T/c6b")" 'EXC001')" = 0 ] && echo 1 || echo 0)"
mutate c7; addvm c7 '    public void A() { try { Name = "x"; } catch (Exception ex) { throw ex; } }'
ok "EXC002: throw ex;" "$([ "$(has "$(check "$T/c7")" 'warning EXC002')" = 1 ] && echo 1 || echo 0)"
mutate c7b; addvm c7b '    public void A() { try { Name = "x"; } catch (Exception ex) { throw; } }
    public void B() { try { Name = "y"; } catch (Exception ex) { throw new InvalidOperationException("x", ex); } }'
ok "EXC002: throw; and throw new X(ex) are fine" "$([ "$(has "$(check "$T/c7b")" 'EXC002')" = 0 ] && echo 1 || echo 0)"
mutate c8; addvm c8 '    public bool Flag { get; set; }
    private bool _status;'
out="$(check "$T/c8")"
ok "NAM001: bool named Flag / Status (property and field)" "$([ "$(grep -c 'NAM001' <<<"$out")" = 2 ] && echo 1 || echo 0)"
mutate c8b; addvm c8b '    public bool IsFlagged { get; set; }
    public string Status { get; set; } = "";'
ok "NAM001: IsXxx and a string named Status are fine" "$([ "$(has "$(check "$T/c8b")" 'NAM001')" = 0 ] && echo 1 || echo 0)"
mutate c9; mkdir -p "$T/c9/WpfApp/Views"
cat > "$T/c9/WpfApp/Views/SearchView.xaml" <<'XML'
<UserControl x:Class="WpfApp.Views.SearchView"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             DataContext="{Binding RelativeSource={RelativeSource Self}}">
    <TextBox />
</UserControl>
XML
cat > "$T/c9/WpfApp/Views/SearchView.xaml.cs" <<'CS'
using System.Windows.Controls;

namespace WpfApp.Views;

public partial class SearchView : UserControl
{
    public SearchView()
    {
        InitializeComponent();
    }
}
CS
out="$(check "$T/c9")"
ok "UI003: UserControl setting itself as DataContext" "$([ "$(has "$out" 'warning UI003')" = 1 ] && [ "$(has "$out" 'WpfApp/Views/SearchView.xaml(4)')" = 1 ] && echo 1 || echo 0)"
ok "the clean project still has none of the new findings" "$(out="$(check "$T/clean" --all)"; for c in DI001 ASY001 ASY002 EXC001 EXC002 NAM001 UI003; do [ "$(has "$out" "$c")" = 0 ] || exit 1; done; echo 1)"

# ---- 標準の層 (Presentation / Application / Domain / Infrastructure)
mkstd() {
    local D="$1"
    for n in Domain Application Infrastructure Presentation; do mkdir -p "$D/Sample.$n"; done
    cat > "$D/Sample.Domain/Sample.Domain.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>
XML
    cat > "$D/Sample.Application/Sample.Application.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><ProjectReference Include="..\Sample.Domain\Sample.Domain.csproj" /></ItemGroup></Project>
XML
    cat > "$D/Sample.Infrastructure/Sample.Infrastructure.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><ProjectReference Include="..\Sample.Application\Sample.Application.csproj" /><ProjectReference Include="..\Sample.Domain\Sample.Domain.csproj" /></ItemGroup></Project>
XML
    cat > "$D/Sample.Presentation/Sample.Presentation.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>WinExe</OutputType><TargetFramework>net8.0-windows</TargetFramework><UseWPF>true</UseWPF></PropertyGroup>
  <ItemGroup><ProjectReference Include="..\Sample.Application\Sample.Application.csproj" /><ProjectReference Include="..\Sample.Domain\Sample.Domain.csproj" /><ProjectReference Include="..\Sample.Infrastructure\Sample.Infrastructure.csproj" /></ItemGroup></Project>
XML
}
mkstd "$T/std"
out="$(check "$T/std")"; rc=$?
ok "standard layers: the allowed dependencies (Presentation -> App/Domain/Infra, Infra -> App/Domain, App -> Domain) give no finding" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"
mkstd "$T/std2"; edit "$T/std2" Sample.Domain/Sample.Domain.csproj '<PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>' '<PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup><ItemGroup><ProjectReference Include="..\Sample.Application\Sample.Application.csproj" /></ItemGroup>'
out="$(check "$T/std2")"; rc=$?
ok "standard layers: Domain referencing Application -> LAY003 (error, rc=1)" "$([ $rc = 1 ] && [ "$(has "$out" 'error   LAY003')" = 1 ] && [ "$(has "$out" 'Sample.Domain (domain) が Sample.Application (application)')" = 1 ] && echo 1 || echo 0)"
mkstd "$T/std3"; edit "$T/std3" Sample.Application/Sample.Application.csproj '<ProjectReference Include="..\Sample.Domain\Sample.Domain.csproj" />' '<ProjectReference Include="..\Sample.Domain\Sample.Domain.csproj" /><ProjectReference Include="..\Sample.Infrastructure\Sample.Infrastructure.csproj" />'
ok "standard layers: Application referencing Infrastructure -> LAY003" "$([ "$(has "$(check "$T/std3")" 'Sample.Application (application) が Sample.Infrastructure (infrastructure)')" = 1 ] && echo 1 || echo 0)"
mkstd "$T/std4"; edit "$T/std4" Sample.Infrastructure/Sample.Infrastructure.csproj '<TargetFramework>net8.0</TargetFramework>' '<TargetFramework>net8.0-windows</TargetFramework><UseWPF>true</UseWPF>'
ok "standard layers: Infrastructure with UseWPF -> LAY001" "$([ "$(has "$(check "$T/std4")" 'error   LAY001')" = 1 ] && echo 1 || echo 0)"
mkstd "$T/std5"; cat > "$T/std5/Sample.Domain/Order.cs" <<'CS'
using System.Windows;

namespace Sample.Domain;

public class Order
{
    public void Notify() => MessageBox.Show("x");
}
CS
ok "standard layers: Domain code using System.Windows / MessageBox -> LAY001" "$([ "$(has "$(check "$T/std5")" 'Sample.Domain/Order.cs(1)')" = 1 ] && echo 1 || echo 0)"
mkstd "$T/std6"; mkdir -p "$T/std6/Sample.Presentation/ViewModels"; cat > "$T/std6/Sample.Presentation/ViewModels/CustomerViewModel.cs" <<'CS'
namespace Sample.Presentation.ViewModels;

public class CustomerViewModel
{
    private readonly CustomerService _service = new CustomerService();
}
CS
ok "standard layers: the Presentation project's ViewModel is checked too (DI001)" "$([ "$(has "$(check "$T/std6")" 'warning DI001')" = 1 ] && echo 1 || echo 0)"
mkstd "$T/std7"; edit "$T/std7" Sample.Domain/Sample.Domain.csproj '<TargetFramework>net8.0</TargetFramework>' '<TargetFramework>net8.0-windows</TargetFramework>'
out="$(check "$T/std7" --data Sample.Domain)"
ok "--data Sample.Domain overrides the standard-name guess (reported as a data layer)" "$([ "$(has "$out" 'data 層の Sample.Domain')" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- Prism は、積極的には採用しないが、add-package で入っても、引っかからない (v2.59.0)
mutate p1
mkdir -p "$T/p1/MyApp.ViewModels" "$T/p1/WpfApp"
cat > "$T/p1/MyApp.ViewModels/PrismViewModel.cs" <<'EOF'
using Prism.Commands;
using Prism.Mvvm;

namespace MyApp.ViewModels;

public sealed class PrismViewModel : BindableBase
{
    private readonly IGreetingService _greeting;
    private string _name = "";

    public PrismViewModel(IGreetingService greeting)
    {
        _greeting = greeting;
        ClearCommand = new DelegateCommand(Clear, () => Name.Length > 0);
        SendCommand = new DelegateCommand<string>(Send);
    }

    public string Name
    {
        get => _name;
        set { if (SetProperty(ref _name, value)) { RaisePropertyChanged(nameof(Greeting)); ClearCommand.RaiseCanExecuteChanged(); } }
    }

    public string Greeting => _greeting.Make(Name);
    public DelegateCommand ClearCommand { get; }
    public DelegateCommand<string> SendCommand { get; }
    private void Clear() { Name = ""; }
    private void Send(string text) { Name = text; }
}

public interface IGreetingService { string Make(string name); }
EOF
cat > "$T/p1/WpfApp/PrismRegistrations.cs" <<'EOF'
using Prism.DryIoc;
using Prism.Ioc;
using MyApp.ViewModels;

namespace WpfApp;

public partial class PrismBootstrap : PrismApplication
{
    protected override void RegisterTypes(IContainerRegistry containerRegistry)
    {
        containerRegistry.RegisterInstance<IGreetingService>(new GreetingService());
        containerRegistry.Register<PrismViewModel>();
    }
}

public sealed class GreetingService : IGreetingService
{
    public string Make(string name) => name;
}
EOF
out="$(check "$T/p1" --all)"; rc=$?
ok "a Prism-style project (BindableBase + DelegateCommand (+ <T>) + constructor injection + PrismApplication.RegisterTypes registering with new) is not flagged (rc=0)" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && [ "$(has "$out" 'DI001')" = 0 ] && echo 1 || echo 0)"
mutate p5
cat > "$T/p5/WpfApp/ViewModelModule.cs" <<'EOF'
using Microsoft.Extensions.DependencyInjection;
using MyApp.ViewModels;

namespace WpfApp;

internal static class ViewModelModule
{
    internal static IServiceCollection AddViewModels(this IServiceCollection services)
    {
        services.AddSingleton<IGreetingService>(new CustomerService());
        return services;
    }
}
EOF
out="$(check "$T/p5")"
ok "a file named ViewModel*.cs that registers services (IServiceCollection) is a composition root: no DI001" "$([ "$(has "$out" 'DI001')" = 0 ] && echo 1 || echo 0)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
