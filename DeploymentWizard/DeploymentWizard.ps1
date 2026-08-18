<#
.SYNOPSIS
    Computer Deployment Wizard v1.1 — WPF-based SCCM deployment interface.

.CONFIGURATION
    Before using this script, replace the following placeholders with your actual values:

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ PLACEHOLDER              │ PARAMETER       │ DESCRIPTION                     │
    ├──────────────────────────┼─────────────────┼─────────────────────────────────┤
    │ "Your Company Name"      │ -CompanyName    │ Organization name (UI title)    │
    │ "YC"                     │ -CompanyShort   │ 2-3 char logo badge code        │
    │ "IT Operations"          │ -Department     │ Department name in header       │
    │ yourdomain.local         │ -DomainName     │ Active Directory domain FQDN    │
    │ OU=...,DC=...,DC=...     │ -SearchBase     │ LDAP root OU distinguished name │
    │ dc01.yourdomain.local    │ -DomainController│ DC hostname for auth/LDAP      │
    │ sccm.yourdomain.local    │ -SccmServer     │ SCCM MP hostname                │
    │ "Your Company Name"      │ -OrgName        │ Written to OSDRegisteredOrgName │
    └──────────────────────────────────────────────────────────────────────────────┘

.DESCRIPTION
    A professional WPF wizard for SCCM/MECM operating system deployment Task Sequences.
    Provides domain authentication, LDAP OU browsing, device information retrieval,
    software selection, and writes Task Sequence variables via COM TSEnvironment.

    Key capabilities:
      - Active Directory authentication with PrincipalContext.ValidateCredentials
      - LDAP organizational unit browser with live search and friendly-path display
      - WMI device information retrieval (name, model, serial, memory, disk, domain)
      - Real-time connectivity testing against Domain Controller (TCP 389) and SCCM server (TCP 445)
      - Dynamic software checkbox generation from parameterized configuration
      - Styled WPF UI with card-based layout, accent bars, and status indicators
      - Secure credential handling (password masked, not logged)
      - SCCM Task Sequence variable output via COM Microsoft.SMS.TSEnvironment

.PARAMETER CompanyName
    Organization name displayed in the window title, header, and dialogs.
    Default: "Momar Tech"

.PARAMETER CompanyShort
    Abbreviated organization code shown in the logo badge (2-3 characters).
    Default: "MT"

.PARAMETER Department
    Department name displayed in the header subtitle and footer.
    Default: "IT Operations"

.PARAMETER DomainName
    Active Directory domain for authentication and domain join.
    Must match the PrincipalContext validation target.
    Default: "momar.local"

.PARAMETER SearchBase
    Distinguished Name of the root OU container for LDAP browsing.
    Format: "OU=Container,DC=domain,DC=local"
    Default: "OU=Domain Computers,DC=Momar,DC=local"

.PARAMETER DomainController
    Hostname or FQDN of the domain controller for connectivity testing (TCP port 389).
    Default: "dc01.momar.local"

.PARAMETER SccmServer
    Hostname or FQDN of the SCCM management point for connectivity testing (TCP port 445).
    Default: "sccm.momar.local"

.PARAMETER OrgName
    Value written to the built-in SCCM variable OSDRegisteredOrgName.
    Default: "Momar Tech"

.PARAMETER Software
    Array of software entries for checkbox generation.
    Format per entry: "DisplayName|TaskSequenceVariableName|DefaultChecked"
    Example: @("Cisco AnyConnect VPN|App_CiscoAnyConnect|true","7-Zip|App_7Zip|false")

.EXAMPLE
    .\DeploymentWizard.ps1

    Runs with all Momar Tech defaults — auth against momar.local,
    LDAP search from OU=Domain Computers,DC=Momar,DC=local.

