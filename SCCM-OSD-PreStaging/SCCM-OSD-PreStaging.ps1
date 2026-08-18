<#
.SYNOPSIS
    SCCM OSD Pre-Staging Tool v1.0 — Zero-Touch device pre-staging with AdminService REST API.

.CONFIGURATION
    Before using this script, replace the following placeholders with your actual values:

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ PLACEHOLDER              │ PARAMETER       │ DESCRIPTION                    │
    ├──────────────────────────┼─────────────────┼────────────────────────────────┤
    │ "Your Company Name"      │ -CompanyName    │ Organization name (UI title)   │
    │ "YC"                     │ -CompanyShort   │ 2-3 char logo badge code       │
    │ "IT Operations"          │ -Department     │ Department name in header      │
    │ yourdomain.local         │ -DomainName     │ Active Directory domain FQDN   │
    │ OU=...,DC=...,DC=...     │ -SearchBase     │ LDAP root OU distinguished name│
    │ dc01.yourdomain.local    │ -DomainController│ DC hostname for LDAP queries  │
    │ YC1                      │ -SccmSiteCode   │ Your SCCM 3-char site code     │
    │ SCCM.yourdomain.local    │ -SccmServer     │ SMS Provider/AdminService FQDN │
    │ "Your Company Name"      │ -OrgName        │ Written to OSDRegisteredOrgName│
    └──────────────────────────────────────────────────────────────────────────────┘

.DESCRIPTION
    A professional WPF tool for pre-staging bare-metal devices in SCCM/MECM before PXE boot.
    Uses SCCM AdminService REST API (no local console required) for device import and
    OSD variable injection. Features dynamic software selection and automatic OU browsing
    from Active Directory.

    Key capabilities:
      - AdminService REST API device import (ImportMachineEntry) — no SCCM console needed
      - OSD variable injection via SMS_MachineSettings (POST to AdminService)
      - Active Directory authentication with PrincipalContext.ValidateCredentials
      - AD OU query via LdapConnection (pure .NET, no ADSI)
      - Dynamic software selection with WPF CheckBoxes — injected as App_* OSD variables
      - MAC address validation, auto-formatting, and computer name input (15-char limit)
      - Language selection (English / Arabic) with OSDLanguage variable
      - SSL certificate bypass for self-signed SCCM environments
      - Professional WPF UI with card-based layout, accent bars, and status indicators

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
    Active Directory domain for the OU query and domain join context.
    Default: "momar.local"

.PARAMETER SearchBase
    Distinguished Name of the root OU container for LDAP browsing.
    Format: "OU=Container,DC=domain,DC=local"
    Default: "OU=Domain Computers,DC=Momar,DC=local"

.PARAMETER DomainController
    Hostname or FQDN of the domain controller for LDAP queries.
    Default: "dc01.momar.local"

.PARAMETER SccmSiteCode
    SCCM site code for provider connection.
    Default: "MT1"

.PARAMETER SccmServer
    Hostname or FQDN of the SCCM server hosting the SMS Provider and AdminService.
    Default: "SCCM.Momar.local"

.PARAMETER OrgName
    Organization name written to OSDRegisteredOrgName device variable.
    Default: "Momar Tech"

.PARAMETER DefaultLanguage
    Default operating system language selection.
    Default: "en-US"

.PARAMETER Software
    Array of software entries for checkbox generation.
    Format per entry: "DisplayName|TaskSequenceVariableName|DefaultChecked"
    Default: 8 common enterprise applications (Chrome, Firefox, 7-Zip, etc.)

.EXAMPLE
    .\SCCM-OSD-PreStaging.ps1

    Runs with all Momar Tech defaults including 8 software options.

.EXAMPLE
    .\SCCM-OSD-PreStaging.ps1 -CompanyName "Contoso Ltd" -CompanyShort "CT" `
        -Department "Infrastructure" -DomainName "contoso.com" `
        -SearchBase "OU=Workstations,DC=contoso,DC=com" `
        -DomainController "dc01.contoso.com" `
        -SccmSiteCode "CT1" -SccmServer "sccm.contoso.com" `
        -OrgName "Contoso Ltd" -DefaultLanguage "ar-SA"

    Fully customized for Contoso Ltd.

.EXAMPLE
    .\SCCM-OSD-PreStaging.ps1 -Software @("Chrome|App_Chrome|true","VPN|App_VPN|true")

    Custom software list — only Chrome and VPN as options.

.NOTES
    File Name      : SCCM-OSD-PreStaging.ps1
    Version        : 1.0
    Author         : IT Operations, Momar Tech
    Requirements   : PowerShell 5.1+, .NET Framework 4.6.2+
                     SCCM AdminService must be enabled on the SMS Provider (HTTPS)
    Architecture   : Single-file — XAML, functions, and event handlers in one script
    UI Framework   : WPF (Windows Presentation Foundation) via XAML embedded string
    SCCM API       : AdminService REST API (ImportMachineEntry, SMS_MachineSettings via Invoke-RestMethod)
    LDAP Method    : System.DirectoryServices.Protocols.LdapConnection (pure .NET, no ADSI COM)

.LINK
    README.md — User-facing documentation and setup guide
#>
param(
    [string]$CompanyName    = "Momar Tech",                                    # Org name in UI title/header
    [string]$CompanyShort   = "MT",                                            # 2-3 char logo badge code
    [string]$Department     = "IT Operations",                                 # Dept name in header/footer
    [string]$DomainName     = "momar.local",                                   # AD domain for OU query
    [string]$SearchBase     = "OU=Domain Computers,DC=Momar,DC=local",         # LDAP root OU DN
    [string]$DomainController = "dc01.momar.local",                            # DC for LDAP queries
    [string]$SccmSiteCode   = "MT1",                                           # SCCM site code (API URL)
    [string]$SccmServer     = "SCCM.Momar.local",                              # AdminService FQDN
    [string]$OrgName        = "Momar Tech",                                    # OSDRegisteredOrgName value
    [string]$DefaultLanguage = "en-US",                                        # OS language (en-US/ar-SA)
    [string[]]$Software      = @("Cisco AnyConnect VPN|App_CiscoAnyConnect|true")  # Software list
)

################################################################################
#  INITIALIZATION
#  Load WPF assemblies, parse Software parameter into hashtable, assign globals.
#  Software format: "DisplayName|TaskSequenceVariableName|DefaultChecked"
################################################################################
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.DirectoryServices.Protocols

# Compile a true .NET delegate for the certificate validation bypass instead of a
# PowerShell scriptblock. The ServicePointManager fires the callback on a thread-pool
# thread that has NO PowerShell runspace in compiled EXEs (PSWrap / ps2exe). A script-
# block { $true } fails there with:
#   "There is no Runspace available to run scripts in this thread."
# Using a compiled C# static method avoids the runspace dependency entirely.
# NOTE: no -ReferencedAssemblies is passed (default refs work in both .NET Framework
# 5.1 and .NET Core 7+), and ServicePointManager is intentionally NOT touched inside
# C# to avoid the SYSLIB0014 obsolete-compile-error on modern runtimes.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public static class SslBypass
{
    public static bool ValidateCertificate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors)
    {
        return true;
    }
}
"@
}
catch {
    Write-Warning "SslBypass compile failed; falling back to scriptblock cert bypass: $($_.Exception.Message)"
}

# Force TLS 1.2 and bypass SSL validation/proxy for the SCCM AdminService HTTPS API.
# These settings are applied at startup AND re-applied inside Invoke-DevicePreStage
# immediately before every API call.
function Set-AdminServiceTls {
    $p = [System.Net.ServicePointManager]::SecurityProtocol
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = $p -bor 192 -bor 768 -bor 3072
    }
    catch {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }
    try {
        # Wire the compiled C# method into the callback as a real .NET delegate (no runspace needed).
        $cbMethod = [SslBypass].GetMethod('ValidateCertificate')
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = `
            [System.Net.Security.RemoteCertificateValidationCallback]::CreateDelegate(
                [System.Net.Security.RemoteCertificateValidationCallback], $cbMethod)
    }
    catch {
        # Fallback: works in interactive PowerShell where a runspace exists.
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }
    [System.Net.WebRequest]::DefaultWebProxy = $null
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 100
}
Set-AdminServiceTls

$script:Co       = $CompanyName
$script:CoShort  = $CompanyShort
$script:Dept     = $Department
$script:Domain   = $DomainName
$script:SB       = $SearchBase
$script:DC       = $DomainController
$script:SC       = $SccmSiteCode
$script:SCCM     = $SccmServer
$script:Org      = $OrgName
$script:Lang     = $DefaultLanguage
$script:Ver      = "v1.0"

$script:SCCMModulePath = $null
$script:SiteCode       = $SccmSiteCode
$script:ConsoleBin     = $null
$script:OUData         = @()
$script:IsSCCMLoaded   = $false
$script:IsLoggedIn     = $false
$script:JoinPass       = ""
$script:AuthAttempts   = 0
$script:MaxAuthAttempts = 5

