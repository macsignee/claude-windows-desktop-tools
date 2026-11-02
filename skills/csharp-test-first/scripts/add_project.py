#!/usr/bin/env python3
"""add_project.py - .NET (WPF) のソリューションに、「クラスライブラリ」と、(必要なら) 「対応するテストプロジェクト (MSTest)」を追加する。

Usage: python3 add_project.py <SLN_DIR> <Name> [--kind lib|data|logic|viewmodel] [--tests none|mstest] [--tests-only]
                              [--namespace NS] [--uses OTHER ...] [--tfm net10.0] [--mstest-version V] [--testsdk-version V] [--dry-run]

  SLN_DIR      .sln または .slnx があるフォルダ (Claude Code を起動したフォルダ)
  Name         ライブラリのプロジェクト名 (例: LogicLayer、ViewModels、SampleApp.Domain)。テストは <Name>.Tests になる。
               名前に . が含まれるときは、その名前が、そのまま、名前空間になる (中規模以上の、Presentation / Application / Domain / Infrastructure 用)
  --kind       lib (既定) / data / logic / viewmodel。名前空間の末尾 (Data / Logic / ViewModels) と、viewmodel のときの基底クラス
               (ObservableObject / RelayCommand / MainViewModel) の有無が変わるだけ。**WPF 非依存のクラスライブラリ** (net10.0) を作る
  --tests      mstest (既定): ライブラリ + テストプロジェクトを作る。none: ライブラリだけ
  --tests-only すでにあるライブラリ <Name> に、テストプロジェクトだけを足す (名前空間・参照は、既存の .csproj から読む)
  --namespace  ルートの名前空間 (既定: ソリューション名)。ライブラリの名前空間は <ルート>.<Data|Logic|ViewModels|名前>
  --uses       このライブラリが、プロジェクト参照する、別のプロジェクトのフォルダ名 (複数可。例: logic が --uses DataLayer)
  --tfm        対象フレームワーク (既定 net10.0)。WPF のアプリは、末尾に -windows が付く
  --mstest-version / --testsdk-version  MSTest (TestAdapter / TestFramework) と Microsoft.NET.Test.Sdk のバージョン (既定は、実在を確認した版。
               新しい版は、add-package の `nuget versions` で確認して、指定する)
  --dry-run    何も書かず、行う内容だけを表示する

作るもの:
  <Name>/<Name>.csproj, <Name>Info.cs (ビルド確認用の、小さな公開クラス。名前の . は、型名では除く)。--kind viewmodel のときは、ObservableObject.cs / RelayCommand.cs / MainViewModel.cs
  <Name>.Tests/<Name>.Tests.csproj (MSTest。Microsoft.NET.Test.Sdk + MSTest.TestAdapter + MSTest.TestFramework)、<Name>InfoTests.cs (ベースラインの 1 件)
  (viewmodel のときは、MainViewModelTests.cs も)
  ソリューション (.sln / .slnx) に、プロジェクトを追加する。ファイルは、BOM 付き UTF-8、CRLF (Visual Studio の既定)。

終了コード: 0 成功 / 2 引数・ソリューションの問題 / 3 すでに存在する (何も書かない)
このスクリプトは、new-solution の new_solution.py からも、読み込まれる (WPF の新規作成)。規約は、同梱の PROJECT-LAYOUT.md を参照。
NuGet の復元は、ウォッチャーのビルドが行う (/restore)。このスクリプトは、ネットワークを使わない。
"""
import argparse
import os
import re
import sys
import uuid

BOM = b'\xef\xbb\xbf'
CSHARP_SDK_TYPE = '{9A19103F-16F7-4668-BE54-9A1E7A4F7556}'   # SDK 形式の C# プロジェクト
DEFAULT_TFM = 'net10.0'
MSTEST_VER = '3.6.4'
TESTSDK_VER = '17.12.0'
IDENT = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
PROJ_NAME = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$')   # SampleApp.Domain のように、. で区切ってよい
SHORT_NS = {'data': 'Data', 'logic': 'Logic', 'viewmodel': 'ViewModels', 'presenter': 'Logic'}


def die(msg, code=2):
    print('ERROR: ' + msg)
    sys.exit(code)


def new_guid():
    return '{' + str(uuid.uuid4()).upper() + '}'


def to_crlf(text):
    return text.replace('\r\n', '\n').replace('\n', '\r\n')


def write_files(sln_dir, files):
    """BOM 付き UTF-8、CRLF で書く (Visual Studio の既定に合わせる)。"""
    for rel, content in files.items():
        p = os.path.join(sln_dir, *rel.split('/'))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(BOM + to_crlf(content).encode('utf-8'))


def find_solution(sln_dir):
    found = [f for f in sorted(os.listdir(sln_dir)) if f.lower().endswith(('.sln', '.slnx'))]
    if not found:
        die(f'.sln / .slnx が見つからない: {sln_dir}')
    if len(found) > 1:
        die(f'ソリューションが複数ある ({", ".join(found)})。どれを使うか、ユーザーに確認すること')
    return os.path.join(sln_dir, found[0])


def default_namespace(sln_path):
    stem = os.path.splitext(os.path.basename(sln_path))[0]
    return re.sub(r'\W', '', stem) or 'App'


def type_prefix(name):
    """プロジェクト名 → C# の型名に使える接頭辞 (. を除く)。"""
    return name.replace('.', '')