.EXAMPLE
    .\DeploymentWizard.ps1 -CompanyName "Contoso Ltd" -CompanyShort "CT" `
        -Department "Infrastructure" -DomainName "contoso.com" `
        -SearchBase "OU=Workstations,DC=contoso,DC=com" `
        -DomainController "dc01.contoso.com" -SccmServer "sccm.contoso.com" `
        -OrgName "Contoso Ltd" `
        -Software @("Google Chrome|App_Chrome|true","Mozilla Firefox|App_Firefox|true","7-Zip|App_7Zip|false")

    Fully customized deployment for Contoso Ltd with three software options.

.NOTES
    File Name      : DeploymentWizard.ps1
    Version        : 1.0
    Author         : IT Operations, Momar Tech
    Requirements   : PowerShell 5.1+, .NET Framework 4.6.2+, AD module optional
    WinPE Support   : Requires WinPE-PowerShell, WinPE-NetFX

    Architecture   : Single-file — XAML, functions, and event handlers in one script
    UI Framework   : WPF (Windows Presentation Foundation) via XAML embedded string
    Auth Method    : System.DirectoryServices.AccountManagement.PrincipalContext
    LDAP Method    : System.DirectoryServices.Protocols.LdapConnection (pure .NET, no ADSI COM)
    SCCM Output    : COM Object → Microsoft.SMS.TSEnvironment

    Security Notes  :
      - Password stored in $script:JoinPass as plaintext (required by SCCM COM interface)
      - Password masked in all UI output and logs
      - Max 5 failed authentication attempts before lockout
      - Credentials never persisted to disk

    Exit Codes:
      0 = Deployment wizard completed successfully
      Non-zero = Error or cancellation (handled by wrapper script)

.LINK
    README.md — User-facing documentation and setup guide
    Start-DeploymentWizard.ps1 — SCCM Task Sequence wrapper script
#>
param(
    [string]$CompanyName    = "Momar Tech",                                    # Org name in UI title/header
    [string]$CompanyShort   = "MT",                                            # 2-3 char logo badge code
    [string]$Department     = "IT Operations",                                 # Dept name in header/footer
    [string]$DomainName     = "momar.local",                                   # AD domain FQDN
    [string]$SearchBase     = "OU=Domain Computers,DC=Momar,DC=local",         # LDAP root OU DN
    [string]$DomainController = "dc01.momar.local",                            # DC for auth/LDAP
    [string]$SccmServer     = "sccm.momar.local",                              # SCCM MP hostname
    [string]$OrgName        = "Momar Tech",                                    # OSDRegisteredOrgName value
    [string[]]$Software     = @("Cisco AnyConnect VPN|App_CiscoAnyConnect|true"),  # Software list
    [string]$DefaultLanguage = "en-US"                                         # OS language (en-US/ar-SA)
)

################################################################################
#  INITIALIZATION
#  Load WPF assemblies, assign script-scoped variables, and parse software config.
#  Software format: "DisplayName|TaskSequenceVariableName|DefaultState"
#  - DisplayName : shown on checkbox label
#  - TSVar       : SCCM variable name (e.g. App_Chrome)
#  - DefaultState: "true" = checked by default, anything else = unchecked
################################################################################
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.DirectoryServices
Add-Type -AssemblyName System.DirectoryServices.Protocols

$script:Co = $CompanyName
$script:CoShort = $CompanyShort
$script:Dept = $Department
$script:Domain = $DomainName
$script:SB = $SearchBase
$script:DC = $DomainController
$script:SCCM = $SccmServer
$script:Org = $OrgName
$script:Lang = $DefaultLanguage
$script:SoftwareItems = foreach ($s in $Software) {
    $p = $s -split '\|', 3
    @{ Name = $p[0]; TSVar = $p[1]; Default = ($p[2] -eq 'true') }
}
$script:Ver = "v1.0"

$hdrTitle = "Computer Deployment Wizard"
$hdrSub = "$CompanyName | $Department"
$ftrText = "v1.0 | $CompanyName - $Department"

################################################################################
#  EMBEDDED XAML UI DEFINITION
#  PowerShell variable interpolation ($var, $($expr)) resolves before parsing.
#  Layout: Header (Navy bar) → Scrollable 2-col body → Footer (action bar)
#  Left column : Auth card, Computer Name card, OU Browser card
#  Right column: Summary, Software, Message Center
#
#  Design tokens defined in Window.Resources:
#    - DropShadowEffect x:Key="Shadow*" — button shadows by color
#    - SolidColorBrush x:Key="*" — palette colors (Navy, Gold, Green, etc.)
#    - Style x:Key="Btn*" — button variants (Primary, Blue, Green, Red, Flat)
#    - Style x:Key="Card" — card container with border, radius, shadow
#    - Style x:Key="Grid*" — DataGrid header, row, cell styling
################################################################################
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Name="MainWindow"
        Title="$CompanyName - $hdrTitle"
        Height="780" Width="900"
        WindowStartupLocation="CenterScreen"
        Topmost="True"
        FontFamily="Segoe UI" FontSize="12"
        Background="#F6F8FB"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <DropShadowEffect x:Key="ShadowPrimary" BlurRadius="10" ShadowDepth="0" Opacity="0.55" Color="#9FAEF7"/>
        <DropShadowEffect x:Key="ShadowBlue"   BlurRadius="10" ShadowDepth="0" Opacity="0.55" Color="#8FB4FF"/>
        <DropShadowEffect x:Key="ShadowGreen"  BlurRadius="10" ShadowDepth="0" Opacity="0.55" Color="#9FD7B8"/>
        <DropShadowEffect x:Key="ShadowRed"    BlurRadius="10" ShadowDepth="0" Opacity="0.55" Color="#F7C4C4"/>
        <DropShadowEffect x:Key="CardShadow"   BlurRadius="12" ShadowDepth="2" Opacity="0.10" Color="#102A43"/>
        <SolidColorBrush x:Key="Navy"        Color="#031926"/>
        <SolidColorBrush x:Key="Gold"        Color="#C9A23D"/>
        <SolidColorBrush x:Key="GoldHover"   Color="#D4B04F"/>
        <SolidColorBrush x:Key="Green"       Color="#28A745"/>
        <SolidColorBrush x:Key="GreenBg"     Color="#ECFDF3"/>
        <SolidColorBrush x:Key="Red"         Color="#DC3545"/>
        <SolidColorBrush x:Key="RedBg"       Color="#FEF2F2"/>
        <SolidColorBrush x:Key="Orange"      Color="#F59E0B"/>
        <SolidColorBrush x:Key="OrangeBg"    Color="#FFFBEB"/>
        <SolidColorBrush x:Key="Blue"        Color="#3B82F6"/>
        <SolidColorBrush x:Key="SoftBlue"    Color="#EEF2FF"/>
        <SolidColorBrush x:Key="AccentBlue"  Color="#1D4ED8"/>
        <SolidColorBrush x:Key="SoftGreen"   Color="#ECFDF3"/>
        <SolidColorBrush x:Key="AccentGreen" Color="#166534"/>
        <SolidColorBrush x:Key="SoftRed"     Color="#FEF2F2"/>
        <SolidColorBrush x:Key="AccentRed"   Color="#991B1B"/>
        <SolidColorBrush x:Key="CardBg"      Color="#FFFFFF"/>
        <SolidColorBrush x:Key="AuthBg"      Color="#FEFCF7"/>
        <SolidColorBrush x:Key="PageBg"      Color="#F6F8FB"/>
        <SolidColorBrush x:Key="Border"      Color="#E4E9F0"/>
        <SolidColorBrush x:Key="BorderDark"  Color="#D7E0EC"/>
        <SolidColorBrush x:Key="TextDark"    Color="#1F2D3A"/>
        <SolidColorBrush x:Key="TextMid"     Color="#475467"/>
        <SolidColorBrush x:Key="TextLight"   Color="#5F6B7A"/>
        <SolidColorBrush x:Key="TextMuted"   Color="#7C8BA1"/>
        <SolidColorBrush x:Key="TextWhite"   Color="#FFFFFF"/>
        <Style x:Key="BtnBase" TargetType="Button">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="8,0"/>
            <Setter Property="Height" Value="28"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Effect" Value="{x:Null}"/>
                    <Setter Property="Background" Value="#ECEFF3"/>
                    <Setter Property="Foreground" Value="#9CA3AF"/>
                    <Setter Property="Opacity" Value="0.75"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="Button" BasedOn="{StaticResource BtnBase}"/>
        <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background" Value="#9FAEF7"/><Setter Property="Foreground" Value="#1F2D3A"/>
            <Setter Property="Effect" Value="{StaticResource ShadowPrimary}"/>
        </Style>
        <Style x:Key="BtnBlue" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background" Value="#8FB4FF"/><Setter Property="Foreground" Value="#1F2D3A"/>
            <Setter Property="Effect" Value="{StaticResource ShadowBlue}"/>
        </Style>
        <Style x:Key="BtnGreen" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background" Value="#9FD7B8"/><Setter Property="Foreground" Value="#1F2D3A"/>
            <Setter Property="Effect" Value="{StaticResource ShadowGreen}"/>
        </Style>
        <Style x:Key="BtnRed" TargetType="Button" BasedOn="{StaticResource BtnBase}">
            <Setter Property="Background" Value="#F7C4C4"/><Setter Property="Foreground" Value="#1F2D3A"/>
            <Setter Property="Effect" Value="{StaticResource ShadowRed}"/>
        </Style>
        <Style x:Key="BtnFlat" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="10,0"/>
            <Setter Property="Height" Value="26"/><Setter Property="FontSize" Value="11.5"/><Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#F0F2F5"/></Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardBg}"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="5"/>
            <Setter Property="Padding" Value="12,10"/><Setter Property="Margin" Value="0,0,0,8"/>
            <Setter Property="Effect" Value="{StaticResource CardShadow}"/>
        </Style>
        <Style x:Key="AccentBar" TargetType="Border"><Setter Property="Width" Value="5"/><Setter Property="CornerRadius" Value="3"/><Setter Property="Margin" Value="0,0,8,0"/></Style>
        <Style x:Key="H3" TargetType="TextBlock"><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="FontSize" Value="12.5"/><Setter Property="Foreground" Value="{StaticResource TextDark}"/></Style>
        <Style x:Key="Lbl" TargetType="TextBlock"><Setter Property="FontSize" Value="11.5"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="{StaticResource TextMid}"/><Setter Property="Margin" Value="0,0,0,3"/></Style>
        <Style x:Key="Tb" TargetType="TextBox"><Setter Property="Height" Value="28"/><Setter Property="FontSize" Value="12"/><Setter Property="Padding" Value="6,3"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
        <Style x:Key="Pb" TargetType="PasswordBox"><Setter Property="Height" Value="28"/><Setter Property="FontSize" Value="12"/><Setter Property="Padding" Value="6,3"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/><Setter Property="BorderThickness" Value="1"/></Style>
        <Style x:Key="GridHeaderStyle" TargetType="{x:Type DataGridColumnHeader}">
            <Setter Property="Background" Value="#EAF2FF"/>
            <Setter Property="Foreground" Value="{StaticResource TextDark}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
        </Style>
        <Style x:Key="GridRowStyle" TargetType="{x:Type DataGridRow}">
            <Setter Property="MinHeight" Value="26"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#F0F2F5"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#F4F8FF"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#DCEBFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="GridCellStyle" TargetType="{x:Type DataGridCell}">
            <Setter Property="Padding" Value="6,3"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Foreground" Value="{StaticResource TextDark}"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
        </Style>
        <Style x:Key="TrimCell" TargetType="{x:Type TextBlock}">
            <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="ToolTip" Value="{Binding RelativeSource={RelativeSource Self}, Path=Text}"/>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="52"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="36"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="{StaticResource Navy}">
            <Grid Margin="14,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Border Grid.Column="0" Width="30" Height="30" CornerRadius="6" Margin="0,0,10,0" Background="{StaticResource Gold}">
                    <TextBlock Text="$($script:CoShort)" FontSize="13" FontWeight="Bold" Foreground="{StaticResource Navy}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="$hdrTitle" FontSize="16" FontWeight="Bold" Foreground="{StaticResource TextWhite}"/>
                    <TextBlock Text="$hdrSub" FontSize="10" Foreground="#7C8BA1" Margin="0,1,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse Name="StatusDot" Width="7" Height="7" Fill="{StaticResource Orange}" Margin="0,0,6,0"/>
                    <TextBlock Name="StatusHeader" Text="Ready" FontSize="11" Foreground="{StaticResource Orange}"/>
                </StackPanel>
            </Grid>
        </Border>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Background="{StaticResource PageBg}">
            <Grid Margin="10,8,10,8">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="10"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- LEFT -->
                <StackPanel Grid.Column="0">
                    <!-- AUTH -->
                    <Border Style="{StaticResource Card}" Background="{StaticResource AuthBg}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                    <Border Style="{StaticResource AccentBar}" Background="{StaticResource Gold}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                        <StackPanel><TextBlock Text="Authentication" Style="{StaticResource H3}"/><TextBlock Text="Enter domain credentials to proceed" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,0,0,0"/></StackPanel>
                            </DockPanel>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Username" Style="{StaticResource Lbl}" VerticalAlignment="Center" Margin="0,0,10,0" Width="55"/>
                                <TextBox Grid.Row="0" Grid.Column="1" Name="UsernameBox" Style="{StaticResource Tb}" Margin="0,0,0,5"/>
                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Password" Style="{StaticResource Lbl}" VerticalAlignment="Center" Margin="0,0,10,0" Width="55"/>
                                <PasswordBox Grid.Row="1" Grid.Column="1" Name="PasswordBox" Style="{StaticResource Pb}" Margin="0,0,0,5"/>
                            </Grid>
                            <Border Name="AuthBanner" CornerRadius="4" Padding="8,6" Margin="0,0,0,6" Visibility="Collapsed">
                                <DockPanel><TextBlock Name="AuthIcon" DockPanel.Dock="Left" FontSize="13" Margin="0,0,6,0" Text="" FontWeight="Bold"/><TextBlock Name="AuthText" FontSize="11.5" TextWrapping="Wrap"/></DockPanel>
                            </Border>
                            <Button Name="LoginBtn" Content="Sign In" Style="{StaticResource BtnBlue}"/>
                        </StackPanel>
                    </Border>
                    <!-- COMPUTER NAME -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="Computer Name" Style="{StaticResource H3}"/><TextBlock Text="Enter the new computer name" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <TextBox Name="ComputerNameBox" Style="{StaticResource Tb}" MaxLength="15" Text=""/>
                            <TextBlock Text="Maximum 15 characters (NetBIOS limit)" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="4,4,0,0"/>
                        </StackPanel>
                    </Border>
                    <!-- LANGUAGE -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="System Language" Style="{StaticResource H3}"/><TextBlock Text="Select the operating system language" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <StackPanel Orientation="Horizontal" Margin="4,2">
                                <RadioButton Name="LangEnglish" Content="English" Margin="0,0,20,0" FontSize="11.5" Foreground="{StaticResource AccentBlue}" FontWeight="SemiBold" GroupName="LangGroup" IsChecked="True"/>
                                <RadioButton Name="LangArabic"  Content="Arabic"  FontSize="11.5" Foreground="{StaticResource AccentBlue}" FontWeight="SemiBold" GroupName="LangGroup"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                    <!-- OU -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Gold}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="Target Organizational Unit" Style="{StaticResource H3}"/><TextBlock Text="Search and select the destination OU" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <Border BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="5" Background="#FFFFFF" Margin="0,0,0,8">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="&#x1F50D;" FontSize="12" Margin="10,0,6,0" VerticalAlignment="Center" Foreground="{StaticResource TextMuted}"/>
                                    <TextBox Grid.Column="1" Name="OUSearchBox" BorderThickness="0" Background="Transparent" Height="26" FontSize="11.5" Padding="3,0" VerticalContentAlignment="Center"/>
                                    <Button Grid.Column="2" Name="OUSearchBtn" Content="Search" Width="50" Height="23" Margin="2" Style="{StaticResource BtnBlue}" FontSize="10.5"/>
                                </Grid>
                            </Border>
                            <Border BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="5" Background="#FFFFFF">
                                <DataGrid
                                    Name="OUDataGrid"
                                    AutoGenerateColumns="False"
                                    CanUserAddRows="False"
                                    IsReadOnly="True"
                                    SelectionMode="Single"
                                    SelectionUnit="FullRow"
                                    HeadersVisibility="Column"
                                    GridLinesVisibility="Horizontal"
                                    HorizontalGridLinesBrush="#F0F2F5"
                                    VerticalGridLinesBrush="#FFFFFF"
                                    RowBackground="#FFFFFF"
                                    AlternatingRowBackground="#F8FBFF"
                                    Background="Transparent"
                                    BorderThickness="0"
                                    Height="170"
                                    ScrollViewer.HorizontalScrollBarVisibility="Auto"
                                    ColumnHeaderStyle="{StaticResource GridHeaderStyle}"
                                    RowStyle="{StaticResource GridRowStyle}"
                                    CellStyle="{StaticResource GridCellStyle}">
                                    <DataGrid.Columns>
                                            <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="130" ElementStyle="{StaticResource TrimCell}"/>
                                            <DataGridTextColumn Header="Description" Binding="{Binding Description}" Width="170" ElementStyle="{StaticResource TrimCell}"/>
                                            <DataGridTextColumn Header="OU Path" Binding="{Binding FriendlyPath}" Width="260" ElementStyle="{StaticResource TrimCell}"/>
                                    </DataGrid.Columns>
                                </DataGrid>
                            </Border>
                            <Border Name="OUSelectedInfo" Visibility="Collapsed" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="8,5" Margin="0,6,0,0">
                                <DockPanel>
                                    <Border DockPanel.Dock="Left" Width="5" Height="5" Background="{StaticResource AccentBlue}" CornerRadius="3" Margin="0,0,6,0"/>
                                    <StackPanel><TextBlock Name="OUSelectedName" FontSize="11.5" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/><TextBlock Name="OUSelectedPath" FontSize="9.5" Foreground="{StaticResource TextLight}" TextTrimming="CharacterEllipsis"/></StackPanel>
                                </DockPanel>
                            </Border>
                            <DockPanel Margin="0,4,0,0">
                                <TextBlock Name="OUMessage" DockPanel.Dock="Left" FontSize="10.5" Foreground="{StaticResource TextMuted}"/>
                                <TextBlock Name="OUCount" DockPanel.Dock="Right" FontSize="10.5" Foreground="{StaticResource TextMuted}"/>
                            </DockPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- RIGHT -->
                <StackPanel Grid.Column="2">
                    <!-- SUMMARY -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Gold}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <TextBlock Text="Deployment Summary" Style="{StaticResource H3}" VerticalAlignment="Center"/>
                            </DockPanel>
                            <Border Background="#F8FAFC" CornerRadius="5" Padding="10,6">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="72"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Computer:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="11"/>
                                    <Border Grid.Row="0" Grid.Column="1" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumComputer" Text="---" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/></Border>
                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Target OU:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="11"/>
                                    <Border Grid.Row="1" Grid.Column="1" Background="#FFFFFF" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumOU" Text="---" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource TextDark}" TextTrimming="CharacterEllipsis"/></Border>
                                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Domain:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="11"/>
                                    <Border Grid.Row="2" Grid.Column="1" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumDomain" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/></Border>
                                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Software:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="11"/>
                                    <Border Grid.Row="3" Grid.Column="1" Background="#FFFFFF" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumApps" Text="---" FontSize="11" Foreground="{StaticResource TextDark}"/></Border>
                                    <TextBlock Grid.Row="4" Grid.Column="0" Text="Language:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="11"/>
                                    <Border Grid.Row="4" Grid.Column="1" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumLang" Text="English" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/></Border>
                                    <TextBlock Grid.Row="5" Grid.Column="0" Text="User:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" FontSize="11"/>
                                    <Border Grid.Row="5" Grid.Column="1" Background="{StaticResource SoftGreen}" CornerRadius="4" Padding="6,3"><TextBlock Name="SumUser" Text="Not signed in" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource AccentGreen}"/></Border>
                                </Grid>
                            </Border>
                        </StackPanel>
                    </Border>
                    <!-- SOFTWARE -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="Software Installation" Style="{StaticResource H3}"/><TextBlock Text="Select software to install" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <Border Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="8,6"><StackPanel Name="SoftwarePanel"/></Border>
                        </StackPanel>
                    </Border>
                    <!-- MESSAGE CENTER -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <TextBlock Text="Message Center" Style="{StaticResource H3}" VerticalAlignment="Center"/>
                            </DockPanel>
                            <Border Background="#1F2D3A" BorderBrush="#2D3F52" BorderThickness="1" CornerRadius="4" Padding="2">
                                <RichTextBox x:Name="LogBox" Height="150" IsReadOnly="True" Background="Transparent" Foreground="#C8D6E5" BorderThickness="0" FontFamily="Consolas" FontSize="11" VerticalScrollBarVisibility="Auto" Padding="6,4"/>
                            </Border>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>
        </ScrollViewer>

        <Border Grid.Row="2" Background="#FFFFFF" BorderBrush="{StaticResource Border}" BorderThickness="0,1,0,0">
            <Grid Margin="12,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Button Grid.Column="0" Name="RefreshBtn" Content="Refresh" Width="65" Margin="0,0,6,0" Style="{StaticResource BtnFlat}"/>
                <TextBlock Grid.Column="1" FontSize="10" Foreground="{StaticResource TextMuted}" VerticalAlignment="Center" Text="$ftrText"/>
                <Button Grid.Column="2" Name="CancelBtn" Content="Cancel" Width="65" Margin="0,0,6,0" Style="{StaticResource BtnFlat}"/>
                <Button Grid.Column="3" Name="FinishBtn" Content="Deploy" Width="90" Style="{StaticResource BtnGreen}"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

################################################################################
#  XAML PARSE & WPF CONTROL BINDING
#  Load XAML → WPF Window, then bind all named controls to PowerShell variables.
#  Auth state tracking: $script:IsLoggedIn, $script:JoinPass, $script:AuthAttempts
################################################################################
$reader = New-Object System.Xml.XmlNodeReader $XAML
$Window = [Windows.Markup.XamlReader]::Load($reader)

$UsernameBox = $Window.FindName("UsernameBox")
$PasswordBox = $Window.FindName("PasswordBox")
$LoginBtn = $Window.FindName("LoginBtn")
$AuthBanner = $Window.FindName("AuthBanner")
$AuthIcon = $Window.FindName("AuthIcon")
$AuthText = $Window.FindName("AuthText")
$ComputerNameBox = $Window.FindName("ComputerNameBox")
$OUSearchBox = $Window.FindName("OUSearchBox")
$OUSearchBtn = $Window.FindName("OUSearchBtn")
$OUDataGrid = $Window.FindName("OUDataGrid")
$OUSelectedInfo = $Window.FindName("OUSelectedInfo")
$OUSelectedName = $Window.FindName("OUSelectedName")
$OUSelectedPath = $Window.FindName("OUSelectedPath")
$OUMessage = $Window.FindName("OUMessage")
$OUCount = $Window.FindName("OUCount")
$StatusDot = $Window.FindName("StatusDot")
$StatusHeader = $Window.FindName("StatusHeader")
$SumComputer = $Window.FindName("SumComputer")
$SumOU = $Window.FindName("SumOU")
$SumDomain = $Window.FindName("SumDomain")
$SumApps = $Window.FindName("SumApps")
$SumUser = $Window.FindName("SumUser")
$SumLang = $Window.FindName("SumLang")
$LangEnglish = $Window.FindName("LangEnglish")
$LangArabic = $Window.FindName("LangArabic")
$SoftwarePanel = $Window.FindName("SoftwarePanel")
$FinishBtn = $Window.FindName("FinishBtn")
$CancelBtn = $Window.FindName("CancelBtn")
$RefreshBtn = $Window.FindName("RefreshBtn")
$LogBox = $Window.FindName("LogBox")
$script:IsLoggedIn = $false
$script:JoinPass = ""
$script:AuthAttempts = 0
$script:MaxAuthAttempts = 5

################################################################################
#  DYNAMIC SOFTWARE CHECKBOX GENERATION
#  Iterates $script:SoftwareItems, creates WPF CheckBox per entry.
#  Each checkbox tracks its SCCM Task Sequence variable name in .Tag.
#  Checked/Unchecked events trigger Update-Summary to refresh the summary panel.
################################################################################
$script:SoftCbs = @()
foreach ($item in $script:SoftwareItems) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $item.Name
    $cb.FontSize = 13
    $cb.Margin = New-Object System.Windows.Thickness(4, 3, 4, 3)
    $cb.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString("#1D4ED8"))
    $cb.IsChecked = $item.Default
    $cb.Tag = $item.TSVar
    $cb.Add_Checked({ Update-Summary })
    $cb.Add_Unchecked({ Update-Summary })
    $SoftwarePanel.Children.Add($cb) | Out-Null
    $script:SoftCbs += $cb
}

################################################################################
#  FROZEN WPF BRUSHES
#  Pre-created and frozen for performance — immutable brushes are thread-safe
#  and avoid repeated color parsing in event handlers and property setters.
################################################################################
<#
.SYNOPSIS
    Creates a frozen WPF SolidColorBrush for the given hex color.
.DESCRIPTION
    Parses the hex color string, creates a SolidColorBrush, and freezes it
    for thread-safe immutable usage. Prevents repeated parsing overhead.
.PARAMETER Hex
    Color in #RRGGBB format.
.EXAMPLE
    $navy = New-Brush "#031926"
#>
function New-Brush {
    param([string]$Hex)
    $c = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $b = New-Object Windows.Media.SolidColorBrush $c
    $b.Freeze()
    return $b
}
$brush = @{
    Navy         = New-Brush "#031926"
    Gold         = New-Brush "#C9A23D"
    Red          = New-Brush "#DC3545"
    RedBg        = New-Brush "#FEF2F2"
    Green        = New-Brush "#28A745"
    GreenBg      = New-Brush "#ECFDF3"
    Orange       = New-Brush "#F59E0B"
    OrangeBg     = New-Brush "#FFFBEB"
    TextDark     = New-Brush "#1F2D3A"
    TextMid      = New-Brush "#475467"
    TextLight    = New-Brush "#5F6B7A"
    TextMuted    = New-Brush "#7C8BA1"
    AccentBlue   = New-Brush "#1D4ED8"
    AccentRed    = New-Brush "#991B1B"
    AccentGreen  = New-Brush "#166534"
}

################################################################################
#  MESSAGE CENTER LOGGING
#
#  Write-UiLog — Thread-safe colored log entries in the Message Center panel.
#  Uses WPF Dispatcher.Invoke for cross-thread safety since log calls may
#  originate from background operations. Each entry prepended with [LEVEL].
#
#  Color scheme:
#    INFO    #808FA7 (muted blue-gray)
#    SUCCESS #28A745 (green)
#    WARNING #F59E0B (amber)
#    ERROR   #DC3545 (red)
################################################################################
function Write-UiLog {
    param([string]$M, [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')][string]$L = 'INFO')
    if (-not $LogBox) { return }
    $c = switch ($L) {
        'INFO'    { '#808FA7' }
        'SUCCESS' { '#28A745' }
        'WARNING' { '#F59E0B' }
        'ERROR'   { '#DC3545' }
    }
    $t = "[$L] $M"
    $LogBox.Dispatcher.Invoke([action] {
            $r = New-Object Windows.Documents.Run $t; $r.Foreground = New-Brush $c
            $p = New-Object Windows.Documents.Paragraph; $p.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)
            $p.Inlines.Add($r); $LogBox.Document.Blocks.Add($p); $LogBox.ScrollToEnd()
        })
}

################################################################################
#  UI HELPERS
#
#  Test-TcpReach            — Asynchronous TCP connection test (LDAP/Kerberos ports)
#  ConvertTo-FriendlyOUPath — DN → Human-readable path (e.g. "Lab / IT / Domain")
################################################################################
<#
.SYNOPSIS
    Tests TCP connectivity to specified ports using async connect with timeout.
.DESCRIPTION
    Attempts TCP connection on each port in priority order.
    Uses BeginConnect/EndConnect with configurable timeout for fast results.
    Default ports: 389 (LDAP) and 88 (Kerberos) — standard AD services.
.PARAMETER H
    Target hostname or IP address.
.PARAMETER P
    Ports to test in order. Default: @(389, 88)
.PARAMETER TO
    Timeout per port in milliseconds. Default: 1500
.EXAMPLE
        Test-TcpReach -H $DomainController -P @(389, 88) -TO 1000
    Returns $true if port 389 or 88 responds within 1000ms.
#>
function Test-TcpReach {
    param([string]$H, [int[]]$P = @(389, 88), [int]$TO = 1500)
    foreach ($p in $P) {
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $ar = $c.BeginConnect($H, $p, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne($TO, $false)) {
                try { $c.EndConnect($ar) } catch {}
                if ($c.Connected) {
                    $c.Dispose()
                    return $true
                }
            }
            $c.Dispose()
        }
        catch {
            if ($c) {
                try { $c.Dispose() } catch {}
            }
        }
    }
    return $false
}
<#
.SYNOPSIS
    Converts an LDAP Distinguished Name to a human-readable hierarchical path.
.DESCRIPTION
    Extracts OU= components from DN, reverses order (most-specific first),
    and joins with " / " separator.
.EXAMPLE
    ConvertTo-FriendlyOUPath "OU=Lab,OU=IT,OU=Domain Computers,DC=Momar,DC=local"
    Returns: "Domain Computers / IT / Lab"
#>
function ConvertTo-FriendlyOUPath {
    param([string]$DN)
    if ([string]::IsNullOrWhiteSpace($DN)) {
        return ""
    }
    $parts = @($DN -split ',' | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_.Substring(3) })
    if ($parts.Count -eq 0) {
        return $DN
    }
    [array]::Reverse($parts)
    return ($parts -join ' / ')
}

################################################################################
#  ORGANIZATIONAL UNIT BROWSER
#
#  Update-OUList   — LDAP query via LdapConnection (pure .NET, works in WinPE).
#                    Caches results in $script:OUData (Name, Description, DN, FriendlyPath).
#                    Uses authenticated bind when credentials are available.
#  Filter-OUDataGrid — Client-side live search across Name, Description,
#                       FriendlyPath, and DN fields.
################################################################################
function Update-OUList {
    if (-not $OUDataGrid) { return }

    $OUMessage.Text = "Loading..."
    $OUMessage.Foreground = $brush.TextMuted
    $OUSelectedInfo.Visibility = "Collapsed"
    $OUDataGrid.ItemsSource = $null

    $ldapConn = $null
    try {
        $ldapId = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($script:DC, 389)
        $ldapConn = New-Object System.DirectoryServices.Protocols.LdapConnection($ldapId)
        $ldapConn.SessionOptions.ProtocolVersion = 3
        $ldapConn.SessionOptions.ReferralChasing = [System.DirectoryServices.Protocols.ReferralChasingOptions]::All
        $ldapConn.Timeout = [TimeSpan]::FromSeconds(15)

        if ($script:IsLoggedIn -and $script:JoinPass) {
            $cred = New-Object System.Net.NetworkCredential($UsernameBox.Text, $script:JoinPass, $script:Domain)
            $ldapConn.Bind($cred)
            Write-UiLog "LDAP bind: authenticated as $($UsernameBox.Text)" "INFO"
        }
        else {
            $ldapConn.Bind()
            Write-UiLog "LDAP bind: anonymous (sign in for better results)" "INFO"
        }

        $filter = "(objectClass=organizationalUnit)"
        $scope = [System.DirectoryServices.Protocols.SearchScope]::Subtree

        $req = New-Object System.DirectoryServices.Protocols.SearchRequest($script:SB, $filter, $scope)
        $req.SizeLimit = 0

        $resp = $ldapConn.SendRequest($req)
        $sr = [System.DirectoryServices.Protocols.SearchResponse]$resp

        $script:OUData = @()
        for ($i = 0; $i -lt $sr.Entries.Count; $i++) {
            $entry = $sr.Entries[$i]
            $a = $entry.Attributes
            if (-not $a) { continue }
            
            try { $names = $a["name"].GetValues([string]) } catch { $names = @() }
            try { $dns   = $a["distinguishedname"].GetValues([string]) } catch { $dns = @() }
            
            if ($names.Count -gt 0 -and $dns.Count -gt 0) {
                $desc = ""
                try {
                    $descVals = $a["description"].GetValues([string])
                    if ($descVals.Count -gt 0) { $desc = $descVals[0] }
                } catch {}
                $script:OUData += [PSCustomObject]@{
                    Name         = $names[0]
                    Description  = $desc
                    DN           = $dns[0]
                    FriendlyPath = ConvertTo-FriendlyOUPath($dns[0])
                }
            }
        }
        Write-UiLog "LDAP search returned $($sr.Entries.Count) entries, parsed $($script:OUData.Count)" "INFO"

        $script:OUData = @($script:OUData | Sort-Object Name)
        if ($script:OUData.Count -eq 0) {
            $OUMessage.Text = "No OUs found"
            $OUMessage.Foreground = $brush.Orange
            $OUCount.Text = ""
            return
        }

        $OUDataGrid.ItemsSource = $script:OUData
        $OUMessage.Text = "Ready"
        $OUMessage.Foreground = $brush.TextMuted
        $OUCount.Text = "{0} OUs" -f $script:OUData.Count
        Write-UiLog "Loaded $($script:OUData.Count) OUs from $($script:DC)" "INFO"
    }
    catch {
        if ($script:IsLoggedIn) {
            $OUMessage.Text = "Cannot load OUs"
            $OUMessage.Foreground = $brush.Red
            Write-UiLog "LDAP error: $($_.Exception.Message)" "ERROR"
        }
        else {
            $OUMessage.Text = "Sign in to load OUs"
            $OUMessage.Foreground = $brush.Orange
            Write-UiLog "LDAP: sign in to browse OUs" "INFO"
        }
        $OUCount.Text = ""
    }
    finally {
        if ($ldapConn) {
            try { $ldapConn.Dispose() } catch {}
        }
    }
}
function Filter-OUDataGrid {
    param([string]$F)
    if (-not $OUDataGrid) { return }

    if ([string]::IsNullOrWhiteSpace($F)) {
        $OUDataGrid.ItemsSource = $script:OUData
    }
    else {
        $OUDataGrid.ItemsSource = @($script:OUData | Where-Object {
            $_.Name -like "*$F*" -or
            $_.Description -like "*$F*" -or
            $_.FriendlyPath -like "*$F*" -or
            $_.DN -like "*$F*"
        })
    }

    $count = @($OUDataGrid.ItemsSource).Count
    $OUCount.Text = "{0} / {1} OUs" -f $count, $script:OUData.Count
    $OUMessage.Text = if ($count -eq 0 -and $F) { "No match" } else { "Ready" }
    $OUMessage.Foreground = if ($count -eq 0 -and $F) { $brush.Orange } else { $brush.TextMuted }
}

################################################################################
#  DEPLOYMENT SUMMARY
#  Update-Summary — Refreshes all five summary pills (Computer, OU, Domain,
#  Software, User) reflecting current UI state. Called by all interactive events.
################################################################################
function Update-Summary {
    $SumComputer.Text = if ($ComputerNameBox.Text) { $ComputerNameBox.Text } else { "---" }
    $SumComputer.Parent.Background = if ($ComputerNameBox.Text) { $brush.GreenBg } else { $brush.RedBg }

    $sel = $OUDataGrid.SelectedItem
    $SumOU.Text = if ($sel -and $sel.DN) { $sel.Name } else { "---" }
    $SumOU.Parent.Background = if ($sel -and $sel.DN) { $brush.GreenBg } else { $brush.RedBg }

    $SumDomain.Text = $script:Domain
    $SumDomain.Parent.Background = $brush.GreenBg

    $SumLang.Text = if ($LangArabic.IsChecked) { "Arabic" } else { "English" }
    $SumLang.Parent.Background = $brush.GreenBg

    $checkedApps = @($script:SoftCbs | Where-Object { $_.IsChecked } | ForEach-Object { $_.Content })
    $SumApps.Text = if ($checkedApps.Count -gt 0) { ($checkedApps -join ", ") } else { "None" }
    $SumApps.Parent.Background = if ($checkedApps.Count -gt 0) { $brush.GreenBg } else { $brush.RedBg }

    if ($script:IsLoggedIn -and $UsernameBox.Text) {
        $SumUser.Text = $UsernameBox.Text
        $SumUser.Foreground = $brush.AccentGreen
        $SumUser.Parent.Background = $brush.GreenBg
    }
    else {
        $SumUser.Text = "Not signed in"
        $SumUser.Foreground = $brush.TextMuted
        $SumUser.Parent.Background = $brush.RedBg
    }
}

################################################################################
#  AUTHENTICATION BANNER
#
#  Show-AuthBanner — Displays color-coded authentication feedback below Sign In.
#    Types: Error (red), Success (green), Warning (amber)
#    Each type has unique border, background, text color, and icon.
#  Hide-AuthBanner — Collapses the banner (clears on re-auth attempt).
################################################################################
function Show-AuthBanner {
    param([string]$Type, [string]$M)
    if (-not $AuthBanner -or -not $AuthIcon -or -not $AuthText) { return }

    $borderC = switch ($Type) {
        "Error"   { $brush.Red }
        "Success" { $brush.Green }
        "Warning" { $brush.Orange }
    }
    $bgC = switch ($Type) {
        "Error"   { $brush.RedBg }
        "Success" { $brush.GreenBg }
        "Warning" { $brush.OrangeBg }
    }
    $txtC = switch ($Type) {
        "Error"   { $brush.AccentRed }
        "Success" { $brush.AccentGreen }
        "Warning" { New-Brush "#92400E" }
    }
    $icon = switch ($Type) {
        "Error"   { "X" }
        "Success" { [char]0x2713 }
        "Warning" { "!" }
    }

    $AuthBanner.Background = $bgC
    $AuthBanner.BorderBrush = $borderC
    $AuthBanner.BorderThickness = New-Object System.Windows.Thickness(1)
    $AuthIcon.Foreground = $borderC
    $AuthIcon.Text = $icon
    $AuthText.Foreground = $txtC
    $AuthText.Text = $M
    $AuthBanner.Visibility = "Visible"
}
function Hide-AuthBanner { if ($AuthBanner) { $AuthBanner.Visibility = "Collapsed" } }

################################################################################
#  CUSTOM DIALOG SYSTEM
#
#  Show-CustomDialog — Generates and displays a styled modal dialog from XAML.
#    Used for validation warnings, confirmations, and deployment results.
#    Types determine accent bar/button colors: Error, Warning, Success, Info.
################################################################################
function Show-CustomDialog {
    param([string]$Type, [string]$T, [string]$M)
    $hc = switch ($Type) { "Error" { "#DC3545" }"Warning" { "#F59E0B" }"Success" { "#28A745" }"Info" { "#3B82F6" } }
    $Title = [System.Security.SecurityElement]::Escape($T)
    $Message = [System.Security.SecurityElement]::Escape($M)
    [xml]$x = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="$Title"
    SizeToContent="WidthAndHeight"
    MinWidth="360" MaxWidth="480"
    WindowStartupLocation="CenterOwner"
    ShowInTaskbar="False"
    FontFamily="Segoe UI" FontSize="11"
    Background="#F6F8FB"
    Topmost="True"
    UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <DropShadowEffect x:Key="DlgShadow" BlurRadius="12" ShadowDepth="2" Opacity="0.10" Color="#102A43"/>
    </Window.Resources>
    <Grid Margin="10">
        <Border
            Background="White"
            BorderBrush="#E6EBF4"
            BorderThickness="1"
            CornerRadius="6"
            Effect="{StaticResource DlgShadow}">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Border Grid.Row="0" Padding="12,10,12,8" BorderBrush="#E6EBF4" BorderThickness="0,0,0,1">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Width="5" Height="22" Background="$hc" CornerRadius="3" Margin="0,0,12,0"/>
                        <TextBlock Grid.Column="1" Text="$Title" Foreground="#1F2D3A" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                    </Grid>
                </Border>
                <Border Grid.Row="1" Background="#F8FAFC" BorderBrush="#E6EBF4" BorderThickness="1" CornerRadius="5" Padding="14" Margin="16,14,16,14">
                    <TextBlock Text="$Message" Foreground="#334155" TextWrapping="Wrap" FontSize="12"/>
                </Border>
                <Border Grid.Row="2" BorderBrush="#E6EBF4" BorderThickness="0,1,0,0" Padding="0,10,0,10">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                        <Button
                            x:Name="DlgOk"
                            Content="OK"
                            Width="80" Height="26"
                            FontSize="11" FontWeight="SemiBold"
                            Cursor="Hand"
                            Background="$hc"
                            Foreground="White"
                            BorderThickness="0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="b" Property="Opacity" Value="0.85"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>
    </Grid>
</Window>
"@
    try {
        $r = New-Object System.Xml.XmlNodeReader $x
        $d = [Windows.Markup.XamlReader]::Load($r)
        $d.FindName("DlgOk").Add_Click({ $d.Close() })
        $d.Owner = $Window
        $d.ShowDialog() | Out-Null
    }
    catch {
        Write-UiLog "Dialog render failed: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show($Message, $Title, "OK", "Warning") | Out-Null
    }
}

################################################################################
#  ACTIVE DIRECTORY AUTHENTICATION
#
#  Test-ADAuthentication — Validates credentials against Active Directory.
#    Uses System.DirectoryServices.AccountManagement.PrincipalContext.
#    Returns hashtable with Success (bool) and Message (string).
#    Handles three failure modes:
#      1. Empty input         → "Please enter your username/password."
#      2. DC unreachable     → "Cannot reach domain: <domain>."
#      3. Invalid credentials → "The username or password is incorrect."
################################################################################
function Test-ADAuthentication {
    param([string]$U, [string]$P)

    if ([string]::IsNullOrWhiteSpace($U)) {
        return @{Success = $false; Message = "Please enter your username."}
    }
    if ([string]::IsNullOrWhiteSpace($P)) {
        return @{Success = $false; Message = "Please enter your password."}
    }

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop
        $ct = [System.DirectoryServices.AccountManagement.ContextType]::Domain
        $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($ct, $script:Domain)
        try {
            $ok = $ctx.ValidateCredentials($U, $P)
        }
        finally {
            $ctx.Dispose()
        }

        if ($ok) {
            return @{Success = $true; Message = "Authentication successful."}
        }
        else {
            return @{Success = $false; Message = "The username or password is incorrect."}
        }
    }
    catch {
        $m = $_.Exception.Message
        if ($m -match "server could not be contacted|not operational|RPC server") {
            return @{Success = $false; Message = "Cannot reach domain: $($script:Domain)."}
        }
        elseif ($m -match "Logon failure") {
            return @{Success = $false; Message = "Incorrect username or password."}
        }
        else {
            return @{Success = $false; Message = "Auth error: $m"}
        }
    }
}

################################################################################
#  SCCM TASK SEQUENCE VARIABLE OUTPUT
#
#  Write-SCCMVariables — Writes deployment configuration to SCCM COM TSEnvironment.
#    Built-in variables (auto-executed by SCCM):
#      OSDComputerName      → New computer hostname
#      OSDDomainName        → Target domain for join
#      OSDDomainOUName      → Target OU distinguished name
#      OSDJoinAccount       → Domain user for join (DOMAIN\username)
#      OSDJoinPassword      → Domain user password (******** in logs)
#      OSDRegisteredOrgName → Organization name
#    Custom variables (used via %VariableName% in TS steps):
#      App_*                → TRUE if checked, not set if unchecked
#
#    Returns hashtable: @{Success = $bool; Message = $string}
################################################################################
function Write-SCCMVariables {
    param(
        [string]$CN,
        [string]$OU,
        [string]$OUN,
        [string]$DN,
        [string]$JU,
        [string]$JP,
        [string]$Lang,
        [hashtable[]]$Apps
    )

    $vars = [ordered]@{
        "OSDComputerName"       = $CN
        "OSDDomainName"         = $DN
        "OSDDomainOUName"       = $OU
        "OSDJoinAccount"        = $JU
        "OSDJoinPassword"       = $JP
        "OSDRegisteredOrgName"  = $script:Org
        "OSDLanguage"           = $Lang
    }

    foreach ($a in $Apps) {
        if ($a.Checked) {
            $vars[$a.TSVar] = "TRUE"
        }
    }

    try {
        $ts = New-Object -COMObject Microsoft.SMS.TSEnvironment
        foreach ($k in $vars.Keys) {
            $ts.Value($k) = $vars[$k]
            $d = if ($k -eq "OSDJoinPassword") { "********" } else { $vars[$k] }
            Write-UiLog "TS: $k = $d" "INFO"
        }
        return @{Success = $true; Message = "All variables written to Task Sequence successfully."}
    }
    catch {
        return @{Success = $false; Message = "Not running inside a Task Sequence."}
    }
}

################################################################################
#  EVENT HANDLERS
#
#  Sign In     : Authenticate → update status dot/header → show/hide banner
#                Lockout after $script:MaxAuthAttempts (5) failed attempts
#  Enter key   : PasswordBox triggers LoginBtn click event
#  TextChanged : OU search (live filter), computer name (summary update)
#  Search btn  : OU filter execution
#  Selection   : DataGrid → show selected OU → update summary
#  Refresh     : Reload WMI device info + LDAP OU list + summary
################################################################################
$LoginBtn.Add_Click({
    Hide-AuthBanner

    if ($script:AuthAttempts -ge $script:MaxAuthAttempts) {
        Show-AuthBanner -Type Error -M "Too many failed attempts. Please wait or restart the wizard."
        $PasswordBox.Password = ""
        Write-UiLog "Auth locked: $($script:MaxAuthAttempts) attempts exceeded" "ERROR"
        return
    }

    $r = Test-ADAuthentication -U $UsernameBox.Text -P $PasswordBox.Password
    if ($r.Success) {
        $script:IsLoggedIn = $true
        $script:JoinPass = $PasswordBox.Password
        $script:AuthAttempts = 0
        Show-AuthBanner -Type Success -M $r.Message
        $StatusDot.Fill = $brush.Green
        $StatusHeader.Text = "Authenticated"
        $StatusHeader.Foreground = $brush.Green
        Write-UiLog "Authenticated: $($UsernameBox.Text)" "SUCCESS"
        Update-OUList
    }
    else {
        $script:AuthAttempts++
        $script:IsLoggedIn = $false
        $remaining = $script:MaxAuthAttempts - $script:AuthAttempts
        Show-AuthBanner -Type Error -M "$($r.Message) ($remaining attempt(s) remaining)"
        $PasswordBox.Password = ""
        $StatusDot.Fill = $brush.Red
        $StatusHeader.Text = "Not authenticated"
        $StatusHeader.Foreground = $brush.Red
        Write-UiLog "Auth failed ($($script:AuthAttempts)/$($script:MaxAuthAttempts))" "ERROR"
    }
    Update-Summary
})

$PasswordBox.Add_KeyDown({
    if ($_.Key -eq "Return" -or $_.Key -eq "Enter") {
        $LoginBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
    }
})

$ComputerNameBox.Add_TextChanged({ Update-Summary })
$OUSearchBox.Add_TextChanged({ Filter-OUDataGrid -F $OUSearchBox.Text })
$OUSearchBtn.Add_Click({ Filter-OUDataGrid -F $OUSearchBox.Text })

$LangEnglish.Add_Checked({
    $script:Lang = "en-US"
    Update-Summary
})
$LangArabic.Add_Checked({
    $script:Lang = "ar-SA"
    Update-Summary
})

$OUDataGrid.Add_SelectionChanged({
    $sel = $OUDataGrid.SelectedItem
    if ($sel -and $sel.DN) {
        $OUSelectedInfo.Visibility = "Visible"
        $OUSelectedName.Text = $sel.Name
        $OUSelectedPath.Text = $sel.DN
    }
    else {
        $OUSelectedInfo.Visibility = "Collapsed"
    }
    Update-Summary
})

$RefreshBtn.Add_Click({
    Update-OUList
    Update-Summary
    $StatusHeader.Text = "Refreshed"
    $StatusHeader.Foreground = $brush.Gold
    $StatusDot.Fill = $brush.Gold
    Write-UiLog "All data refreshed" "INFO"
})

################################################################################
#  DEPLOY BUTTON — Validation → SCCM output → result dialog
#  Validates: logged in, computer name not empty, valid chars, <=15 chars, OU selected
#  Then writes TS variables and displays result dialog with variable summary.
################################################################################
$FinishBtn.Add_Click({
    if (-not $script:IsLoggedIn) {
        Show-CustomDialog -Type Warning -T "Auth Required" -M "Please sign in first."
        return
    }
    if ([string]::IsNullOrWhiteSpace($ComputerNameBox.Text)) {
        Show-CustomDialog -Type Warning -T "Name Required" -M "Enter a computer name."
        return
    }
    if ($ComputerNameBox.Text -match '[\\\/\:\*\?\"\<\>\|]') {
        Show-CustomDialog -Type Warning -T "Invalid Name" -M "Name contains invalid characters."
        return
    }
    if ($ComputerNameBox.Text.Length -gt 15) {
        Show-CustomDialog -Type Warning -T "Name Too Long" -M "Max 15 characters."
        return
    }

    $sel = $OUDataGrid.SelectedItem
    if (-not $sel -or -not $sel.DN) {
        Show-CustomDialog -Type Warning -T "OU Required" -M "Select a target OU."
        return
    }

    $al = @()
    foreach ($cb in $script:SoftCbs) {
        $al += @{
            Name    = [string]$cb.Content
            TSVar   = $cb.Tag
            Checked = [bool]$cb.IsChecked
        }
    }

    $result = Write-SCCMVariables -CN $ComputerNameBox.Text -OU $sel.DN -OUN $sel.Name `
        -DN $script:Domain -JU $UsernameBox.Text -JP $script:JoinPass -Lang $script:Lang -Apps $al

    $ca = @($al | Where-Object { $_.Checked } | ForEach-Object { $_.Name })
    $an = if ($ca.Count -gt 0) { ($ca -join ", ") } else { "None" }

    $sc  = [System.Security.SecurityElement]::Escape($ComputerNameBox.Text)
    $so  = [System.Security.SecurityElement]::Escape($sel.Name)
    $su  = [System.Security.SecurityElement]::Escape($UsernameBox.Text)
    $sd  = [System.Security.SecurityElement]::Escape($script:Domain)
    $sa  = [System.Security.SecurityElement]::Escape($an)
    $stc = if ($result.Success) { "#28A745" } else { "#DC3545" }
    $tt  = if ($result.Success) { "Deployment Ready" } else { "Deployment Issue" }
    $ll  = if ($result.Success) { "SUCCESS" } else { "ERROR" }

    $vn = @("OSDComputerName", "OSDDomainName", "OSDDomainOUName",
             "OSDJoinAccount", "OSDJoinPassword", "OSDRegisteredOrgName", "OSDLanguage")
    $vv = @($ComputerNameBox.Text, $script:Domain, $sel.FriendlyPath,
            $UsernameBox.Text, "********", $script:Org, $script:Lang)

    foreach ($a in $al) {
        if ($a.Checked) {
            $vn += $a.TSVar
            $vv += $a.Name
        }
    }

    $rd = ""
    $vr = ""
    for ($i = 0; $i -lt $vn.Count; $i++) {
        $sv = $([System.Security.SecurityElement]::Escape($vn[$i]))
        $sx = $([System.Security.SecurityElement]::Escape($vv[$i]))
        $rd += '<RowDefinition Height="Auto"/>'
        $vr += @"
<Grid Grid.Row="$i"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Grid.Column="0" Text="$sv" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,0"/><Border Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,3"><TextBlock Text="$sx" FontSize="11.5" FontWeight="SemiBold" Foreground="#1D4ED8" TextTrimming="CharacterEllipsis"/></Border></Grid>
"@
    }
    [xml]$dx = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Deployment"
    SizeToContent="WidthAndHeight"
    MinWidth="650" MaxWidth="750"
    WindowStartupLocation="CenterOwner"
    ShowInTaskbar="False"
    FontFamily="Segoe UI" FontSize="11"
    Background="#F6F8FB"
    Topmost="True"
    UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <DropShadowEffect x:Key="DlgShadow" BlurRadius="12" ShadowDepth="2" Opacity="0.10" Color="#102A43"/>
    </Window.Resources>
    <Grid Margin="14">
        <Border
            Background="White"
            BorderBrush="#E6EBF4"
            BorderThickness="1"
            CornerRadius="6"
            Effect="{StaticResource DlgShadow}">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Border Grid.Row="0" Padding="14,12,14,10" BorderBrush="#E6EBF4" BorderThickness="0,0,0,1">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Width="5" Height="28" Background="$stc" CornerRadius="3" Margin="0,0,10,0"/>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="$tt" Foreground="#1F2D3A" FontSize="15" FontWeight="Bold"/>
                            <TextBlock Text="Computer: $sc | Target OU: $so" Foreground="#5F6B7A" FontSize="10.5" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>
                <StackPanel Grid.Row="1" Margin="14,12,14,12">
                    <TextBlock Text="Task Sequence Variables" FontSize="12" FontWeight="Bold" Foreground="#1F2D3A" Margin="0,0,0,6"/>
                    <Border Background="#F8FAFC" BorderBrush="#E6EBF4" BorderThickness="1" CornerRadius="5" Padding="14,12">
                        <Grid>
                            <Grid.RowDefinitions>$rd</Grid.RowDefinitions>
                            $vr
                        </Grid>
                    </Border>
                </StackPanel>
                <Border Grid.Row="2" BorderBrush="#E6EBF4" BorderThickness="0,1,0,0" Padding="0,12,0,12">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                        <Button
                            x:Name="DlgBack"
                            Content="Back"
                            Width="80" Height="28"
                            Margin="0,0,8,0"
                            FontSize="11" FontWeight="SemiBold"
                            Cursor="Hand"
                            Background="#3B82F6"
                            Foreground="White"
                            BorderThickness="0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="b" Property="Opacity" Value="0.85"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                        <Button
                            x:Name="DlgOk"
                            Content="Deploy"
                            Width="80" Height="28"
                            FontSize="11" FontWeight="SemiBold"
                            Cursor="Hand"
                            Background="#28A745"
                            Foreground="White"
                            BorderThickness="0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>
    </Grid>