$script:SoftwareItems = foreach ($s in $Software) {
    $p = $s -split '\|', 3
    @{ Name = $p[0]; TSVar = $p[1]; Default = ($p[2] -eq 'true') }
}

$hdrTitle = "OSD Pre-Staging"
$hdrSub   = "$CompanyName | $Department"
$ftrText  = "v1.0 | $CompanyName - $Department"

################################################################################
#  EMBEDDED XAML UI DEFINITION
#  Layout: Header (Navy bar) → Scrollable 2-col body → Footer (action bar)
#  Left column : Auth card, MAC Address card, Computer Name card, Target OU card
#  Right column: Summary card, Software card, Language card, Message Center
################################################################################
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Name="MainWindow"
        Title="$CompanyName - $hdrTitle"
        Height="910" Width="1100"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" FontSize="14"
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
            <Setter Property="FontSize" Value="14"/>
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
            <Setter Property="Height" Value="28"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
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
        <Style x:Key="H3" TargetType="TextBlock"><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="FontSize" Value="13"/><Setter Property="Foreground" Value="{StaticResource TextDark}"/></Style>
        <Style x:Key="Lbl" TargetType="TextBlock"><Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="{StaticResource TextMid}"/><Setter Property="Margin" Value="0,0,0,3"/></Style>
        <Style x:Key="Tb" TargetType="TextBox"><Setter Property="Height" Value="28"/><Setter Property="FontSize" Value="13"/><Setter Property="Padding" Value="6,3"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
        <Style x:Key="Pb" TargetType="PasswordBox"><Setter Property="Height" Value="28"/><Setter Property="FontSize" Value="13"/><Setter Property="Padding" Value="6,3"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/><Setter Property="BorderThickness" Value="1"/></Style>
        <Style x:Key="GridHeaderStyle" TargetType="{x:Type DataGridColumnHeader}">
            <Setter Property="Background" Value="#EAF2FF"/>
            <Setter Property="Foreground" Value="{StaticResource TextDark}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
        </Style>
        <Style x:Key="GridRowStyle" TargetType="{x:Type DataGridRow}">
            <Setter Property="MinHeight" Value="28"/>
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
            <RowDefinition Height="60"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="44"/>
        </Grid.RowDefinitions>
        <!-- HEADER -->
        <Border Grid.Row="0" Background="{StaticResource Navy}">
            <Grid Margin="14,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Border Grid.Column="0" Width="36" Height="36" CornerRadius="6" Margin="0,0,10,0" Background="{StaticResource Gold}">
                    <TextBlock Text="$($script:CoShort)" FontSize="14" FontWeight="Bold" Foreground="{StaticResource Navy}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="$hdrTitle" FontSize="16" FontWeight="Bold" Foreground="{StaticResource TextWhite}"/>
                    <TextBlock Text="$hdrSub" FontSize="12" Foreground="#7C8BA1" Margin="0,1,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse Name="StatusDot" Width="7" Height="7" Fill="{StaticResource Orange}" Margin="0,0,6,0"/>
                    <TextBlock Name="StatusHeader" Text="Ready" FontSize="13" Foreground="{StaticResource Orange}"/>
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

                <!-- LEFT COLUMN -->
                <StackPanel Grid.Column="0">
                    <!-- AUTH -->
                    <Border Style="{StaticResource Card}" Background="{StaticResource AuthBg}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                    <Border Style="{StaticResource AccentBar}" Background="{StaticResource Gold}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                        <StackPanel><TextBlock Text="Authentication" Style="{StaticResource H3}"/><TextBlock Name="AuthSubtitle" Text="Enter domain credentials to proceed" FontSize="12" Foreground="{StaticResource TextMuted}" Margin="0,0,0,0"/></StackPanel>
                            </DockPanel>
                            <StackPanel Name="AuthLoginPanel">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Username" Style="{StaticResource Lbl}" VerticalAlignment="Center" Margin="0,0,10,0" Width="78"/>
                                    <TextBox Grid.Row="0" Grid.Column="1" Name="UsernameBox" Style="{StaticResource Tb}" Margin="0,0,0,5"/>
                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Password" Style="{StaticResource Lbl}" VerticalAlignment="Center" Margin="0,0,10,0" Width="78"/>
                                    <PasswordBox Grid.Row="1" Grid.Column="1" Name="PasswordBox" Style="{StaticResource Pb}" Margin="0,0,0,5"/>
                                </Grid>
                                <Border Name="AuthBanner" CornerRadius="4" Padding="8,6" Margin="0,0,0,6" Visibility="Collapsed">
                                    <DockPanel><TextBlock Name="AuthIcon" DockPanel.Dock="Left" FontSize="13" Margin="0,0,6,0" Text="" FontWeight="Bold"/><TextBlock Name="AuthText" FontSize="13" TextWrapping="Wrap"/></DockPanel>
                                </Border>
                                <Button Name="LoginBtn" Content="Sign In" Style="{StaticResource BtnBlue}"/>
                            </StackPanel>
                            <DockPanel Name="AuthWelcomePanel" Visibility="Collapsed" Margin="0,4,0,0">
                                <Button Name="SignOutBtn" DockPanel.Dock="Right" Content="Sign Out" Width="72" Style="{StaticResource BtnFlat}" FontSize="12" VerticalAlignment="Center"/>
                                <Border Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="8,7">
                                    <TextBlock Name="AuthWelcomeText" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}" VerticalAlignment="Center"/>
                                </Border>
                            </DockPanel>
                        </StackPanel>
                    </Border>
                    <!-- MAC ADDRESS CARD -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="MAC Address" Style="{StaticResource H3}"/><TextBlock Text="Enter the target device MAC address" FontSize="12" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <TextBox Name="MacAddressBox" Style="{StaticResource Tb}" MaxLength="17" Text=""
                                     ToolTip="Paste or type — auto-formats to 00:11:22:AA:BB:CC"/>
                            <TextBlock Text="Accepted: 00:11:22:AA:BB:CC  |  00-11-22-AA-BB-CC  |  001122AABBCC" FontSize="12" Foreground="{StaticResource TextMuted}" Margin="4,3,0,0"/>
                            <Border Name="MacBanner" CornerRadius="4" Padding="8,6" Margin="0,4,0,0" Visibility="Collapsed">
                                <DockPanel><TextBlock Name="MacIcon" DockPanel.Dock="Left" FontSize="13" Margin="0,0,6,0" Text="" FontWeight="Bold"/><TextBlock Name="MacText" FontSize="13" TextWrapping="Wrap"/></DockPanel>
                            </Border>
                        </StackPanel>
                    </Border>
                    <!-- COMPUTER NAME -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="Computer Name" Style="{StaticResource H3}"/><TextBlock Text="Enter the new computer name" FontSize="12" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <TextBox Name="ComputerNameBox" Style="{StaticResource Tb}" MaxLength="15" Text=""/>
                            <TextBlock Text="Maximum 15 characters (NetBIOS limit)" FontSize="12" Foreground="{StaticResource TextMuted}" Margin="4,4,0,0"/>
                        </StackPanel>
                    </Border>
                    <!-- TARGET OU -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Gold}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="Target Organizational Unit" Style="{StaticResource H3}"/><TextBlock Text="Search and select the destination OU" FontSize="12" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <Border BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="5" Background="#FFFFFF" Margin="0,0,0,8">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="&#x1F50D;" FontSize="14" Margin="10,0,6,0" VerticalAlignment="Center" Foreground="{StaticResource TextMuted}"/>
                                    <TextBox Grid.Column="1" Name="OUSearchBox" BorderThickness="0" Background="Transparent" Height="28" FontSize="13" Padding="3,0" VerticalContentAlignment="Center"/>
                                    <Button Grid.Column="2" Name="OUSearchBtn" Content="Search" Width="72" Height="28" Margin="2" Style="{StaticResource BtnPrimary}" FontSize="12"/>
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
                                    Height="215"
                                    ScrollViewer.HorizontalScrollBarVisibility="Auto"
                                    ColumnHeaderStyle="{StaticResource GridHeaderStyle}"
                                    RowStyle="{StaticResource GridRowStyle}"
                                    CellStyle="{StaticResource GridCellStyle}">
                                    <DataGrid.Columns>
                                            <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="140" ElementStyle="{StaticResource TrimCell}"/>
                                            <DataGridTextColumn Header="Description" Binding="{Binding Description}" Width="160" ElementStyle="{StaticResource TrimCell}"/>
                                            <DataGridTextColumn Header="OU Path" Binding="{Binding FriendlyPath}" Width="360" ElementStyle="{StaticResource TrimCell}"/>
                                    </DataGrid.Columns>
                                </DataGrid>
                            </Border>
                            <Border Name="OUSelectedInfo" Visibility="Collapsed" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="8,5" Margin="0,6,0,0">
                                <DockPanel>
                                    <Border DockPanel.Dock="Left" Width="5" Height="5" Background="{StaticResource AccentBlue}" CornerRadius="3" Margin="0,0,6,0"/>
                                    <StackPanel><TextBlock Name="OUSelectedName" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/><TextBlock Name="OUSelectedPath" FontSize="12" Foreground="{StaticResource TextLight}" TextTrimming="CharacterEllipsis"/></StackPanel>
                                </DockPanel>
                            </Border>
                            <DockPanel Margin="0,4,0,0">
                                <TextBlock Name="OUMessage" DockPanel.Dock="Left" FontSize="12" Foreground="{StaticResource TextMuted}"/>
                                <TextBlock Name="OUCount" DockPanel.Dock="Right" FontSize="12" Foreground="{StaticResource TextMuted}"/>
                            </DockPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- RIGHT COLUMN -->
                <StackPanel Grid.Column="2">
                    <!-- SUMMARY -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Gold}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <TextBlock Text="Pre-Staging Summary" Style="{StaticResource H3}" VerticalAlignment="Center"/>
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
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="80"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="MAC:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="13"/>
                                    <Border Grid.Row="0" Grid.Column="1" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumMac" Text="---" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/></Border>
                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Name:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="13"/>
                                    <Border Grid.Row="1" Grid.Column="1" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumName" Text="---" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/></Border>
                                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Target OU:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="13"/>
                                    <Border Grid.Row="2" Grid.Column="1" Background="#FFFFFF" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumOU" Text="---" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource TextDark}" TextTrimming="CharacterEllipsis"/></Border>
                                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Domain:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="13"/>
                                    <Border Grid.Row="3" Grid.Column="1" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumDomain" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/></Border>
                                    <TextBlock Grid.Row="4" Grid.Column="0" Text="Language:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" Margin="0,0,0,4" FontSize="13"/>
                                    <Border Grid.Row="4" Grid.Column="1" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Name="SumLang" Text="English" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/></Border>
                                    <TextBlock Grid.Row="5" Grid.Column="0" Text="SCCM:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" FontSize="13"/>
                                    <Border Grid.Row="5" Grid.Column="1" Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="6,3"><TextBlock Name="SumSCCM" Text="$("{0} | {1}" -f $script:SC, $script:SCCM)" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}"/></Border>
                                    <TextBlock Grid.Row="6" Grid.Column="0" Text="User:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" FontSize="13"/>
                                    <Border Grid.Row="6" Grid.Column="1" Background="{StaticResource SoftRed}" CornerRadius="4" Padding="6,3"><TextBlock Name="SumUser" Text="Not signed in" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource AccentRed}"/></Border>
                                    <TextBlock Grid.Row="7" Grid.Column="0" Text="Software:" FontWeight="SemiBold" Foreground="{StaticResource TextMid}" VerticalAlignment="Center" FontSize="13"/>
                                    <Border Grid.Row="7" Grid.Column="1" Background="#FFFFFF" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="4" Padding="6,3"><TextBlock Name="SumApps" Text="None" FontSize="13" Foreground="{StaticResource TextDark}" TextTrimming="CharacterEllipsis"/></Border>
                                </Grid>
                            </Border>
                        </StackPanel>
                    </Border>
                    <!-- SOFTWARE -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="Software Installation" Style="{StaticResource H3}"/><TextBlock Text="Select software to install" FontSize="12" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <Border Background="{StaticResource SoftBlue}" CornerRadius="4" Padding="8,6"><StackPanel Name="SoftwarePanel"/></Border>
                        </StackPanel>
                    </Border>
                    <!-- LANGUAGE -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <StackPanel><TextBlock Text="System Language" Style="{StaticResource H3}"/><TextBlock Text="Select the operating system language" FontSize="12" Foreground="{StaticResource TextMuted}" Margin="0,1,0,0"/></StackPanel>
                            </DockPanel>
                            <StackPanel Orientation="Horizontal" Margin="4,2">
                                <RadioButton Name="LangEnglish" Content="English" Margin="0,0,20,0" FontSize="13" Foreground="{StaticResource AccentBlue}" FontWeight="SemiBold" GroupName="LangGroup" IsChecked="True"/>
                                <RadioButton Name="LangArabic"  Content="Arabic"  FontSize="13" Foreground="{StaticResource AccentBlue}" FontWeight="SemiBold" GroupName="LangGroup"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                    <!-- MESSAGE CENTER -->
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <DockPanel Margin="0,0,0,6">
                                <Border Style="{StaticResource AccentBar}" Background="{StaticResource Navy}" DockPanel.Dock="Left" Height="20" VerticalAlignment="Center"/>
                                <Button Name="ClearLogBtn" DockPanel.Dock="Right" Content="Clear" Width="70" Style="{StaticResource BtnFlat}" Margin="0,0,0,0"/>
                                <Button Name="CopyLogBtn" DockPanel.Dock="Right" Content="Copy" Width="70" Style="{StaticResource BtnFlat}" Margin="0,0,4,0"/>
                                <TextBlock Text="Message Center" Style="{StaticResource H3}" VerticalAlignment="Center"/>
                            </DockPanel>
                            <Border Background="#1F2D3A" BorderBrush="#2D3F52" BorderThickness="1" CornerRadius="4" Padding="2">
                                <RichTextBox x:Name="LogBox" Height="170" IsReadOnly="True" Background="Transparent" Foreground="#C8D6E5" BorderThickness="0" FontFamily="Consolas" FontSize="13" VerticalScrollBarVisibility="Auto" Padding="6,4"/>
                            </Border>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>
        </ScrollViewer>

        <!-- FOOTER -->
        <Border Grid.Row="2" Background="#FFFFFF" BorderBrush="{StaticResource Border}" BorderThickness="0,1,0,0">
            <Grid Margin="12,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" FontSize="12" Foreground="{StaticResource TextMuted}" VerticalAlignment="Center" Text="$ftrText"/>
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button Name="RefreshBtn" Content="Refresh" Width="95" Margin="0,0,6,0" Style="{StaticResource BtnFlat}"/>
                    <Button Name="PrestageBtn" Content="Add Device" Width="140" Style="{StaticResource BtnGreen}"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