def layer_namespace(root_ns, kind, name):
    """名前が . を含む (SampleApp.Domain) ときは、その名前を、そのまま、名前空間にする。"""
    if '.' in name:
        return name
    return f'{root_ns}.{SHORT_NS.get(kind, name)}'


def windows_tfm(tfm):
    return tfm if tfm.endswith('-windows') else tfm + '-windows'


# ------------------------------------------------------------------ 規約のファイル (templates/dotnet/ と同じ内容。tests/ で、一致を確認する)
DIRECTORY_BUILD_PROPS = '''<Project>

  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>

</Project>
'''

EDITORCONFIG = '''# C# / WPF の書式 (~/.claude/rules/csharp-common.md の「5 C# コーディング規約」と同じ)。Visual Studio と dotnet format が読む。
root = true

[*]
charset = utf-8-bom
end_of_line = crlf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.{csproj,props,targets,slnx,json,yml,yaml}]
indent_size = 2

[*.{slnx,json,yml,yaml,md}]
charset = utf-8

[*.md]
trim_trailing_whitespace = false

[*.cs]
# 括弧は Allman (開き括弧は、次の行の頭)
csharp_new_line_before_open_brace = all
csharp_new_line_before_else = true
csharp_new_line_before_catch = true
csharp_new_line_before_finally = true
csharp_new_line_before_members_in_object_initializers = true
csharp_new_line_before_members_in_anonymous_types = true
# ファイルスコープの名前空間
csharp_style_namespace_declarations = file_scoped:suggestion
csharp_using_directive_placement = outside_namespace:suggestion
dotnet_sort_system_directives_first = true
# 常に、波括弧を付ける
csharp_prefer_braces = true:suggestion
# var は、型が明らかなときだけ
csharp_style_var_for_built_in_types = false:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = false:suggestion
# 命名: 型・メンバーは PascalCase、インターフェースは I 接頭辞、private フィールドは _camelCase
dotnet_naming_rule.interfaces_start_with_i.symbols = interfaces
dotnet_naming_rule.interfaces_start_with_i.style = begins_with_i
dotnet_naming_rule.interfaces_start_with_i.severity = suggestion
dotnet_naming_symbols.interfaces.applicable_kinds = interface
dotnet_naming_style.begins_with_i.required_prefix = I
dotnet_naming_style.begins_with_i.capitalization = pascal_case
dotnet_naming_rule.private_fields_underscore.symbols = private_fields
dotnet_naming_rule.private_fields_underscore.style = underscore_camel
dotnet_naming_rule.private_fields_underscore.severity = suggestion
dotnet_naming_symbols.private_fields.applicable_kinds = field
dotnet_naming_symbols.private_fields.applicable_accessibilities = private, protected, private_protected
dotnet_naming_style.underscore_camel.required_prefix = _
dotnet_naming_style.underscore_camel.capitalization = camel_case
dotnet_naming_rule.types_pascal.symbols = types
dotnet_naming_rule.types_pascal.style = pascal
dotnet_naming_rule.types_pascal.severity = suggestion
dotnet_naming_symbols.types.applicable_kinds = class, struct, enum, delegate
dotnet_naming_style.pascal.capitalization = pascal_case

[*.xaml]
indent_size = 4
'''

GITIGNORE = '''.vs/
bin/
obj/
*.user
TestResults/
# ウォッチャーと Claude (Skill) が、ソリューションのフォルダに作る一時ファイル
.claude-logs/
trigger_*.flag
build_result.txt
build_error.log
test_result.txt
test_error.log
gtest_result.txt
gtest_error.log
package_result.txt
package_error.log
package_output.txt
# vcpkg (C++ を混ぜる場合) と、取得したソース
vcpkg_installed/
'''


# ------------------------------------------------------------------ プロジェクトファイル
def csproj_lib(tfm, root_ns, refs):
    items = ''.join(f'    <ProjectReference Include="..\\{r}\\{r}.csproj" />\n' for r in refs)
    ref_block = f'\n  <ItemGroup>\n{items}  </ItemGroup>\n' if refs else ''
    return f'''<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>{tfm}</TargetFramework>
    <RootNamespace>{root_ns}</RootNamespace>
  </PropertyGroup>
{ref_block}
</Project>
'''


def csproj_test(tfm, root_ns, target, mstest_ver, sdk_ver, extra_refs=()):
    refs = [target] + [r for r in extra_refs if r != target]
    items = ''.join(f'    <ProjectReference Include="..\\{r}\\{r}.csproj" />\n' for r in refs)
    return f'''<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>{tfm}</TargetFramework>
    <RootNamespace>{root_ns}.Tests</RootNamespace>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="{sdk_ver}" />
    <PackageReference Include="MSTest.TestAdapter" Version="{mstest_ver}" />
    <PackageReference Include="MSTest.TestFramework" Version="{mstest_ver}" />
  </ItemGroup>

  <ItemGroup>
{items}  </ItemGroup>

</Project>
'''