</Window>
"@
    try {
        $dr = New-Object System.Xml.XmlNodeReader $dx
        $dd = [Windows.Markup.XamlReader]::Load($dr)
        $dd.FindName("DlgBack").Add_Click({
            $dd.Close()
        })
        $dd.FindName("DlgOk").Add_Click({
            Write-UiLog "Deployment: $($ComputerNameBox.Text) -> $($sel.Name)" $ll
            $dd.Close()
            $Window.Close()
        })
        $dd.Owner = $Window
        $dd.ShowDialog() | Out-Null
    }
    catch {
        Write-UiLog "Result dialog failed: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show("Variables written. Close the wizard to proceed.", "Deployment", "OK", "Information") | Out-Null
        $Window.Close()
    }
})

################################################################################
#  CANCEL BUTTON — Confirmation dialog → close wizard
################################################################################
$CancelBtn.Add_Click({
    [xml]$cx = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Cancel"
    SizeToContent="WidthAndHeight"
    MinWidth="340"
    WindowStartupLocation="CenterOwner"
    ShowInTaskbar="False"
    FontFamily="Segoe UI" FontSize="11"
    Background="#F6F8FB"
    Topmost="True"
    UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Grid Margin="10">
        <Border Background="White" BorderBrush="#E6EBF4" BorderThickness="1" CornerRadius="6">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Border Grid.Row="0" Padding="12,10,12,8" BorderBrush="#E6EBF4" BorderThickness="0,0,0,1">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Width="5" Height="22" Background="#F59E0B" CornerRadius="3" Margin="0,0,12,0"/>
                        <TextBlock Grid.Column="1" Text="Cancel Deployment?" Foreground="#1F2D3A" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                    </Grid>
                </Border>
                <Border Grid.Row="1" Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" CornerRadius="5" Padding="14" Margin="16,14,16,14">
                    <TextBlock Text="Are you sure you want to cancel?" Foreground="#92400E" TextWrapping="Wrap" FontSize="12"/>
                </Border>
                <Border Grid.Row="2" BorderBrush="#E6EBF4" BorderThickness="0,1,0,0" Padding="0,10,0,10">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                        <Button
                            x:Name="YesBtn"
                            Content="Yes, Cancel"
                            Width="85" Height="28"
                            Margin="5,0"
                            FontSize="11" FontWeight="SemiBold"
                            Cursor="Hand"
                            Background="#F59E0B"
                            Foreground="White"
                            BorderThickness="0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                        <Button
                            x:Name="NoBtn"
                            Content="No"
                            Width="55" Height="28"
                            Margin="5,0"
                            FontSize="11" FontWeight="SemiBold"
                            Cursor="Hand"
                            IsCancel="True"
                            Background="#8899AA"
                            Foreground="White"
                            BorderThickness="0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                    </StackPanel>
                </Border>
            </Grid>
        </Border>
    </Grid>
</Window>
"@
    try {
        $cr = New-Object System.Xml.XmlNodeReader $cx
        $cd = [Windows.Markup.XamlReader]::Load($cr)
        $cd.FindName("YesBtn").Add_Click({
            $cd.Close()
            $Window.Close()
        })
        $cd.FindName("NoBtn").Add_Click({
            $cd.Close()
        })
        $cd.Owner = $Window
        $cd.ShowDialog() | Out-Null
    }
    catch {
        Write-UiLog "Cancel dialog failed: $($_.Exception.Message)" "ERROR"
        $res = [System.Windows.MessageBox]::Show("Are you sure you want to cancel?", "Cancel", "YesNo", "Warning")
        if ($res -eq "Yes") { $Window.Close() }
    }
})

################################################################################
#  STARTUP & WINDOW LIFECYCLE
#
#  Loaded  : Fetch device info, load OU list, init summary, focus username field.
#  Closing : Set $script:Closing flag, clear UI children, nullify data references
#            to ensure garbage collection and prevent stale dispatches.
#  The window is shown as a modal dialog — script waits until user closes it.
################################################################################
$script:Closing = $false

$Window.Add_Loaded({
    # Set default language radio button
    if ($script:Lang -eq "ar-SA") { $LangArabic.IsChecked = $true } else { $LangEnglish.IsChecked = $true }
    Update-OUList
    Update-Summary
    [System.Windows.Input.Keyboard]::Focus($UsernameBox)
    $Window.Activate() | Out-Null
})

$Window.Add_Closing({
    $script:Closing = $true
    if ($SoftwarePanel)   { $SoftwarePanel.Children.Clear() }
    $script:OUData = $null
    $script:SoftCbs = $null
})

Write-UiLog "Ready. Domain: $($script:Domain)" "INFO"
$Window.ShowDialog() | Out-Null