################################################################################
#  XAML PARSE & WPF CONTROL BINDING
################################################################################
$reader = New-Object System.Xml.XmlNodeReader $XAML
$Window = [Windows.Markup.XamlReader]::Load($reader)

$UsernameBox       = $Window.FindName("UsernameBox")
$PasswordBox       = $Window.FindName("PasswordBox")
$LoginBtn          = $Window.FindName("LoginBtn")
$AuthLoginPanel    = $Window.FindName("AuthLoginPanel")
$AuthWelcomePanel  = $Window.FindName("AuthWelcomePanel")
$AuthWelcomeText   = $Window.FindName("AuthWelcomeText")
$AuthSubtitle      = $Window.FindName("AuthSubtitle")
$SignOutBtn        = $Window.FindName("SignOutBtn")
$AuthBanner        = $Window.FindName("AuthBanner")
$AuthIcon          = $Window.FindName("AuthIcon")
$AuthText          = $Window.FindName("AuthText")
$MacAddressBox     = $Window.FindName("MacAddressBox")
$MacBanner         = $Window.FindName("MacBanner")
$MacIcon           = $Window.FindName("MacIcon")
$MacText           = $Window.FindName("MacText")
$ComputerNameBox   = $Window.FindName("ComputerNameBox")
$LangEnglish       = $Window.FindName("LangEnglish")
$LangArabic        = $Window.FindName("LangArabic")
$OUSearchBox       = $Window.FindName("OUSearchBox")
$OUSearchBtn       = $Window.FindName("OUSearchBtn")
$OUDataGrid        = $Window.FindName("OUDataGrid")
$OUSelectedInfo    = $Window.FindName("OUSelectedInfo")
$OUSelectedName    = $Window.FindName("OUSelectedName")
$OUSelectedPath    = $Window.FindName("OUSelectedPath")
$OUMessage         = $Window.FindName("OUMessage")
$OUCount           = $Window.FindName("OUCount")
$StatusDot         = $Window.FindName("StatusDot")
$StatusHeader      = $Window.FindName("StatusHeader")
$SumMac            = $Window.FindName("SumMac")
$SumName           = $Window.FindName("SumName")
$SumOU             = $Window.FindName("SumOU")
$SumDomain         = $Window.FindName("SumDomain")
$SumLang           = $Window.FindName("SumLang")
$SumSCCM           = $Window.FindName("SumSCCM")
$SumUser           = $Window.FindName("SumUser")
$SumApps           = $Window.FindName("SumApps")
$SoftwarePanel     = $Window.FindName("SoftwarePanel")
$PrestageBtn       = $Window.FindName("PrestageBtn")
$RefreshBtn        = $Window.FindName("RefreshBtn")
$LogBox            = $Window.FindName("LogBox")
$ClearLogBtn       = $Window.FindName("ClearLogBtn")
$CopyLogBtn        = $Window.FindName("CopyLogBtn")