def csproj_winforms(tfm, root_ns, refs):
    items = ''.join(f'    <ProjectReference Include="..\\{r}\\{r}.csproj" />\n' for r in refs)
    ref_block = f'\n  <ItemGroup>\n{items}  </ItemGroup>\n' if refs else ''
    return f'''<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>{windows_tfm(tfm)}</TargetFramework>
    <UseWindowsForms>true</UseWindowsForms>
    <ApplicationHighDpiMode>SystemAware</ApplicationHighDpiMode>
    <RootNamespace>{root_ns}</RootNamespace>
  </PropertyGroup>

  <ItemGroup>
    <Compile Update="Forms\\MainForm.cs">
      <SubType>Form</SubType>
    </Compile>
  </ItemGroup>
{ref_block}
</Project>
'''


def csproj_wpf(tfm, root_ns, refs):
    items = ''.join(f'    <ProjectReference Include="..\\{r}\\{r}.csproj" />\n' for r in refs)
    ref_block = f'\n  <ItemGroup>\n{items}  </ItemGroup>\n' if refs else ''
    return f'''<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>{windows_tfm(tfm)}</TargetFramework>
    <UseWPF>true</UseWPF>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <RootNamespace>{root_ns}</RootNamespace>
  </PropertyGroup>
{ref_block}
</Project>
'''


# ------------------------------------------------------------------ ソース
def info_cs(name, ns):
    return f'''namespace {ns};

/// <summary>ビルドと参照の確認用の、小さな公開クラス。本物の機能ができたら、消してよい。</summary>
public static class {type_prefix(name)}Info
{{
    /// <summary>このプロジェクトの名前。</summary>
    public static string Name => "{name}";
}}
'''


def info_tests_cs(name, ns):
    return f'''using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace {ns}.Tests;

[TestClass]
public class {type_prefix(name)}InfoTests
{{
    [TestMethod]
    public void Name_ReturnsProjectName()
    {{
        Assert.AreEqual("{name}", {type_prefix(name)}Info.Name);
    }}
}}
'''


def observable_object_cs(ns):
    return f'''using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace {ns};

/// <summary>INotifyPropertyChanged の基底クラス。ViewModel は、これを継承する。</summary>
public abstract class ObservableObject : INotifyPropertyChanged
{{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {{
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }}

    /// <summary>値が変わったときだけ、フィールドを更新して、変更を通知する。</summary>
    protected bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {{
        if (EqualityComparer<T>.Default.Equals(field, value))
        {{
            return false;
        }}

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }}
}}
'''


def relay_command_cs(ns):
    return f'''using System.Windows.Input;

namespace {ns};

/// <summary>引数のない、同期のコマンド。</summary>
public sealed class RelayCommand : ICommand
{{
    private readonly Action _execute;
    private readonly Func<bool>? _canExecute;

    public RelayCommand(Action execute, Func<bool>? canExecute = null)
    {{
        ArgumentNullException.ThrowIfNull(execute);
        _execute = execute;
        _canExecute = canExecute;
    }}

    public event EventHandler? CanExecuteChanged;

    public bool CanExecute(object? parameter) => _canExecute?.Invoke() ?? true;

    public void Execute(object? parameter) => _execute();

    /// <summary>実行できるかどうかが変わったことを、通知する。</summary>
    public void NotifyCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}}
'''


def main_viewmodel_cs(ns):
    return f'''namespace {ns};

/// <summary>メイン画面の ViewModel。WPF の型 (Window や MessageBox) を、使わない。</summary>
public sealed class MainViewModel : ObservableObject
{{
    private string _name = "";

    public MainViewModel()
    {{
        ClearCommand = new RelayCommand(Clear, () => Name.Length > 0);
    }}

    public string Name
    {{
        get => _name;
        set
        {{
            if (SetProperty(ref _name, value))
            {{
                OnPropertyChanged(nameof(Greeting));
                ClearCommand.NotifyCanExecuteChanged();
            }}
        }}
    }}

    public string Greeting => Name.Length == 0 ? "名前を入力してください" : $"こんにちは、{{Name}} さん";

    public RelayCommand ClearCommand {{ get; }}

    private void Clear()
    {{
        Name = "";
    }}
}}
'''


def main_viewmodel_tests_cs(ns):
    return f'''using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace {ns}.Tests;

[TestClass]
public class MainViewModelTests
{{
    [TestMethod]
    public void Greeting_NameEmpty_AsksForName()
    {{
        var vm = new MainViewModel();

        Assert.AreEqual("名前を入力してください", vm.Greeting);
    }}

    [TestMethod]
    public void Greeting_NameSet_GreetsByName()
    {{
        var vm = new MainViewModel {{ Name = "太郎" }};

        Assert.AreEqual("こんにちは、太郎 さん", vm.Greeting);
    }}

    [TestMethod]
    public void Name_Changed_RaisesPropertyChangedForNameAndGreeting()
    {{
        var vm = new MainViewModel();
        var raised = new List<string?>();
        vm.PropertyChanged += (_, e) => raised.Add(e.PropertyName);

        vm.Name = "太郎";

        CollectionAssert.AreEquivalent(new[] {{ "Name", "Greeting" }}, raised);
    }}

    [TestMethod]
    public void ClearCommand_NameEmpty_CannotExecute()
    {{
        var vm = new MainViewModel();

        Assert.IsFalse(vm.ClearCommand.CanExecute(null));
    }}

    [TestMethod]
    public void ClearCommand_Execute_ClearsName()
    {{
        var vm = new MainViewModel {{ Name = "太郎" }};

        vm.ClearCommand.Execute(null);

        Assert.AreEqual("", vm.Name);
    }}
}}
'''


def styles_xaml():
    """色・余白・スタイルは、各画面に直接書かず、ResourceDictionary に置く。"""
    return '''<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <Thickness x:Key="DefaultControlMargin">8</Thickness>

    <Style x:Key="PrimaryButtonStyle"
           TargetType="Button">
        <Setter Property="Margin"
                Value="{StaticResource DefaultControlMargin}" />
        <Setter Property="MinWidth"
                Value="100" />
    </Style>

</ResourceDictionary>
'''


def app_xaml(ns):
    return f'''<Application x:Class="{ns}.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="Resources/Styles.xaml" />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Application.Resources>
</Application>
'''


def app_xaml_cs(ns, vm_ns):
    # using の並びは、dotnet format (IMPORTS) の規約に合わせる: System が先、残りは名前の順
    usings = "\n".join(f"using {u};" for u in sorted({f"{ns}.Views", vm_ns}))
    return f'''using System.Windows;
{usings}

namespace {ns};

public partial class App : Application
{{
    protected override void OnStartup(StartupEventArgs e)
    {{
        base.OnStartup(e);

        // 画面と ViewModel を組み立てる場所 (composition root)。DI コンテナを導入するときは、ここで構成する。
        var window = new MainWindow
        {{
            DataContext = new MainViewModel(),
        }};
        window.Show();
    }}
}}
'''


def app_manifest():
    """DPI 認識モードを、明示するマニフェスト (UI デザインガイドライン UI-DPI-002)。WPF の既定と同じ、システム DPI 対応。
    モニターごとの DPI に追従させるときは、dpiAware を true/pm にし、dpiAwareness (PerMonitorV2) を足す (UI-DPI-004)。"""
    return '''<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
    </windowsSettings>
  </application>
</assembly>
'''


def main_window_xaml(ns, title, vm_ns, vm_assembly=None):
    asm = f';assembly={vm_assembly}' if vm_assembly else ''
    return f'''<Window x:Class="{ns}.Views.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:vm="clr-namespace:{vm_ns}{asm}"
        mc:Ignorable="d"
        d:DataContext="{{d:DesignInstance Type=vm:MainViewModel, IsDesignTimeCreatable=True}}"
        Title="{title}"
        Width="400"
        Height="220"
        MinWidth="320"
        MinHeight="180">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
        </Grid.RowDefinitions>

        <DockPanel Grid.Row="0">
            <Label x:Name="NameLabel"
                   DockPanel.Dock="Left"
                   Margin="{{StaticResource DefaultControlMargin}}"
                   Content="名前:"
                   Target="{{Binding ElementName=NameTextBox}}" />
            <TextBox x:Name="NameTextBox"
                     AutomationProperties.AutomationId="NameTextBox"
                     AutomationProperties.LabeledBy="{{Binding ElementName=NameLabel}}"
                     Margin="{{StaticResource DefaultControlMargin}}"
                     Text="{{Binding Name, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}}" />
        </DockPanel>

        <TextBlock Grid.Row="1"
                   AutomationProperties.AutomationId="GreetingText"
                   Margin="{{StaticResource DefaultControlMargin}}"
                   Text="{{Binding Greeting, Mode=OneWay}}" />

        <Button Grid.Row="2"
                AutomationProperties.AutomationId="ClearButton"
                HorizontalAlignment="Left"
                VerticalAlignment="Top"
                Style="{{StaticResource PrimaryButtonStyle}}"
                Content="クリア"
                Command="{{Binding ClearCommand}}" />
    </Grid>
</Window>
'''


def main_window_cs(ns):
    return f'''using System.Windows;

namespace {ns}.Views;

/// <summary>メイン画面。View 固有の処理だけを書く (業務ロジックと、DataContext の設定は、書かない)。</summary>
public partial class MainWindow : Window
{{
    public MainWindow()
    {{
        InitializeComponent();
    }}
}}
'''


# ------------------------------------------------------------------ WinForms のソース (MVP: Form は IMainView を実装し、MainPresenter が振る舞いを持つ)
def main_view_cs(ns):
    return f'''namespace {ns};

/// <summary>メイン画面の、Presenter から見た姿。WinForms の型 (Form や MessageBox) を、持ち込まない。</summary>
public interface IMainView
{{
    /// <summary>入力された名前。</summary>
    string PersonName {{ get; set; }}

    /// <summary>表示する挨拶。</summary>
    string Greeting {{ set; }}

    /// <summary>クリアを、押せるか。</summary>
    bool CanClear {{ set; }}

    /// <summary>名前が、変わった。</summary>
    event EventHandler? NameChanged;

    /// <summary>クリアが、求められた。</summary>
    event EventHandler? ClearRequested;
}}
'''


def main_presenter_cs(ns):
    return f'''namespace {ns};

/// <summary>メイン画面の振る舞い。WinForms の型を使わない (View は IMainView 越しに触る)。</summary>
public sealed class MainPresenter
{{
    private readonly IMainView _view;

    public MainPresenter(IMainView view)
    {{
        _view = view;
        _view.NameChanged += OnNameChanged;
        _view.ClearRequested += OnClearRequested;
        Refresh();
    }}

    private void OnNameChanged(object? sender, EventArgs e)
    {{
        Refresh();
    }}

    private void OnClearRequested(object? sender, EventArgs e)
    {{
        _view.PersonName = "";
        Refresh();
    }}

    private void Refresh()
    {{
        var name = _view.PersonName;
        _view.Greeting = name.Length == 0 ? "名前を入力してください" : $"こんにちは、{{name}} さん";
        _view.CanClear = name.Length > 0;
    }}
}}
'''