################################################################################
#  FROZEN WPF BRUSHES
################################################################################
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
    SoftBlue     = New-Brush "#EEF2FF"
}

################################################################################
#  DYNAMIC SOFTWARE CHECKBOX GENERATION
#  Iterates $script:SoftwareItems, creates WPF CheckBox per entry.
#  Each CheckBox tracks its SCCM Task Sequence variable name in .Tag.
#  Checked/Unchecked events trigger Update-Summary.
################################################################################
$script:SoftCbs = @()
foreach ($item in $script:SoftwareItems) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $item.Name
    $cb.FontSize = 13
    $cb.Margin = New-Object System.Windows.Thickness(6, 5, 6, 5)
    $cb.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString("#1D4ED8"))
    $cb.IsChecked = $item.Default
    $cb.Tag = $item.TSVar
    $cb.ToolTip = "TS Variable: $($item.TSVar)"
    $cb.Add_Checked({ Update-Summary })
    $cb.Add_Unchecked({ Update-Summary })
    $SoftwarePanel.Children.Add($cb) | Out-Null
    $script:SoftCbs += $cb
}

################################################################################
#  MESSAGE CENTER LOGGING
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
#  CUSTOM DIALOG SYSTEM
################################################################################
function Show-CustomDialog {
    param([string]$Type, [string]$T, [string]$M, [switch]$YesNo)
    $hc = switch ($Type) { "Error" { "#DC3545" }"Warning" { "#F59E0B" }"Success" { "#28A745" }"Info" { "#3B82F6" } }
    $Title = [System.Security.SecurityElement]::Escape($T)
    $Message = [System.Security.SecurityElement]::Escape($M)

    $buttonsXaml = if ($YesNo) {
@"
                            <Button x:Name="DlgYes" Content="Yes" Width="80" Height="28" FontSize="13" FontWeight="SemiBold" Cursor="Hand" Background="$hc" Foreground="White" BorderThickness="0" Margin="0,0,8,0">
                                <Button.Template>
                                    <ControlTemplate TargetType="Button">
                                        <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,0">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Button.Template>
                            </Button>
                            <Button x:Name="DlgNo" Content="No" Width="80" Height="28" FontSize="13" FontWeight="SemiBold" Cursor="Hand" Background="Transparent" Foreground="#475467" BorderBrush="#D7E0EC" BorderThickness="1">
                                <Button.Template>
                                    <ControlTemplate TargetType="Button">
                                        <Border Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="10,0">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#F0F2F5"/></Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Button.Template>
                            </Button>
"@
    }
    else {
@"
                            <Button x:Name="DlgOk" Content="OK" Width="90" Height="28" FontSize="13" FontWeight="SemiBold" Cursor="Hand" Background="$hc" Foreground="White" BorderThickness="0">
                                <Button.Template>
                                    <ControlTemplate TargetType="Button">
                                        <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,0">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Button.Template>
                            </Button>
"@
    }

    [xml]$x = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="$Title"
    SizeToContent="WidthAndHeight"
    MinWidth="420" MaxWidth="560"
    WindowStartupLocation="CenterOwner"
    ShowInTaskbar="False"
    FontFamily="Segoe UI" FontSize="13"
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
                        <TextBlock Grid.Column="1" Text="$Title" Foreground="#1F2D3A" FontSize="16" FontWeight="Bold" VerticalAlignment="Center"/>
                    </Grid>
                </Border>
                <Border Grid.Row="1" Background="#F8FAFC" BorderBrush="#E6EBF4" BorderThickness="1" CornerRadius="5" Padding="14" Margin="16,14,16,14">
                    <TextBlock Text="$Message" Foreground="#334155" TextWrapping="Wrap" FontSize="14"/>
                </Border>
                <Border Grid.Row="2" BorderBrush="#E6EBF4" BorderThickness="0,1,0,0" Padding="0,10,0,10">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
$($buttonsXaml)
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
        $d.Owner = $Window

        if ($YesNo) {
            $script:_DialogResult = $false
            $d.FindName("DlgYes").Add_Click({ $script:_DialogResult = $true; $d.Close() })
            $d.FindName("DlgNo").Add_Click({ $script:_DialogResult = $false; $d.Close() })
            $d.ShowDialog() | Out-Null
            return $script:_DialogResult
        }
        else {
            $d.FindName("DlgOk").Add_Click({ $d.Close() })
            $d.ShowDialog() | Out-Null
        }
    }
    catch {
        Write-UiLog "Dialog render failed: $($_.Exception.Message)" "ERROR"
        $r = [System.Windows.MessageBox]::Show($Message, $Title, $(if ($YesNo){'YesNo'}else{'OK'}), $(if ($Type -eq 'Error'){'Error'}else{'Warning'}))
        if ($YesNo) { return ($r -eq 'Yes') }
    }
}

################################################################################
#  UI HELPERS
################################################################################
function ConvertTo-FriendlyOUPath {
    param([string]$DN)
    if ([string]::IsNullOrWhiteSpace($DN)) { return "" }
    $parts = @($DN -split ',' | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_.Substring(3) })
    if ($parts.Count -eq 0) { return $DN }
    [array]::Reverse($parts)
    return ($parts -join ' / ')
}

function Test-MacAddress {
    param([string]$Mac)
    if ([string]::IsNullOrWhiteSpace($Mac)) { return $false }
    return $Mac -match '^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$'
}

function Format-MacAddress {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "" }
    $hex = $Raw.ToUpper() -replace '[^0-9A-F]', ''
    if ($hex.Length -lt 12) { return $Raw }
    if ($hex.Length -gt 12) { $hex = $hex.Substring(0, 12) }
    $pairs = for ($i = 0; $i -lt 12; $i += 2) { $hex.Substring($i, 2) }
    return ($pairs -join ':')
}

function Show-MacBanner {
    param([string]$Type, [string]$M)
    if (-not $MacBanner -or -not $MacIcon -or -not $MacText) { return }
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
    $MacBanner.Background = $bgC
    $MacBanner.BorderBrush = $borderC
    $MacBanner.BorderThickness = New-Object System.Windows.Thickness(1)
    $MacIcon.Foreground = $borderC
    $MacIcon.Text = $icon
    $MacText.Foreground = $txtC
    $MacText.Text = $M
    $MacBanner.Visibility = "Visible"
}
function Hide-MacBanner { if ($MacBanner) { $MacBanner.Visibility = "Collapsed" } }