def main_presenter_tests_cs(ns):
    return f'''using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace {ns}.Tests;

[TestClass]
public class MainPresenterTests
{{
    private sealed class FakeMainView : IMainView
    {{
        public event EventHandler? NameChanged;

        public event EventHandler? ClearRequested;

        public string PersonName {{ get; set; }} = "";

        public string Greeting {{ get; set; }} = "";

        public bool CanClear {{ get; set; }}

        public void RaiseNameChanged(string name)
        {{
            PersonName = name;
            NameChanged?.Invoke(this, EventArgs.Empty);
        }}

        public void RaiseClearRequested()
        {{
            ClearRequested?.Invoke(this, EventArgs.Empty);
        }}
    }}

    [TestMethod]
    public void Constructor_NameEmpty_AsksForNameAndDisablesClear()
    {{
        var view = new FakeMainView();

        _ = new MainPresenter(view);

        Assert.AreEqual("名前を入力してください", view.Greeting);
        Assert.IsFalse(view.CanClear);
    }}

    [TestMethod]
    public void NameChanged_NameSet_GreetsByName()
    {{
        var view = new FakeMainView();
        _ = new MainPresenter(view);

        view.RaiseNameChanged("太郎");

        Assert.AreEqual("こんにちは、太郎 さん", view.Greeting);
    }}

    [TestMethod]
    public void NameChanged_NameSet_EnablesClear()
    {{
        var view = new FakeMainView();
        _ = new MainPresenter(view);

        view.RaiseNameChanged("太郎");

        Assert.IsTrue(view.CanClear);
    }}

    [TestMethod]
    public void ClearRequested_NameSet_ClearsName()
    {{
        var view = new FakeMainView {{ PersonName = "太郎" }};
        _ = new MainPresenter(view);

        view.RaiseClearRequested();

        Assert.AreEqual("", view.PersonName);
        Assert.IsFalse(view.CanClear);
    }}
}}
'''


def program_cs(ns, usings):
    # using の並びは、dotnet format (IMPORTS) の規約に合わせる: System が先、残りは名前の順
    lines = "\n".join(f"using {u};" for u in sorted(set(usings)))
    return f'''{lines}

namespace {ns};

internal static class Program
{{
    [STAThread]
    private static void Main()
    {{
        ApplicationConfiguration.Initialize();

        // 画面と Presenter を組み立てる場所 (composition root)。DI コンテナを導入するときは、ここで構成する。
        var form = new MainForm();
        _ = new MainPresenter(form);
        Application.Run(form);
    }}
}}
'''


def main_form_cs(ns, presenter_ns):
    # using System.Windows.Forms を、明示する (ImplicitUsings に頼ると、VS が Form と認識しなかった。実機で確認)。System が先、残りは名前の順
    usings = "\n".join(f"using {u};" for u in ["System.ComponentModel", "System.Windows.Forms"] + sorted({presenter_ns}))
    return f'''{usings}

namespace {ns}.Forms;

/// <summary>メイン画面。View 固有の処理だけを書く (業務ロジックは、Presenter に置く)。
/// IMainView のプロパティは、デザイナーが保存しない値なので、[DesignerSerializationVisibility(Hidden)] を付ける (.NET 9 以降の WinForms 解析 WFO1000 が、ビルドエラーにする)。</summary>
public partial class MainForm : Form, IMainView
{{
    public MainForm()
    {{
        InitializeComponent();
    }}

    public event EventHandler? NameChanged;

    public event EventHandler? ClearRequested;

    [Browsable(false)]
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public string PersonName
    {{
        get => NameTextBox.Text;
        set => NameTextBox.Text = value;
    }}

    [Browsable(false)]
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public string Greeting
    {{
        set => GreetingLabel.Text = value;
    }}

    [Browsable(false)]
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public bool CanClear
    {{
        set => ClearButton.Enabled = value;
    }}

    private void NameTextBox_TextChanged(object? sender, EventArgs e)
    {{
        NameChanged?.Invoke(this, EventArgs.Empty);
    }}

    private void ClearButton_Click(object? sender, EventArgs e)
    {{
        ClearRequested?.Invoke(this, EventArgs.Empty);
    }}
}}
'''


def main_form_designer_cs(ns, title):
    return f'''namespace {ns}.Forms;

partial class MainForm
{{
    /// <summary>
    /// Required designer variable.
    /// </summary>
    private System.ComponentModel.IContainer components = null;

    /// <summary>
    /// Clean up any resources being used.
    /// </summary>
    /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
    protected override void Dispose(bool disposing)
    {{
        if (disposing && (components != null))
        {{
            components.Dispose();
        }}
        base.Dispose(disposing);
    }}

    #region Windows Form Designer generated code

    /// <summary>
    /// Required method for Designer support - do not modify
    /// the contents of this method with the code editor.
    /// </summary>
    private void InitializeComponent()
    {{
        MainTable = new TableLayoutPanel();
        NameTextBox = new TextBox();
        GreetingLabel = new Label();
        ClearButton = new Button();
        MainTable.SuspendLayout();
        SuspendLayout();
        //
        // MainTable
        //
        MainTable.ColumnCount = 1;
        MainTable.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        MainTable.Controls.Add(NameTextBox, 0, 0);
        MainTable.Controls.Add(GreetingLabel, 0, 1);
        MainTable.Controls.Add(ClearButton, 0, 2);
        MainTable.Dock = DockStyle.Fill;
        MainTable.Name = "MainTable";
        MainTable.Padding = new Padding(12);
        MainTable.RowCount = 3;
        MainTable.RowStyles.Add(new RowStyle());
        MainTable.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        MainTable.RowStyles.Add(new RowStyle());
        MainTable.TabIndex = 0;
        //
        // NameTextBox
        //
        NameTextBox.Dock = DockStyle.Fill;
        NameTextBox.Name = "NameTextBox";
        NameTextBox.TabIndex = 0;
        NameTextBox.TextChanged += NameTextBox_TextChanged;
        //
        // GreetingLabel
        //
        GreetingLabel.Dock = DockStyle.Fill;
        GreetingLabel.Name = "GreetingLabel";
        GreetingLabel.TabIndex = 1;
        GreetingLabel.TextAlign = ContentAlignment.MiddleLeft;
        //
        // ClearButton
        //
        ClearButton.Anchor = AnchorStyles.Right;
        ClearButton.AutoSize = true;
        ClearButton.Name = "ClearButton";
        ClearButton.TabIndex = 2;
        ClearButton.Text = "クリア";
        ClearButton.UseVisualStyleBackColor = true;
        ClearButton.Click += ClearButton_Click;
        //
        // MainForm
        //
        AutoScaleDimensions = new SizeF(7F, 15F);
        AutoScaleMode = AutoScaleMode.Font;
        ClientSize = new Size(400, 180);
        Controls.Add(MainTable);
        MinimumSize = new Size(320, 160);
        Name = "MainForm";
        StartPosition = FormStartPosition.CenterScreen;
        Text = "{title}";
        MainTable.ResumeLayout(false);
        MainTable.PerformLayout();
        ResumeLayout(false);
    }}

    #endregion

    private TableLayoutPanel MainTable;
    private TextBox NameTextBox;
    private Label GreetingLabel;
    private Button ClearButton;
}}
'''


# ------------------------------------------------------------------ ファイル一式
def lib_files(name, ns, uses, tfm, kind='lib'):
    """ライブラリ <Name> のファイル一式 (WPF 非依存)。"""
    files = {
        f'{name}/{name}.csproj': csproj_lib(tfm, ns, uses),
        f'{name}/{type_prefix(name)}Info.cs': info_cs(name, ns),
    }
    if kind == 'viewmodel':
        files.update(viewmodel_files(f'{name}', ns))
    if kind == 'presenter':
        files.update(presenter_files(f'{name}', ns))
    return files


def presenter_files(folder, ns):
    return {
        f'{folder}/IMainView.cs': main_view_cs(ns),
        f'{folder}/MainPresenter.cs': main_presenter_cs(ns),
    }


def viewmodel_files(folder, ns):
    return {
        f'{folder}/ObservableObject.cs': observable_object_cs(ns),
        f'{folder}/RelayCommand.cs': relay_command_cs(ns),
        f'{folder}/MainViewModel.cs': main_viewmodel_cs(ns),
    }


def test_files(name, ns, tfm, mstest_ver, sdk_ver, kind='lib', extra_refs=()):
    """<Name>.Tests のファイル一式。"""
    tn = f'{name}.Tests'
    if kind == 'app-presenter':
        # ロジック層のない WinForms: アプリ (WinExe) の Presenters/ を、テストする。Info クラスがないので、ベースラインは Presenter のテスト。
        # アプリが <TFM>-windows なので、テストも同じ TFM (違うと NU1201)
        return {
            f'{tn}/{tn}.csproj': csproj_test(windows_tfm(tfm), ns, name, mstest_ver, sdk_ver, extra_refs),
            f'{tn}/MainPresenterTests.cs': main_presenter_tests_cs(ns),
        }
    files = {
        f'{tn}/{tn}.csproj': csproj_test(tfm, ns, name, mstest_ver, sdk_ver, extra_refs),
        f'{tn}/{type_prefix(name)}InfoTests.cs': info_tests_cs(name, ns),
    }
    if kind == 'viewmodel':
        files[f'{tn}/MainViewModelTests.cs'] = main_viewmodel_tests_cs(ns)
    if kind == 'presenter':
        files[f'{tn}/MainPresenterTests.cs'] = main_presenter_tests_cs(ns)
    return files


def winforms_app_files(name, ns, tfm, uses, presenter_ns, presenter_in_app):
    """WinForms のメイン (View)。presenter_in_app なら、IMainView / MainPresenter を、アプリの Presenters フォルダに置く。
    構成: Program.cs (composition root) / Forms/ (Form と Designer) / Presenters/ (ロジック層がないとき)。"""
    files = {
        f'{name}/{name}.csproj': csproj_winforms(tfm, ns, uses),
        f'{name}/Program.cs': program_cs(ns, [f'{ns}.Forms', presenter_ns]),
        f'{name}/Forms/MainForm.cs': main_form_cs(ns, presenter_ns),
        f'{name}/Forms/MainForm.Designer.cs': main_form_designer_cs(ns, name),
    }
    if presenter_in_app:
        files.update(presenter_files(f'{name}/Presenters', presenter_ns))
    return files