################################################################################
#  AUTHENTICATION BANNER
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
#  ACTIVE DIRECTORY AUTHENTICATION
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
#  ORGANIZATIONAL UNIT BROWSER
################################################################################
function Update-OUList {
    if (-not $OUDataGrid) { return }

    $OUMessage.Text = "Loading..."
    $OUMessage.Foreground = $brush.TextMuted
    $OUSelectedInfo.Visibility = "Collapsed"
    $OUDataGrid.ItemsSource = $null

    try {
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $rootEntry = $domain.GetDirectoryEntry()
        $searchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($script:DC)/$($script:SB)")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=organizationalUnit)"
        $searcher.PageSize = 1000
        $searcher.ServerTimeLimit = [TimeSpan]::FromSeconds(30)
        $searcher.PropertiesToLoad.Add("name") | Out-Null
        $searcher.PropertiesToLoad.Add("distinguishedname") | Out-Null
        $searcher.PropertiesToLoad.Add("description") | Out-Null

        $results = $searcher.FindAll()
        Write-UiLog "Queried AD — $($results.Count) OUs found" "INFO"

        $script:OUData = @()
        foreach ($result in $results) {
            $props = $result.Properties
            $name = $props["name"][0]
            $dn   = $props["distinguishedname"][0]
            $desc = ""
            if ($props["description"] -and $props["description"].Count -gt 0) {
                $desc = $props["description"][0]
            }
            $script:OUData += [PSCustomObject]@{
                Name         = $name
                Description  = $desc
                DN           = $dn
                FriendlyPath = ConvertTo-FriendlyOUPath($dn)
            }
        }
        $results.Dispose()
        $searcher.Dispose()
        $searchRoot.Dispose()

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
        Write-UiLog "Found $($script:OUData.Count) OUs from $($script:DC)" "INFO"
    }
    catch {
        $OUMessage.Text = "Cannot load OUs"
        $OUMessage.Foreground = $brush.Red
        Write-UiLog "OU error: $($_.Exception.Message)" "ERROR"
        $OUCount.Text = ""
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
#  PRE-STAGING SUMMARY (MAC, Name, OU, Domain, Language, SCCM, User, Software)
################################################################################
function Update-Summary {
    $mac = $MacAddressBox.Text.Trim()
    $name = $ComputerNameBox.Text

    $SumMac.Text = if ($mac) { $mac } else { "---" }
    $SumMac.Parent.Background = if (Test-MacAddress -Mac $mac) { $brush.GreenBg } else { $brush.RedBg }

    $SumName.Text = if ($name) { $name } else { "---" }
    $SumName.Parent.Background = if ($name -and $name -ne "---") { $brush.GreenBg } else { $brush.RedBg }

    $sel = $OUDataGrid.SelectedItem
    $SumOU.Text = if ($sel -and $sel.DN) { $sel.Name } else { "---" }
    $SumOU.Parent.Background = if ($sel -and $sel.DN) { $brush.GreenBg } else { $brush.RedBg }

    $SumDomain.Text = $script:Domain
    $SumDomain.Parent.Background = $brush.GreenBg

    $SumLang.Text = if ($LangArabic.IsChecked) { "Arabic" } else { "English" }
    $SumLang.Parent.Background = $brush.GreenBg

    if ($script:IsSCCMLoaded) {
        $displaySite = if ($script:SiteCode) { $script:SiteCode } else { "Loaded" }
        $SumSCCM.Text = "$displaySite  |  $($script:SCCM) (Console)"
        $SumSCCM.Foreground = $brush.AccentGreen
        $SumSCCM.Parent.Background = $brush.GreenBg
    }
    else {
        $SumSCCM.Text = "$($script:SC) | $($script:SCCM) (AdminService)"
        $SumSCCM.Foreground = $brush.AccentGreen
        $SumSCCM.Parent.Background = $brush.GreenBg
    }

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

    $checkedApps = @($script:SoftCbs | Where-Object { $_.IsChecked } | ForEach-Object { $_.Content })
    $SumApps.Text = if ($checkedApps.Count -gt 0) { ($checkedApps -join ", ") } else { "None" }
    $SumApps.Parent.Background = if ($checkedApps.Count -gt 0) { $brush.GreenBg } else { $brush.RedBg }
}

################################################################################
#  SCCM MODULE DISCOVERY & IMPORT
################################################################################
function Get-SCCMModule {
    if ($script:SCCMModulePath) { return $true }

    $scriptDir = Split-Path -Parent $PSCommandPath

    $localPath = "$scriptDir\ConfigurationManager.psd1"
    if ((Test-Path -LiteralPath $localPath) -and (Test-Path "$scriptDir\AdminUI.PS.dll")) {
        $script:SCCMModulePath = $localPath
        Write-UiLog "Found SCCM module (portable): $localPath" "SUCCESS"
        return $true
    }

    if (Test-Path -LiteralPath $localPath) {
        Write-UiLog "ConfigurationManager.psd1 found in script directory but DLLs are missing. Will use installed console." "WARNING"
    }

    $possiblePaths = @(
        "$env:ProgramFiles\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1",
        "${env:ProgramFiles(x86)}\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1",
        "$env:SMS_ADMIN_UI_PATH\..\ConfigurationManager.psd1"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path -LiteralPath $path) {
            $script:SCCMModulePath = $path
            Write-UiLog "Found SCCM module: $path" "SUCCESS"
            return $true
        }
    }
    return $false
}

function Find-ConsoleBinDirectory {
    $installPaths = @(
        "$env:ProgramFiles\Microsoft Configuration Manager\AdminConsole\bin",
        "${env:ProgramFiles(x86)}\Microsoft Configuration Manager\AdminConsole\bin"
    )
    foreach ($path in $installPaths) {
        if (Test-Path "$path\Microsoft.ConfigurationManagement.exe") { return $path }
        if (Test-Path "$path\Microsoft.ConfigurationManagement.ManagementProvider.dll") { return $path }
    }
    $moduleDir = Split-Path -Parent $script:SCCMModulePath
    if ((Test-Path "$moduleDir\AdminUI.PS.dll") -and (Test-Path "$moduleDir\Microsoft.ConfigurationManagement.ManagementProvider.dll")) {
        return $moduleDir
    }
    return $null
}

function Import-SCCMEnvironment {
    if (-not $script:SCCMModulePath) {
        if (-not (Get-SCCMModule)) { return $false }
    }

    $scriptDir = Split-Path -Parent $PSCommandPath
    $isLocalModule = ($script:SCCMModulePath -like "$scriptDir*") -and (Test-Path "$scriptDir\AdminUI.PS.dll")
    $moduleDir = Split-Path -Parent $script:SCCMModulePath

    if ($isLocalModule) {
        Write-UiLog "Module detected in script directory (portable mode)." "INFO"
    }

    try {
        $oldLocation = Get-Location

        if ($isLocalModule) {
            $consoleBin = Find-ConsoleBinDirectory
            if ($consoleBin) {
                $script:ConsoleBin = $consoleBin
                Write-UiLog "SCCM console binaries found at: $consoleBin" "INFO"
                Set-Location $consoleBin
                Import-Module "$consoleBin\ConfigurationManager.psd1" -Force -ErrorAction Stop
            }
            else {
                $script:ConsoleBin = $moduleDir
                Write-UiLog "Importing from script directory (ensure DLLs are present)..." "INFO"
                Set-Location $moduleDir
                Import-Module $script:SCCMModulePath -Force -ErrorAction Stop
            }
        }
        else {
            $script:ConsoleBin = $moduleDir
            Set-Location $moduleDir
            Import-Module $script:SCCMModulePath -Force -ErrorAction Stop
        }

        try {
            $detectedSite = (Get-PSDrive -PSProvider CMSite -ErrorAction SilentlyContinue).Name
            if ($detectedSite) {
                $script:SiteCode = $detectedSite
                Set-Location "${script:SiteCode}:"
                Write-UiLog "Connected to SCCM site: $($script:SiteCode) | Server: $($script:SCCM)" "SUCCESS"
            }
            else {
                Set-Location "$($script:SC):"
                Write-UiLog "Connected to configured site: $($script:SC) | Server: $($script:SCCM)" "SUCCESS"
            }
        }
        catch {
            Write-UiLog "Could not auto-detect site code. Using configured: $($script:SC)" "WARNING"
        }

        $script:IsSCCMLoaded = $true
        Set-Status -Color $brush.Green -Text "SCCM Connected"
        return $true
    }
    catch {
        Set-Location $oldLocation -ErrorAction SilentlyContinue
        Write-UiLog "Failed to import SCCM module: $_" "ERROR"
        Write-UiLog "Ensure ConfigurationManager.psd1 and its dependent DLLs are present." "ERROR"
        $script:IsSCCMLoaded = $false
        return $false
    }
    finally {
        Update-Summary
    }
}

################################################################################
#  STATUS DOT HELPER
################################################################################
function Set-Status {
    param([System.Windows.Media.Brush]$Color, [string]$Text)
    $StatusDot.Fill = $Color
    $StatusHeader.Text = $Text
    $StatusHeader.Foreground = $Color
}

################################################################################
#  CONFIRMATION DIALOG — MAC OVERWRITE
#  Unified WPF design matching the pre-stage confirmation dialog.
#  Shows existing device details vs new details in a card layout.
################################################################################
function Show-OverwriteDialog {
    param(
        [string]$ExistingName,
        [string]$NewName,
        [string]$MacAddress,
        [string]$TargetOU,
        [string]$DomainName
    )

    $friendlyOU = ConvertTo-FriendlyOUPath -DN $TargetOU
    $Title = [System.Security.SecurityElement]::Escape("Device Already Exists")
    $eOld  = [System.Security.SecurityElement]::Escape($ExistingName)
    $eNew  = [System.Security.SecurityElement]::Escape($NewName)
    $eMac  = [System.Security.SecurityElement]::Escape($MacAddress)
    $eOU   = [System.Security.SecurityElement]::Escape($friendlyOU)
    $eDom  = [System.Security.SecurityElement]::Escape($DomainName)

    [xml]$x = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="$Title"
    SizeToContent="WidthAndHeight"
    MinWidth="480" MaxWidth="560"
    WindowStartupLocation="CenterOwner"
    ShowInTaskbar="False"
    FontFamily="Segoe UI" FontSize="13"
    Background="#F6F8FB"
    Topmost="True"
    UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <DropShadowEffect x:Key="DlgShadow" BlurRadius="12" ShadowDepth="2" Opacity="0.10" Color="#102A43"/>
        <SolidColorBrush x:Key="Navy" Color="#031926"/>
        <SolidColorBrush x:Key="Gold" Color="#C9A23D"/>
        <SolidColorBrush x:Key="WarningBg" Color="#FFFBEB"/>
        <SolidColorBrush x:Key="AccentBar" Color="#F59E0B"/>
        <SolidColorBrush x:Key="TextDark" Color="#1F2D3A"/>
        <SolidColorBrush x:Key="TextMid" Color="#475467"/>
        <SolidColorBrush x:Key="TextLight" Color="#7C8BA1"/>
        <SolidColorBrush x:Key="CardBg" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="Border" Color="#E6EBF4"/>
    </Window.Resources>
    <Grid Margin="10">
        <Border Background="White" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="6" Effect="{StaticResource DlgShadow}">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Header -->
                <Border Grid.Row="0" Padding="14,12,14,10" BorderBrush="{StaticResource Border}" BorderThickness="0,0,0,1">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Width="5" Height="24" Background="{StaticResource AccentBar}" CornerRadius="3" Margin="0,0,12,0"/>
                        <StackPanel Grid.Column="1" VerticalAlignment="Center">
                            <TextBlock Text="$Title" Foreground="{StaticResource TextDark}" FontSize="16" FontWeight="Bold"/>
                            <TextBlock Text="This MAC is already registered — review details below" Foreground="{StaticResource TextLight}" FontSize="11" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <!-- Detail cards -->
                <Border Grid.Row="1" Padding="16,14,16,10">
                    <StackPanel>
                        <!-- Existing Device Card -->
                        <Border Background="{StaticResource CardBg}" BorderBrush="#FDE68A" BorderThickness="1" CornerRadius="5" Padding="14,10" Margin="0,0,0,10">
                            <StackPanel>
                                <TextBlock Text="EXISTING DEVICE" Foreground="#92400E" FontSize="10" FontWeight="Bold" Margin="0,0,0,8"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="80"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="22"/>
                                        <RowDefinition Height="22"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Name" Foreground="{StaticResource TextLight}" FontSize="12"/>
                                    <TextBlock Grid.Row="0" Grid.Column="1" Text="$eOld" Foreground="#92400E" FontSize="12" FontWeight="SemiBold"/>
                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="MAC" Foreground="{StaticResource TextLight}" FontSize="12"/>
                                    <TextBlock Grid.Row="1" Grid.Column="1" Text="$eMac" Foreground="{StaticResource TextMid}" FontSize="12"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <!-- Arrow -->
                        <TextBlock Text="⮟ Updated to ⮟" Foreground="{StaticResource TextLight}" FontSize="12" HorizontalAlignment="Center" Margin="0,2,0,6"/>

                        <!-- New Device Card -->
                        <Border Background="#F0F4FF" BorderBrush="#BFDBFE" BorderThickness="1" CornerRadius="5" Padding="14,10">
                            <StackPanel>
                                <TextBlock Text="NEW DEVICE" Foreground="#1E40AF" FontSize="10" FontWeight="Bold" Margin="0,0,0,8"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="80"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="22"/>
                                        <RowDefinition Height="22"/>
                                        <RowDefinition Height="22"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Name" Foreground="{StaticResource TextLight}" FontSize="12"/>
                                    <TextBlock Grid.Row="0" Grid.Column="1" Text="$eNew" Foreground="#1E40AF" FontSize="12" FontWeight="SemiBold"/>
                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Target OU" Foreground="{StaticResource TextLight}" FontSize="12"/>
                                    <TextBlock Grid.Row="1" Grid.Column="1" Text="$eOU" Foreground="{StaticResource TextMid}" FontSize="12" TextTrimming="CharacterEllipsis"/>
                                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Domain" Foreground="{StaticResource TextLight}" FontSize="12"/>
                                    <TextBlock Grid.Row="2" Grid.Column="1" Text="$eDom" Foreground="{StaticResource TextMid}" FontSize="12"/>
                                </Grid>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </Border>

                <!-- Buttons -->
                <Border Grid.Row="2" BorderBrush="{StaticResource Border}" BorderThickness="0,1,0,0" Padding="0,10,0,10">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                        <Button x:Name="DlgYes" Content="Yes, Overwrite" Width="130" Height="30" FontSize="12.5" FontWeight="SemiBold" Cursor="Hand" Background="#F59E0B" Foreground="White" BorderThickness="0" Margin="0,0,10,0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="12,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                        <Button x:Name="DlgNo" Content="Cancel" Width="110" Height="30" FontSize="12.5" FontWeight="SemiBold" Cursor="Hand" Background="Transparent" Foreground="#475467" BorderBrush="#D7E0EC" BorderThickness="1">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="12,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#F0F2F5"/></Trigger>
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
        $d.Owner = $Window
        $script:_DialogResult = $false
        $d.FindName("DlgYes").Add_Click({ $script:_DialogResult = $true; $d.Close() })
        $d.FindName("DlgNo").Add_Click({ $script:_DialogResult = $false; $d.Close() })
        $d.ShowDialog() | Out-Null
        return $script:_DialogResult
    }
    catch {
        # Fallback: plain MessageBox for WinPE/degraded environments
        $choice = [System.Windows.MessageBox]::Show(
            "MAC $MacAddress is already registered to '$ExistingName'.`n`nOverwrite with '$NewName'?",
            "Device Already Exists", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        return ($choice -eq 'Yes')
    }
}

################################################################################
#  DEVICE PRE-STAGE EXECUTION (AdminService REST API)
#  Uses SCCM AdminService REST API for direct WMI object manipulation.
#  No local SCCM console or ConfigurationManager module required.
################################################################################
function Invoke-DevicePreStage {
    param(
        [string]$MacAddress,
        [string]$ComputerName,
        [string]$TargetOU
    )

    $normalizedMac = $MacAddress -replace '[:-]', ':'
    $siteCode = $script:SiteCode
    $adminServiceBaseUri = "https://$($script:SCCM)/AdminService/wmi"

    try {
        Write-UiLog "Pre-staging $ComputerName (MAC: $normalizedMac) → SCCM..." "INFO"

        # Re-apply TLS 1.2 / cert bypass / proxy bypass just before the HTTPS calls so the
        # compiled EXE (Windows PowerShell 5.1 / .NET Framework) negotiates TLS 1.2 correctly.
        Set-AdminServiceTls

        $securePass = ConvertTo-SecureString $script:JoinPass -AsPlainText -Force
        $userName = if ($UsernameBox.Text -match '\\') { $UsernameBox.Text } else { "$($script:Domain)\$($UsernameBox.Text)" }
        $cred = New-Object System.Management.Automation.PSCredential($userName, $securePass)

        $restCommon = @{ ContentType = "application/json"; Credential = $cred; ErrorAction = "Stop" }
        if ($PSVersionTable.PSVersion.Major -ge 7) { $restCommon.SkipCertificateCheck = $true }

        Set-Status -Color $brush.Orange -Text "Importing via API..."

        # ---------------------------------------------------------------------
        # STEP 1: Import Machine Entry (always overwrites existing records)
        # ---------------------------------------------------------------------
        $importUri = "$adminServiceBaseUri/SMS_Site.ImportMachineEntry"
        $importPayload = @{
            MACAddress = $normalizedMac
            NetbiosName = $ComputerName
            OverwriteExistingRecord = $true
        } | ConvertTo-Json

        Write-UiLog "Importing device record..." "INFO"
        $importResponse = Invoke-RestMethod -Uri $importUri -Method Post -Body $importPayload @restCommon

        # Log key fields only — avoid dumping the full JSON
        Write-UiLog "Import result: ResourceID=$($importResponse.ResourceID), MachineExists=$($importResponse.MachineExists), ReturnValue=$($importResponse.ReturnValue)" "INFO"

        # -----------------------------------------------------------------
        # Retrieve ResourceID — try response first, then poll with backoff
        # -----------------------------------------------------------------
        $resourceId = $null

        # Some AdminService versions return ResourceID directly in the response
        if ($importResponse -and $importResponse.ResourceID) {
            $resourceId = $importResponse.ResourceID
            Write-UiLog "Device registered — ResourceID $resourceId" "SUCCESS"
        }
        else {
            $maxAttempts = 6
            $sleepSec    = 2
            $queryUri    = "$adminServiceBaseUri/SMS_R_System?`$filter=NetbiosName eq '$ComputerName'&`$select=ResourceID"

            Write-UiLog "Waiting for SCCM to index the new device..." "WARNING"

            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    $resourceResponse = Invoke-RestMethod -Uri $queryUri -Method Get @restCommon
                    if ($resourceResponse.value -and $resourceResponse.value.Count -gt 0) {
                        $resourceId = $resourceResponse.value[0].ResourceID
                        Write-UiLog "Device found on retry $attempt/$maxAttempts ($($sleepSec * ($attempt - 1))s) — ResourceID $resourceId" "SUCCESS"
                        break
                    }
                }
                catch {
                    Write-UiLog "Retry $attempt failed — $($_.Exception.Message)" "WARNING"
                }

                if ($attempt -eq $maxAttempts) {
                    throw "Device not found after $maxAttempts retries (~$($sleepSec * $maxAttempts)s). SCCM database may be slow — check AdminService.log on the SCCM server."
                }

                Write-UiLog "Retrying in ${sleepSec}s..." "INFO"
                Start-Sleep -Seconds $sleepSec
            }
        }

        if (-not $resourceId) {
            throw "Failed to retrieve ResourceID. The device may not have imported correctly."
        }

        # ---------------------------------------------------------------------
        # STEP 2: Inject OSD Device Variables
        # ---------------------------------------------------------------------
        Write-UiLog "Writing OSD variables (OU: $TargetOU)..." "INFO"

        $variables = @(
            @{
                Name = "OSDComputerName"
                Value = $ComputerName
                IsMasked = $false
            },
            @{
                Name = "OSDDomainOUName"
                Value = $TargetOU
                IsMasked = $false
            },
            @{
                Name = "OSDLanguage"
                Value = $script:Lang
                IsMasked = $false
            },
            @{
                Name = "OSDRegisteredOrgName"
                Value = $script:Org
                IsMasked = $false
            },
            @{
                Name = "OSDDomainName"
                Value = $script:Domain
                IsMasked = $false
            },
            @{
                Name = "OSDJoinAccount"
                Value = $UsernameBox.Text
                IsMasked = $false
            },
            @{
                Name = "OSDJoinPassword"
                Value = $script:JoinPass
                IsMasked = $true
            }
        )

        foreach ($cb in $script:SoftCbs) {
            if ($cb.IsChecked) {
                $variables += @{
                    Name = $cb.Tag.ToString()
                    Value = "TRUE"
                    IsMasked = $false
                }
                Write-UiLog "  + $($cb.Tag)" "INFO"
            }
        }

        $settingsUri = "$adminServiceBaseUri/SMS_MachineSettings"
        $settingsPayload = @{
            ResourceID = $resourceId
            SourceSite = $siteCode
            LocaleID = 1033
            MachineVariables = $variables
        } | ConvertTo-Json -Depth 10

        $null = Invoke-RestMethod -Uri $settingsUri -Method Post -Body $settingsPayload @restCommon

        Write-UiLog "Device pre-staged successfully — $ComputerName is ready." "SUCCESS"
        Write-UiLog "PXE boot the device to begin deployment." "SUCCESS"
        Set-Status -Color $brush.Green -Text "Pre-Staged"

        return [PSCustomObject]@{ Success = $true; ResourceID = $resourceId }
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errMsg = $_.ErrorDetails.Message
        }
        elseif ($_.Exception.InnerException -and $_.Exception.InnerException.Message) {
            $errMsg = "$errMsg | Inner: $($_.Exception.InnerException.Message)"
        }
        Write-UiLog "Pre-stage failed: $errMsg" "ERROR"
        Set-Status -Color $brush.Red -Text "Error"
        return [PSCustomObject]@{ Success = $false; ResourceID = $null }
    }
}