def wpf_app_files(name, ns, tfm, uses, vm_in_app, vm_project=None):
    """WPF のメイン (View)。vm_in_app なら、ViewModel をアプリの ViewModels フォルダに置く。
    構成: App.xaml / Views/ / ViewModels/ / Resources/ (WPF プログラミング規約 3.1)。"""
    # ViewModel が別のプロジェクトにあるときは、その名前空間 (layer_namespace)。アプリの中なら <ルート>.ViewModels
    vm_ns = f'{ns}.ViewModels' if vm_in_app or not vm_project else layer_namespace(ns, 'viewmodel', vm_project)
    files = {
        f'{name}/{name}.csproj': csproj_wpf(tfm, ns, uses),
        f'{name}/app.manifest': app_manifest(),
        f'{name}/App.xaml': app_xaml(ns),
        f'{name}/App.xaml.cs': app_xaml_cs(ns, vm_ns),
        f'{name}/Resources/Styles.xaml': styles_xaml(),
        f'{name}/Views/MainWindow.xaml': main_window_xaml(ns, name, vm_ns, None if vm_in_app else vm_project),
        f'{name}/Views/MainWindow.xaml.cs': main_window_cs(ns),
    }
    if vm_in_app:
        files.update(viewmodel_files(f'{name}/ViewModels', vm_ns))
    return files


# ------------------------------------------------------------------ ソリューションの編集
def slnx_text(projects, startup=None):
    """projects: [(名前, guid)]。.NET だけの .slnx は、構成を書かない (Visual Studio の既定: Debug / Release、Any CPU)。"""
    out = '<Solution>\n'
    for n, g in projects:
        mark = ' DefaultStartup="true"' if n == startup else ''
        out += f'  <Project Path="{n}/{n}.csproj" Id="{g.strip("{}").lower()}"{mark} />\n'
    return out + '</Solution>\n'


def edit_sln(path, projects):
    raw = open(path, 'rb').read()
    bom = raw.startswith(BOM)
    text = raw[3:].decode('utf-8') if bom else raw.decode('utf-8')
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = text.replace('\r\n', '\n').split('\n')

    cfgs, in_sec = [], False
    for ln in lines:
        if 'GlobalSection(SolutionConfigurationPlatforms)' in ln:
            in_sec = True
            continue
        if in_sec and 'EndGlobalSection' in ln:
            break
        m = re.match(r'\s*([^|=\s]+)\|([^=]+?)\s*=', ln) if in_sec else None
        if m:
            cfgs.append((m.group(1), m.group(2).strip()))
    if not cfgs:
        print('WARNING: ソリューションに構成がない。プロジェクトは追加するが、構成の対応付けは、Visual Studio で行うこと')

    def idx(pred, start=0):
        for i in range(start, len(lines)):
            if pred(lines[i]):
                return i
        return -1

    g = idx(lambda s: s.strip() == 'Global')
    if g < 0:
        die('.sln に Global セクションがない (想定外の形式)')
    proj_lines = []
    for n, gd in projects:
        proj_lines += [f'Project("{CSHARP_SDK_TYPE}") = "{n}", "{n}\\{n}.csproj", "{gd}"', 'EndProject']
    lines[g:g] = proj_lines

    map_lines = []
    for n, gd in projects:
        for c, p in cfgs:
            map_lines += [f'\t\t{gd}.{c}|{p}.ActiveCfg = {c}|Any CPU', f'\t\t{gd}.{c}|{p}.Build.0 = {c}|Any CPU']
    if map_lines:
        s = idx(lambda x: 'GlobalSection(ProjectConfigurationPlatforms)' in x)
        if s >= 0:
            e = idx(lambda x: 'EndGlobalSection' in x, s)
            lines[e:e] = map_lines
        else:
            at = idx(lambda x: 'GlobalSection(SolutionProperties)' in x)
            if at < 0:
                at = idx(lambda x: x.strip() == 'EndGlobal')
            lines[at:at] = ['\tGlobalSection(ProjectConfigurationPlatforms) = postSolution'] + map_lines + ['\tEndGlobalSection']
    open(path, 'wb').write((BOM if bom else b'') + nl.join(lines).encode('utf-8'))


def edit_slnx(path, projects):
    raw = open(path, 'rb').read()
    bom = raw.startswith(BOM)
    text = raw[3:].decode('utf-8') if bom else raw.decode('utf-8')
    nl = '\r\n' if '\r\n' in text else '\n'
    end = text.rfind('</Solution>')
    if end < 0:
        die('.slnx に </Solution> がない (想定外の形式)')
    add = ''.join(f'  <Project Path="{n}/{n}.csproj" Id="{gd.strip("{}").lower()}" />{nl}' for n, gd in projects)
    line_start = text.rfind('\n', 0, end) + 1
    text = text[:line_start] + add + text[line_start:]
    open(path, 'wb').write((BOM if bom else b'') + text.encode('utf-8'))


def register(sln, projects):
    (edit_slnx if sln.lower().endswith('.slnx') else edit_sln)(sln, projects)


# ------------------------------------------------------------------ 既存プロジェクトの読み取り
def read_lib_info(sln_dir, name):
    """既存のライブラリ <Name> の、名前空間・TFM・参照 (プロジェクト名) を、.csproj から読む。"""
    p = os.path.join(sln_dir, name, f'{name}.csproj')
    if not os.path.isfile(p):
        die(f'プロジェクトが見つからない: {name}/{name}.csproj')
    text = open(p, encoding='utf-8-sig').read()
    ns = re.search(r'<RootNamespace>([^<]+)</RootNamespace>', text)
    tfm = re.search(r'<TargetFramework>([^<]+)</TargetFramework>', text)
    uses = [os.path.splitext(os.path.basename(m.replace('\\', '/')))[0]
            for m in re.findall(r'<ProjectReference\s+Include="([^"]+)"', text)]
    return {'ns': ns.group(1) if ns else None, 'tfm': tfm.group(1) if tfm else DEFAULT_TFM, 'uses': uses,
            'is_vm': os.path.isfile(os.path.join(sln_dir, name, 'MainViewModel.cs')),
            'is_presenter': os.path.isfile(os.path.join(sln_dir, name, 'MainPresenter.cs')),
            'is_app_presenter': os.path.isfile(os.path.join(sln_dir, name, 'Presenters', 'MainPresenter.cs')),
            'is_exe': bool(re.search(r'<OutputType>\s*(Win)?Exe\s*</OutputType>', text)),
            'is_test': 'Microsoft.NET.Test.Sdk' in text}


def libraries_without_tests(sln_dir):
    """テストプロジェクトのない、ライブラリ (exe とテストプロジェクトを除く。ただし、アプリの Presenters/ に Presenter がある WinForms のアプリは含める) の名前の一覧。"""
    out = []
    for d in sorted(os.listdir(sln_dir)):
        p = os.path.join(sln_dir, d, f'{d}.csproj')
        if not os.path.isfile(p) or d.endswith('.Tests'):
            continue
        info = read_lib_info(sln_dir, d)
        if info['is_test'] or (info['is_exe'] and not info['is_app_presenter']):   # WPF のアプリは除く。Presenter を持つ WinForms のアプリは、対象
            continue
        if os.path.exists(os.path.join(sln_dir, f'{d}.Tests')):
            continue
        out.append(d)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sln_dir')
    ap.add_argument('name')
    ap.add_argument('--kind', choices=['lib', 'data', 'logic', 'viewmodel', 'presenter'], default='lib')
    ap.add_argument('--tests', choices=['none', 'mstest'], default='mstest')
    ap.add_argument('--tests-only', action='store_true')
    ap.add_argument('--namespace')
    ap.add_argument('--uses', action='append', default=[])
    ap.add_argument('--tfm', default=DEFAULT_TFM)
    ap.add_argument('--mstest-version', default=MSTEST_VER)
    ap.add_argument('--testsdk-version', default=TESTSDK_VER)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    sln_dir = os.path.abspath(a.sln_dir)
    if not os.path.isdir(sln_dir):
        die(f'フォルダがない: {sln_dir}')
    sln = find_solution(sln_dir)
    if not PROJ_NAME.match(a.name):
        die(f'プロジェクト名が不正 (英数字と _ のみ、先頭は英字か _。SampleApp.Domain のように . で区切ってよい): {a.name}')
    for u in a.uses:
        if not os.path.isfile(os.path.join(sln_dir, u, f'{u}.csproj')):
            die(f'--uses のプロジェクトが見つからない: {u}/{u}.csproj')
    root_ns = a.namespace or default_namespace(sln)

    files, projects = {}, []
    if a.tests_only:
        info = read_lib_info(sln_dir, a.name)
        if os.path.exists(os.path.join(sln_dir, f'{a.name}.Tests')):
            die(f'すでに存在する: {a.name}.Tests (何も書いていない)', 3)
        ns = a.namespace or info['ns'] or layer_namespace(root_ns, a.kind, a.name)
        kind = 'viewmodel' if info['is_vm'] else ('presenter' if info['is_presenter'] else a.kind)
        tg = new_guid()
        files = test_files(a.name, ns, info['tfm'], a.mstest_version, a.testsdk_version, kind)
        projects = [(f'{a.name}.Tests', tg)]
    else:
        if os.path.exists(os.path.join(sln_dir, a.name)):
            die(f'すでに存在する: {a.name} (何も書いていない)', 3)
        if a.tests == 'mstest' and os.path.exists(os.path.join(sln_dir, f'{a.name}.Tests')):
            die(f'すでに存在する: {a.name}.Tests (何も書いていない)', 3)
        ns = layer_namespace(root_ns, a.kind, a.name)
        lg = new_guid()
        files = lib_files(a.name, ns, a.uses, a.tfm, a.kind)
        projects = [(a.name, lg)]
        if a.tests == 'mstest':
            tg = new_guid()
            files.update(test_files(a.name, ns, a.tfm, a.mstest_version, a.testsdk_version, a.kind))
            projects.append((f'{a.name}.Tests', tg))

    print(f'ソリューション : {os.path.basename(sln)} (すでにある)')
    print(f'名前空間       : {ns}')
    for rel in files:
        print(f'  + {rel}')
    print(f'  ~ {os.path.basename(sln)} ({len(projects)} プロジェクトを追加)')
    if a.dry_run:
        print('(dry-run: 何も書いていない)')
        return
    write_files(sln_dir, files)
    register(sln, projects)
    print('完了。NuGet の復元は、ウォッチャーのビルド (/restore) が行う。')


if __name__ == '__main__':
    main()