################################################################################
#  EVENT HANDLERS
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
        Write-UiLog "Signed in as $($UsernameBox.Text)" "SUCCESS"

        $AuthLoginPanel.Visibility = "Collapsed"
        $AuthWelcomePanel.Visibility = "Visible"
        $AuthWelcomeText.Text = "Signed in as $($UsernameBox.Text)"
        $AuthSubtitle.Text = "Authenticated"
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

$SignOutBtn.Add_Click({
    $script:IsLoggedIn = $false
    $script:JoinPass = ""
    $PasswordBox.Password = ""
    $AuthLoginPanel.Visibility = "Visible"
    $AuthWelcomePanel.Visibility = "Collapsed"
    $AuthSubtitle.Text = "Enter domain credentials to proceed"
    Hide-AuthBanner
    $StatusDot.Fill = $brush.Orange
    $StatusHeader.Text = "Ready"
    $StatusHeader.Foreground = $brush.Orange
    Update-Summary
    Write-UiLog "Signed out." "INFO"
})

$ClearLogBtn.Add_Click({
    $LogBox.Document.Blocks.Clear()
    Write-UiLog "Log cleared." "INFO"
})

$CopyLogBtn.Add_Click({
    $range = New-Object System.Windows.Documents.TextRange($LogBox.Document.ContentStart, $LogBox.Document.ContentEnd)
    [System.Windows.Clipboard]::SetText($range.Text)
    Write-UiLog "Log copied to clipboard." "SUCCESS"
})

$ComputerNameBox.Add_TextChanged({ Update-Summary })

$LangEnglish.Add_Checked({
    $script:Lang = "en-US"
    Update-Summary
})
$LangArabic.Add_Checked({
    $script:Lang = "ar-SA"
    Update-Summary
})

$MacAddressBox.Add_TextChanged({
    Hide-MacBanner
    $mac = $MacAddressBox.Text.Trim()
    if ($mac.Length -gt 0) {
        if (Test-MacAddress -Mac $mac) {
            Show-MacBanner -Type Success -M "Valid MAC address format."
        }
        else {
            Show-MacBanner -Type Error -M "Invalid format. Use: 00:11:22:AA:BB:CC"
        }
    }
    Update-Summary
})

$MacAddressBox.Add_LostKeyboardFocus({
    $current = $MacAddressBox.Text
    $formatted = Format-MacAddress -Raw $current
    if ($formatted -ne $current) {
        $MacAddressBox.Text = $formatted
    }
})

$MacAddressBox.Add_GotFocus({
    $MacAddressBox.SelectAll()
})

$OUSearchBox.Add_TextChanged({ Filter-OUDataGrid -F $OUSearchBox.Text })
$OUSearchBtn.Add_Click({ Filter-OUDataGrid -F $OUSearchBox.Text })

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

    Set-Status -Color $brush.Gold -Text "Refreshed"
    Write-UiLog "All data refreshed" "INFO"
})

################################################################################
#  PRE-STAGE BUTTON
################################################################################
$PrestageBtn.Add_Click({
    if (-not $script:IsLoggedIn) {
        Show-CustomDialog -Type Warning -T "Auth Required" -M "Please sign in first."
        return
    }
    $mac = $MacAddressBox.Text.Trim()
    $computerName = $ComputerNameBox.Text.Trim()

    if (-not (Test-MacAddress -Mac $mac)) {
        Show-CustomDialog -Type Warning -T "Invalid MAC" -M "Please enter a valid MAC address (e.g. 00:11:22:AA:BB:CC)."
        return
    }
    if ([string]::IsNullOrWhiteSpace($computerName)) {
        Show-CustomDialog -Type Warning -T "Name Required" -M "Enter a computer name."
        return
    }
    if ($computerName -match '[\\\/\:\*\?\"\<\>\|]') {
        Show-CustomDialog -Type Warning -T "Invalid Name" -M "Name contains invalid characters."
        return
    }
    if ($computerName.Length -gt 15) {
        Show-CustomDialog -Type Warning -T "Name Too Long" -M "Max 15 characters."
        return
    }
    $sel = $OUDataGrid.SelectedItem
    if (-not $sel -or -not $sel.DN) {
        Show-CustomDialog -Type Warning -T "OU Required" -M "Please search and select a target OU."
        return
    }

    Write-UiLog "Signed in as $($UsernameBox.Text) | SCCM: $($script:SCCM)" "INFO"

    $checkedSw = @($script:SoftCbs | Where-Object { $_.IsChecked } | ForEach-Object { $_.Content })
    $swList = if ($checkedSw.Count -gt 0) { ($checkedSw -join ", ") } else { "None" }

    $scn  = [System.Security.SecurityElement]::Escape($computerName)
    $smn  = [System.Security.SecurityElement]::Escape($mac)
    $son  = [System.Security.SecurityElement]::Escape($sel.Name)
    $sdn  = [System.Security.SecurityElement]::Escape($sel.DN)
    $sdnm = [System.Security.SecurityElement]::Escape($script:Domain)
    $sln  = [System.Security.SecurityElement]::Escape($(if ($LangArabic.IsChecked) { "Arabic" } else { "English" }))
    $sogn = [System.Security.SecurityElement]::Escape($script:Org)
    $sjan = [System.Security.SecurityElement]::Escape($UsernameBox.Text)
    $ssn  = [System.Security.SecurityElement]::Escape($swList)

    [xml]$confirmXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Confirm Pre-Stage"
    SizeToContent="WidthAndHeight"
    MinWidth="620" MaxWidth="740"
    WindowStartupLocation="CenterOwner"
    ShowInTaskbar="False"
    FontFamily="Segoe UI" FontSize="13"
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
                        <Border Grid.Column="0" Width="5" Height="28" Background="#3B82F6" CornerRadius="3" Margin="0,0,10,0"/>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="Confirm Pre-Stage" Foreground="#1F2D3A" FontSize="16" FontWeight="Bold"/>
                            <TextBlock Text="Review details before submitting" Foreground="#5F6B7A" FontSize="12" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>
                <StackPanel Grid.Row="1" Margin="14,12,14,12">
                    <TextBlock Text="Device Details" FontSize="14" FontWeight="Bold" Foreground="#1F2D3A" Margin="0,0,0,6"/>
                    <Border Background="#F8FAFC" BorderBrush="#E6EBF4" BorderThickness="1" CornerRadius="5" Padding="14,12">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="122"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Row="0" Grid.Column="0" Text="Computer Name" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="0" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$scn" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="1" Grid.Column="0" Text="MAC Address" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="1" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$smn" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="2" Grid.Column="0" Text="Target OU" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="2" Grid.Column="1" Background="White" BorderBrush="#E6EBF4" BorderThickness="1" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$son" FontSize="13" FontWeight="SemiBold" Foreground="#1F2D3A" TextTrimming="CharacterEllipsis" ToolTip="$sdn"/></Border>
                            <TextBlock Grid.Row="3" Grid.Column="0" Text="Domain" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="3" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sdnm" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="4" Grid.Column="0" Text="Language" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="4" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sln" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="5" Grid.Column="0" Text="Organization" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="5" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sogn" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="6" Grid.Column="0" Text="Join Account" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="6" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sjan" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="7" Grid.Column="0" Text="Software" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,0"/>
                            <Border Grid.Row="7" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3"><TextBlock Text="$ssn" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8" TextTrimming="CharacterEllipsis" ToolTip="$ssn"/></Border>
                        </Grid>
                    </Border>
                </StackPanel>
                <Border Grid.Row="2" BorderBrush="#E6EBF4" BorderThickness="0,1,0,0" Padding="0,12,0,12">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                        <Button x:Name="ConfirmYes" Content="Yes, Pre-Stage" Width="130" Height="28" FontSize="13" FontWeight="SemiBold" Cursor="Hand" Background="#28A745" Foreground="White" BorderThickness="0" Margin="0,0,10,0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" CornerRadius="4" Padding="10,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                        <Button x:Name="ConfirmNo" Content="Cancel" Width="90" Height="28" FontSize="13" FontWeight="SemiBold" Cursor="Hand" Background="Transparent" Foreground="#475467" BorderBrush="#D7E0EC" BorderThickness="1">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="10,0">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#F0F2F5"/></Trigger>
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
        $cr = New-Object System.Xml.XmlNodeReader $confirmXaml
        $cd = [Windows.Markup.XamlReader]::Load($cr)
        $cd.Owner = $Window
        $script:_ConfirmResult = $false
        $cd.FindName("ConfirmYes").Add_Click({ $script:_ConfirmResult = $true; $cd.Close() })
        $cd.FindName("ConfirmNo").Add_Click({ $script:_ConfirmResult = $false; $cd.Close() })
        $cd.ShowDialog() | Out-Null
        if (-not $script:_ConfirmResult) { return }
    }
    catch {
        Write-UiLog "Confirm dialog failed: $($_.Exception.Message)" "ERROR"
        $fallback = [System.Windows.MessageBox]::Show("Pre-stage device '$computerName'?", "Confirm Pre-Stage", "YesNo", "Question")
        if ($fallback -ne 'Yes') { return }
    }

    $PrestageBtn.Content = "Staging..."
    $PrestageBtn.IsEnabled = $false
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait

    $maxRetries = 2
    $attempt = 0
    $result = $null
    do {
        $attempt++
        $result = Invoke-DevicePreStage -MacAddress $mac -ComputerName $computerName -TargetOU $sel.DN
        if ($result.Success) { break }
        if ($attempt -lt $maxRetries) {
            $retry = Show-CustomDialog -Type Error -T "Pre-Stage Error" -M "Pre-stage failed.`n`nRetry (attempt $attempt of $($maxRetries-1))?" -YesNo
            if (-not $retry) { break }
        }
    } while (-not $result.Success -and $attempt -lt $maxRetries)

    $PrestageBtn.Content = "Add Device"
    $PrestageBtn.IsEnabled = $true
    $Window.Cursor = $null

    if ($result.Success) {
        $sc  = [System.Security.SecurityElement]::Escape($computerName)
        $sm  = [System.Security.SecurityElement]::Escape($mac)
        $so  = [System.Security.SecurityElement]::Escape($sel.Name)
        $sd  = [System.Security.SecurityElement]::Escape($script:Domain)
        $sdn = [System.Security.SecurityElement]::Escape($sel.DN)
        $sl  = [System.Security.SecurityElement]::Escape($script:Lang)
        $sorg = [System.Security.SecurityElement]::Escape($script:Org)
        $sja  = [System.Security.SecurityElement]::Escape($UsernameBox.Text)

        $checkedSw = @($script:SoftCbs | Where-Object { $_.IsChecked } | ForEach-Object { $_.Content })
        $ss  = if ($checkedSw.Count -gt 0) { [System.Security.SecurityElement]::Escape(($checkedSw -join ", ")) } else { "None" }

        [xml]$dx = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Pre-Stage Complete"
    SizeToContent="WidthAndHeight"
    MinWidth="620" MaxWidth="740"
    WindowStartupLocation="CenterOwner"
    ShowInTaskbar="False"
    FontFamily="Segoe UI" FontSize="13"
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
                        <Border Grid.Column="0" Width="5" Height="28" Background="#28A745" CornerRadius="3" Margin="0,0,10,0"/>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="Device Pre-Staged Successfully" Foreground="#1F2D3A" FontSize="16" FontWeight="Bold"/>
                            <TextBlock Text="Computer: $sc | MAC: $sm" Foreground="#5F6B7A" FontSize="12" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>
                <StackPanel Grid.Row="1" Margin="14,12,14,12">
                    <TextBlock Text="Device Details" FontSize="14" FontWeight="Bold" Foreground="#1F2D3A" Margin="0,0,0,6"/>
                    <Border Background="#F8FAFC" BorderBrush="#E6EBF4" BorderThickness="1" CornerRadius="5" Padding="14,12">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="122"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Row="0" Grid.Column="0" Text="Computer Name" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="0" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sc" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="1" Grid.Column="0" Text="MAC Address" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="1" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sm" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="2" Grid.Column="0" Text="Target OU" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="2" Grid.Column="1" Background="White" BorderBrush="#E6EBF4" BorderThickness="1" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$so" FontSize="13" FontWeight="SemiBold" Foreground="#1F2D3A" TextTrimming="CharacterEllipsis" ToolTip="$sdn"/></Border>
                            <TextBlock Grid.Row="3" Grid.Column="0" Text="Domain" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="3" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sd" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="4" Grid.Column="0" Text="Language" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="4" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sl" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="5" Grid.Column="0" Text="Organization" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="5" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sorg" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="6" Grid.Column="0" Text="Join Account" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="6" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="$sja" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="7" Grid.Column="0" Text="Join Password" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,4"/>
                            <Border Grid.Row="7" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3" Margin="0,0,0,4"><TextBlock Text="********" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8"/></Border>
                            <TextBlock Grid.Row="8" Grid.Column="0" Text="Software" FontWeight="SemiBold" Foreground="#475467" VerticalAlignment="Center" Margin="0,0,6,0"/>
                            <Border Grid.Row="8" Grid.Column="1" Background="#EEF2FF" CornerRadius="4" Padding="6,3"><TextBlock Text="$ss" FontSize="13" FontWeight="SemiBold" Foreground="#1D4ED8" TextTrimming="CharacterEllipsis" ToolTip="$ss"/></Border>
                        </Grid>
                    </Border>
                </StackPanel>
                <Border Grid.Row="2" BorderBrush="#E6EBF4" BorderThickness="0,1,0,0" Padding="0,12,0,12">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                        <Button
                            x:Name="DlgOk"
                            Content="OK"
                            Width="90" Height="28"
                            FontSize="13" FontWeight="SemiBold"
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
            $dd.FindName("DlgOk").Add_Click({ $dd.Close() })
            $dd.Owner = $Window
            $dd.ShowDialog() | Out-Null
        }
        catch {
            Write-UiLog "Result dialog failed: $($_.Exception.Message)" "ERROR"
            Show-CustomDialog -Type Success -T "Pre-Stage Complete" -M "Device pre-staged successfully!" | Out-Null
        }
        $MacAddressBox.Text = ""
        $ComputerNameBox.Text = ""
        $OUDataGrid.SelectedItem = $null
        $OUSelectedInfo.Visibility = "Collapsed"
        Write-UiLog "Ready for next device." "INFO"
        Update-Summary
    }
})

################################################################################
#  STARTUP & WINDOW LIFECYCLE
################################################################################
$script:Closing = $false

$Window.Add_Loaded({
    if ($script:Lang -eq "ar-SA") { $LangArabic.IsChecked = $true } else { $LangEnglish.IsChecked = $true }
    Update-OUList
    Update-Summary
    [System.Windows.Input.Keyboard]::Focus($UsernameBox)
    $Window.Activate() | Out-Null
})

$Window.Add_Closing({
    $script:Closing = $true
    $script:OUData = $null
})

        Write-UiLog "Ready. $($script:Domain) | Site $($script:SC) | $($script:SCCM)" "INFO"
        Write-UiLog "Sign in, enter MAC + name, select OU, then Pre-Stage." "INFO"
$Window.ShowDialog() | Out-Null
