<#
With legal notice / caption added to the script

Checks Windows logon legal notice values and logs whether they are empty or populated, and if populated logs the actual content.

Registry:
  HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System
    - LegalNoticeCaption
    - LegalNoticeText

Log output behavior (C:\Temp\SystemCheck.log):
- If empty/missing/whitespace: logs "EMPTY"
- If populated: logs "POPULATED" and the value content
- If key can't be read: logs read failure + error message

HTML behavior (C:\Temp\SystemInfoReport.html):
- Shows only status (Has content / Empty) and checkmark/X
- Does NOT render the full legal notice text in HTML (to avoid giant/unsafe output)

Compatible with PowerShell v5 and v7.
#>

# -------------------------------
# Paths & Logging Setup
# -------------------------------
$OutputFolder = "C:\Temp"
$LogFolder    = $OutputFolder
if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

$LogFile    = Join-Path $LogFolder "SystemCheck.log"
$HtmlFile   = Join-Path $LogFolder "SystemInfoReport.html"   # final combined HTML
$FontOutput = "C:\applog\FontCheckResults.txt"

# Ensure log folder exists
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

# Start log file
[System.IO.File]::WriteAllText(
    $LogFile,
    "===== Script Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====`r`n",
    [System.Text.Encoding]::UTF8
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp  $Message"
    [System.IO.File]::AppendAllText(
        $LogFile,
        $line + [Environment]::NewLine,
        [System.Text.Encoding]::UTF8
    )
}

Write-Log "Merged script started."

# -------------------------------
# Script A: Collect System Info (includes BIOS Version)
# -------------------------------
Write-Log "Collecting system information (Script A portion)..."

$StartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$MachineName = $env:COMPUTERNAME

try {
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $SerialNumber = if ($bios.SerialNumber) { $bios.SerialNumber } else { "Unknown" }
    $BIOSVersion = if ($bios.SMBIOSBIOSVersion) { $bios.SMBIOSBIOSVersion } elseif ($bios.Version) { $bios.Version } else { "Unknown" }
} catch {
    $SerialNumber = "Unknown"
    $BIOSVersion  = "Unknown"
}

try {
    $LoggedInUser = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
    if (-not $LoggedInUser) { $LoggedInUser = "No interactive user logged in" }
} catch {
    $LoggedInUser = "Unknown"
}

try {
    $BootTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    $UptimeTimespan = (Get-Date) - $BootTime
    $UptimeFormatted = "{0} days {1} hours {2} minutes" -f `
        $UptimeTimespan.Days, $UptimeTimespan.Hours, $UptimeTimespan.Minutes
} catch {
    $UptimeFormatted = "Unknown"
}

$FinishTime_SystemInfo = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Log ("System information collected. BIOS Version: {0}" -f $BIOSVersion)

# -------------------------------
# Script B: Checks (Fonts, M365, Languages, Activation, Local Admin)
# -------------------------------
Write-Log "Starting Script B checks..."

# Symbols (HTML spans) for ok / bad
$OkSymbolHtml  = "<span class='ok'>&#10004;</span>"
$BadSymbolHtml = "<span class='bad'>&#10008;</span>"

# -------------------------------
# SECTION 1 — FONT CHECK
# -------------------------------
Write-Log "Starting font check..."

$fontName = @("SimHei", "Gulim", "GulimChe", "Meiryo", "Meiryo Ui", "MingLIU")
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
$fontCollection = [System.Drawing.Text.InstalledFontCollection]::new()
$fontResults = @()
foreach ($name in $fontName) {
    $found = $fontCollection.Families | Where-Object { $_.Name -like "$name" }
    if ($found) {
        $msg = "$name is installed."
        $fontResults += $msg
        Write-Log $msg
    } else {
        $msg = "$name is NOT installed."
        $fontResults += $msg
        Write-Log $msg
    }
}
$fontFolder = Split-Path $FontOutput -Parent
if ($fontFolder -and -not (Test-Path $fontFolder)) {
    New-Item -Path $fontFolder -ItemType Directory -Force | Out-Null
}
$fontResults | Out-File -FilePath $FontOutput -Encoding UTF8
Write-Log "Font check completed. Results saved to $FontOutput"

# -------------------------------
# SECTION 2 — M365 COMPONENT CHECK
# -------------------------------
Write-Log "Starting M365 component check..."

function Get-AppPath {
    param([Parameter(Mandatory=$true)][string]$ExeName)
    $regKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExeName",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$ExeName"
    )
    foreach ($key in $regKeys) {
        if (Test-Path $key) {
            $val = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).'(default)'
            if (-not $val) { $val = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)."(Default)" }
            if ($val -and (Test-Path $val)) { return $val }
        }
    }
    return $null
}

function Get-M365Components {
    $components = @{
        "Word"       = "WINWORD.EXE"
        "Excel"      = "EXCEL.EXE"
        "Access"     = "MSACCESS.EXE"
        "PowerPoint" = "POWERPNT.EXE"
        "Outlook"    = "OUTLOOK.EXE"
        "OneNote"    = "ONENOTE.EXE"
    }
    $results = @()
    foreach ($component in $components.GetEnumerator()) {
        $exePath  = Get-AppPath -ExeName $component.Value
        $installed = $false
        if ($exePath -and (Test-Path $exePath)) { $installed = $true }
        $logSymbol  = if ($installed) { "✔" } else { "✘" }
        $htmlSymbol = if ($installed) { $OkSymbolHtml } else { $BadSymbolHtml }
        $results += [PSCustomObject]@{
            Component  = $component.Key
            LogSymbol  = $logSymbol
            HtmlSymbol = $htmlSymbol
            Path       = $exePath
        }
    }
    return $results
}

$officeResults = Get-M365Components
foreach ($item in $officeResults) {
    $pathText = if ($item.Path) { $item.Path } else { "Not found" }
    Write-Log ("{0} Installed: {1} (Path: {2})" -f $item.Component, $item.LogSymbol, $pathText)
}

# -------------------------------
# SECTION 3 — LANGUAGE PACK CHECK
# -------------------------------
Write-Log "Starting language pack check..."
$LanguageList = @(
    @{ Code="en-US"; Name="English (United States)" },
    @{ Code="de-DE"; Name="German (Germany)" },
    @{ Code="el-GR"; Name="Greek (Greece)" },
    @{ Code="es-ES"; Name="Spanish (Spain)" },
    @{ Code="fr-FR"; Name="French (France)" },
    @{ Code="ja-JP"; Name="Japanese" },
    @{ Code="ko-KR"; Name="Korean" },
    @{ Code="it-IT"; Name="Italian (Italy)" },
    @{ Code="nl-NL"; Name="Dutch (Netherlands)" },
    @{ Code="pt-BR"; Name="Portuguese (Brazil)" },
    @{ Code="pt-PT"; Name="Portuguese (Portugal)" },
    @{ Code="th-TH"; Name="Thai" },
    @{ Code="zh-CN"; Name="Chinese (Simplified)" },
    @{ Code="zh-TW"; Name="Chinese (Traditional)" }
)
try {
    $InstalledLangs = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName
} catch {
    $InstalledLangs = @()
}
$LanguageResults = @()
foreach ($lang in $LanguageList) {
    $installed = $InstalledLangs -contains $lang.Code
    $htmlSymbol = if ($installed) { $OkSymbolHtml } else { $BadSymbolHtml }
    $installedText = if ($installed) { 'Yes' } else { 'No' }
    Write-Log ("Language {0} ({1}) Installed: {2}" -f $lang.Code, $lang.Name, $installedText)
    $LanguageResults += [PSCustomObject]@{
        Code       = $lang.Code
        Name       = $lang.Name
        HtmlSymbol = $htmlSymbol
    }
}

# -------------------------------
# SECTION 4 — OFFICE ACTIVATION CHECK
# -------------------------------
Write-Log "Starting Office activation check (Device-Based Licensing + OSPP.VBS fallback)..."

function Get-OfficeActivationStatus {
    $statusValue = "Not Activated"
    $channelValue = "N/A"
    $expiryValue = "N/A"
    $last5 = "N/A"
    $activated = $false

    $dblPath = "C:\ProgramData\Microsoft\Office\Licenses\Device"
    if (Test-Path $dblPath) {
        try {
            $xmlFiles = Get-ChildItem $dblPath -Filter "*.xml" -ErrorAction SilentlyContinue
            if ($xmlFiles -and $xmlFiles.Count -gt 0) {
                $xmlFile = $xmlFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                $xml = [xml](Get-Content $xmlFile.FullName -ErrorAction Stop)
                $statusValue = $xml.LicenseData.LicenseStatus
                $channelValue = $xml.LicenseData.LicenseType
                $expiryValue = $xml.LicenseData.ExpirationDate
                if (-not $statusValue) { $statusValue = "Activated" }
                if (-not $channelValue) { $channelValue = "Device-Based Licensing" }
                if (-not $expiryValue) { $expiryValue = "Unknown" }
                if ($statusValue -match "Active|Activated") { $activated = $true }
                Write-Log ("DBL: Status={0}, Channel={1}, Expiration={2}" -f $statusValue, $channelValue, $expiryValue)
            }
        } catch {
            Write-Log ("DBL parse failed: {0}" -f $_.Exception.Message)
        }
    }

    $osppCandidates = @(
        "$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS",
        "$env:ProgramFiles(x86)\Microsoft Office\Office16\OSPP.VBS",
        "$env:ProgramFiles\Microsoft Office\Office15\OSPP.VBS",
        "$env:ProgramFiles(x86)\Microsoft Office\Office15\OSPP.VBS",
        "$env:ProgramFiles\Microsoft Office\Office14\OSPP.VBS",
        "$env:ProgramFiles(x86)\Microsoft Office\Office14\OSPP.VBS"
    )
    $osppPath = $osppCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $osppPath) {
        try {
            $found = Get-ChildItem -Path "$env:ProgramFiles","$env:ProgramFiles(x86)" -Filter "OSPP.VBS" -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1
            if ($found) { $osppPath = $found.FullName }
        } catch {}
    }

    if ($osppPath) {
        Write-Log ("Found OSPP.VBS at {0}" -f $osppPath)
        try {
            $cscriptOutput = & cscript.exe //Nologo $osppPath /dstatus 2>&1
            $last5Lines = $cscriptOutput | Select-String -Pattern 'Last 5' -SimpleMatch
            if ($last5Lines) { $last5 = ($last5Lines[0].ToString() -replace '.*Last 5.*:\s*','').Trim() }
            $licLines = $cscriptOutput | Select-String -Pattern 'LICENSE STATUS' -SimpleMatch
            if ($licLines) {
                foreach ($l in $licLines) {
                    $text = $l.ToString() -replace '.*LICENSE STATUS:\s*',''
                    if ($text -match 'LICENSED|Licensed|---Licensed---') { $activated = $true }
                    if (-not ($statusValue) -or $statusValue -eq "Not Activated") { $statusValue = $text.Trim() }
                }
            }
            $nameLine = $cscriptOutput | Select-String -Pattern 'LICENSE NAME' -SimpleMatch | Select-Object -First 1
            if ($nameLine) { $nameText = $nameLine.ToString() -replace '.*LICENSE NAME:\s*',''; if ($nameText) { $channelValue = $nameText.Trim() } }
            Write-Log "OSPP.VBS /dstatus executed and parsed."
        } catch {
            Write-Log ("OSPP.VBS execution failed: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-Log "OSPP.VBS not found on system (skipping cscript method)."
    }

    $htmlSymbol = if ($activated) { $OkSymbolHtml } else { $BadSymbolHtml }
    if (-not $last5) { $last5 = "N/A" }

    return [PSCustomObject]@{
        Status     = $statusValue
        Key        = $last5
        Channel    = $channelValue
        SCA        = "N/A"
        Expiration = $expiryValue
        HtmlSymbol = $htmlSymbol
    }
}

$ActivationResult = Get-OfficeActivationStatus

# -------------------------------
# SECTION 5 — LOCAL ADMINISTRATOR PASSWORD CHECK
# -------------------------------
Write-Log "Checking local Administrator account password status..."
function Get-LocalAdminPasswordStatus {
    try {
        $admin = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID -match "-500$" }
    } catch { $admin = $null }

    if (-not $admin) {
        Write-Log "Local Administrator account not found."
        return [PSCustomObject]@{
            Account = "Administrator"
            Enabled = "Unknown"
            BlankPassword = "Unknown"
            HtmlSymbol = $BadSymbolHtml
        }
    }

    $blank = $false
    try { $blank = $admin.PasswordRequired -eq $false } catch {}
    $blankStatus = if ($blank) { "Yes (Insecure)" } else { "No" }
    $enabledStatus = if ($admin.Enabled) { "Enabled" } else { "Disabled" }
    $htmlSymbol = if ($blank) { $BadSymbolHtml } else { $OkSymbolHtml }
    Write-Log ("Local Administrator: Enabled={0}, BlankPassword={1}" -f $enabledStatus, $blankStatus)
    return [PSCustomObject]@{
        Account = "Administrator"
        Enabled = $enabledStatus
        BlankPassword = $blankStatus
        HtmlSymbol = $htmlSymbol
    }
}
$LocalAdminResult = Get-LocalAdminPasswordStatus
Write-Log "Script B checks completed."

# -------------------------------
# Executable details function & execution
# -------------------------------
function Get-ExecutableDetails {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fileInfo = Get-Item -Path $Path -ErrorAction Stop
    $versionInfo = $fileInfo.VersionInfo
    [PSCustomObject]@{
        FilePath       = $fileInfo.FullName
        ProductName    = $versionInfo.ProductName
        FileVersion    = $versionInfo.FileVersion
        ProductVersion = $versionInfo.ProductVersion
        CreationDate   = $fileInfo.CreationTime
    }
}

$executablePath = "C:\blp\Wintrv\wintrv.exe"
try {
    $ExeDetails = Get-ExecutableDetails -Path $executablePath
    Write-Log ("Executable details retrieved for {0}" -f $executablePath)
} catch {
    Write-Log ("Failed to retrieve executable details for {0}: {1}" -f $executablePath, $_.Exception.Message)
    $ExeDetails = [PSCustomObject]@{
        FilePath = $executablePath
        ProductName = "N/A"
        FileVersion = "N/A"
        ProductVersion = "N/A"
        CreationDate = "N/A"
    }
}

# --------------------------------------------------
# Bloomberg Excel add-on checks
# --------------------------------------------------
Write-Log "Checking Excel add-ons (Bloomberg) presence..."
$AddOnFiles = @(
    @{ Name = "Bloombergui.xla"; Path = "C:\blp\API\Office Tools\Bloombergui.xla" },
    @{ Name = "bofaddin.dll"    ; Path = "C:\blp\API\office tools\bofaddin.dll" }
)
$AddOnResults = @()
foreach ($entry in $AddOnFiles) {
    $path = $entry.Path
    try { $exists = Test-Path -Path $path } catch { $exists = $false }
    if ($exists) { $symbol = $OkSymbolHtml; $existsText = "Yes" } else { $symbol = $BadSymbolHtml; $existsText = "No" }
    $AddOnResults += [PSCustomObject]@{
        Name      = $entry.Name
        Path      = $path
        Exists    = $exists
        HtmlSymbol= $symbol
        ExistsText= $existsText
    }
    Write-Log ("Add-on {0} present: {1} (Path: {2})" -f $entry.Name, $existsText, $path)
}

# --------------------------------------------------
# Legal Notice checks (LOGS ACTUAL VALUES)
# --------------------------------------------------
Write-Log "Checking Legal Notice registry values (will log actual content if present)..."

$LegalNoticeRegPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$LegalNoticeReadOk  = $true
$LegalNoticeReadError = ""

$LegalNoticeCaptionValue = $null
$LegalNoticeTextValue    = $null

try {
    # IMPORTANT: correct value names are LegalNoticeCaption and LegalNoticeText
    $ln = Get-ItemProperty -Path $LegalNoticeRegPath -ErrorAction Stop
    try { $LegalNoticeCaptionValue = $ln.LegalNoticeCaption } catch { $LegalNoticeCaptionValue = $null }
    try { $LegalNoticeTextValue    = $ln.LegalNoticeText } catch { $LegalNoticeTextValue = $null }
} catch {
    $LegalNoticeReadOk = $false
    $LegalNoticeReadError = $_.Exception.Message
    Write-Log ("Unable to read {0}: {1}" -f $LegalNoticeRegPath, $LegalNoticeReadError)
}

$LegalNoticeCaptionHasContent = -not [string]::IsNullOrWhiteSpace([string]$LegalNoticeCaptionValue)
$LegalNoticeTextHasContent    = -not [string]::IsNullOrWhiteSpace([string]$LegalNoticeTextValue)

# Log: EMPTY vs POPULATED + actual content
if (-not $LegalNoticeReadOk) {
    Write-Log "LegalNoticeCaption: UNKNOWN (read failed)"
    Write-Log "LegalNoticeText: UNKNOWN (read failed)"
} else {
    if ($LegalNoticeCaptionHasContent) {
        Write-Log "LegalNoticeCaption: POPULATED"
        Write-Log ("LegalNoticeCaption Value: {0}" -f ([string]$LegalNoticeCaptionValue))
    } else {
        Write-Log "LegalNoticeCaption: EMPTY"
    }

    if ($LegalNoticeTextHasContent) {
        Write-Log "LegalNoticeText: POPULATED"
        Write-Log ("LegalNoticeText Value: {0}" -f ([string]$LegalNoticeTextValue))
    } else {
        Write-Log "LegalNoticeText: EMPTY"
    }
}

# HTML status variables
if ($LegalNoticeReadOk) {
    if ($LegalNoticeCaptionHasContent) { $LegalNoticeCaptionStatus = "Has content" } else { $LegalNoticeCaptionStatus = "Empty" }
    if ($LegalNoticeTextHasContent)    { $LegalNoticeTextStatus    = "Has content" } else { $LegalNoticeTextStatus    = "Empty" }
} else {
    $LegalNoticeCaptionStatus = "Unknown (read failed)"
    $LegalNoticeTextStatus    = "Unknown (read failed)"
}

if ($LegalNoticeCaptionHasContent) { $LegalNoticeCaptionSymbol = $OkSymbolHtml } else { $LegalNoticeCaptionSymbol = $BadSymbolHtml }
if ($LegalNoticeTextHasContent)    { $LegalNoticeTextSymbol    = $OkSymbolHtml } else { $LegalNoticeTextSymbol    = $BadSymbolHtml }

# -----------------------------------------------------------------------------
# Build the Combined HTML Report
# -----------------------------------------------------------------------------

$ReportHeader = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>System & M365 Report</title>
<style>
    body { font-family: Segoe UI, Arial, sans-serif; background-color: #f4f6f9; padding: 20px; color: #333; }
    h1 { color: #1f3758; }
    h2 { color: #2a4d8f; border-bottom: 2px solid #2a4d8f; padding-bottom: 5px; margin-bottom: 12px; }
    .info-table { width: 60%; border-collapse: collapse; background: #ffffff; border-radius: 6px; overflow: hidden; box-shadow: 0 2px 6px rgba(0,0,0,0.08); margin-bottom: 20px; }
    .info-table th { background-color: #2a4d8f; color: white; text-align: left; padding: 10px; width: 20%; white-space: nowrap; }
    .info-table td { padding: 10px; border-bottom: 1px solid #e0e0e0; color: #333333; }
    .log { margin-top: 8px; font-size: 14px; color: #444; }
    table.section { border-collapse: collapse; width: 80%; margin-bottom: 18px; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.06); }
    table.section th, table.section td { border: 1px solid #ccc; padding: 8px; text-align: left; font-size: 14px; vertical-align: top; }
    table.section th { background: #efefef; }
    .ok  { color: #28a745; font-weight: bold; font-size: 18px; }
    .bad { color: #d9534f; font-weight: bold; font-size: 18px; }
    .small { font-size: 12px; color: #666; }
</style>
</head>
<body>
<h1>QA & M365 Comprehensive Report</h1>
"@

$SystemSection = @"
<h2>System Information Summary</h2>
<table class='info-table'>
    <tr><th>Machine Name</th><td>$MachineName</td></tr>
    <tr><th>Serial Number</th><td>$SerialNumber</td></tr>
    <tr><th>BIOS Version</th><td>$BIOSVersion</td></tr>
    <tr><th>Logged-in User</th><td>$LoggedInUser</td></tr>
    <tr><th>System Uptime</th><td>$UptimeFormatted</td></tr>
</table>
<div class='log'>
    <p><strong>Start Time:</strong> $StartTime</p>
    <p><strong>System Info Collected:</strong> $FinishTime_SystemInfo</p>
</div>
"@

$ExeSection = @"
<h2>Bloomberg Terminal</h2>
<table class='section'>
<tr><th>File Path</th><td>$($ExeDetails.FilePath)</td></tr>
<tr><th>Product Name</th><td>$($ExeDetails.ProductName)</td></tr>
<tr><th>File Version</th><td>$($ExeDetails.FileVersion)</td></tr>
<tr><th>Product Version</th><td>$($ExeDetails.ProductVersion)</td></tr>
<tr><th>Creation Date</th><td>$($ExeDetails.CreationDate)</td></tr>
</table>
"@

$AddOnHeader = @"
<h2>Excel add-on</h2>
<table class='section'>
<tr><th>Add-on</th><th>Path</th><th>Status</th></tr>
"@
$AddOnRows = ""
foreach ($item in $AddOnResults) {
    $AddOnRows += "<tr><td>$($item.Name)</td><td>$($item.Path)</td><td style='text-align:center;'>$($item.HtmlSymbol)</td></tr>`n"
}
$AddOnFooter = "</table>"

$B_LangHeader = @"
<h2>Language Pack Installation Report</h2>
<table class='section'>
<tr><th>Language Code</th><th>Language Name</th><th>Status</th></tr>
"@
$B_LangRows = ""
foreach ($item in $LanguageResults) {
    $B_LangRows += "<tr><td>$($item.Code)</td><td>$($item.Name)</td><td style='text-align:center;'>$($item.HtmlSymbol)</td></tr>`n"
}
$B_LangFooter = "</table>"

$B_M365Header = @"
<h2>M365 Apps - Component Installation Report</h2>
<table class='section'>
<tr><th>Component</th><th>Status</th><th>Path</th></tr>
"@
$B_M365Rows = ""
foreach ($item in $officeResults) {
    $pathText = if ($item.Path) { $item.Path } else { "Not found" }
    $B_M365Rows += "<tr><td>$($item.Component)</td><td style='text-align:center;'>$($item.HtmlSymbol)</td><td>$pathText</td></tr>`n"
}
$B_M365Footer = "</table>"

$B_FontHeader = @"
<h2>Font Installation Report</h2>
<table class='section'>
<tr><th>Font Name</th><th>Status</th></tr>
"@
$B_FontRows = ""
foreach ($name in $fontName) {
    $found = $fontCollection.Families | Where-Object Name -like "$name"
    $symbol = if ($found) { $OkSymbolHtml } else { $BadSymbolHtml }
    $B_FontRows += "<tr><td>$name</td><td style='text-align:center;'>$symbol</td></tr>`n"
}
$B_FontFooter = "</table>"

# Legal Notice section in HTML (status only; actual text is in the log)
$B_LegalHeader = @"
<h2>Legal Notice (Logon Banner)</h2>
<table class='section'>
<tr><th>Registry Value</th><th>Result</th><th>Status</th></tr>
"@
$B_LegalRows  = ""
$B_LegalRows += "<tr><td>LegalNoticeCaption</td><td>$LegalNoticeCaptionStatus</td><td style='text-align:center;'>$LegalNoticeCaptionSymbol</td></tr>`n"
$B_LegalRows += "<tr><td>LegalNoticeText</td><td>$LegalNoticeTextStatus</td><td style='text-align:center;'>$LegalNoticeTextSymbol</td></tr>`n"

if (-not $LegalNoticeReadOk) {
    $safeErr = $LegalNoticeReadError
    if ($null -eq $safeErr) { $safeErr = "" }
    $safeErr = [string]$safeErr
    $safeErr = $safeErr -replace '&','&amp;'
    $safeErr = $safeErr -replace '<','&lt;'
    $safeErr = $safeErr -replace '>','&gt;'
    $safeErr = $safeErr -replace '"','&quot;'
    $B_LegalRows += "<tr><td colspan='3'><strong>Read error:</strong> $safeErr</td></tr>`n"
}
$B_LegalFooter = "</table>"

$B_ActivationHeader = @"
<h2>Office Activation Status</h2>
<table class='section'>
<tr><th>Status</th><th>Last 5 Digits</th><th>Channel</th><th>SCA</th><th>Expiration</th></tr>
"@
$B_ActivationRow = "<tr>
<td style='text-align:center;'>$($ActivationResult.HtmlSymbol)</td>
<td style='text-align:center;'>$($ActivationResult.Key)</td>
<td>$($ActivationResult.Channel)</td>
<td>$($ActivationResult.SCA)</td>
<td>$($ActivationResult.Expiration)</td>
</tr>"
$B_ActivationFooter = "</table>"

$B_LocalAdminHeader = @"
<h2>Local Administrator Password Status</h2>
<table class='section'>
<tr><th>Account</th><th>Enabled</th><th>Blank Password</th><th>Status</th></tr>
"@
$B_LocalAdminRow = "<tr>
<td>$($LocalAdminResult.Account)</td>
<td>$($LocalAdminResult.Enabled)</td>
<td>$($LocalAdminResult.BlankPassword)</td>
<td style='text-align:center;'>$($LocalAdminResult.HtmlSymbol)</td>
</tr>"
$B_LocalAdminFooter = "</table>"

# --------------------------------------------------
# SECTION 6 — POWER CONFIGURATION CHECK
# --------------------------------------------------
Write-Log "Checking Power Configuration settings..."

function Get-PowerConfigSettings {
    # Get active power scheme with /getactivescheme
    $activeScheme = "Unknown"
    $activeSchemeGUID = "Unknown"
    try {
        $schemeOutput = & powercfg /getactivescheme 2>$null
        if ($schemeOutput) {
            $activeScheme = $schemeOutput.ToString() -replace '\(.*','' | ForEach-Object { $_.Trim() }
            # Extract GUID
            if ($schemeOutput -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
                $activeSchemeGUID = $matches[0]
            }
        }
    } catch {
        $activeScheme = "Error retrieving"
        Write-Log "Error getting active scheme: $($_.Exception.Message)"
    }
    
    Write-Log "Active Power Scheme: $activeScheme (GUID: $activeSchemeGUID)"
    
    # Check Display (Monitor) shutoff timeout
    # Display subgroup: 7516b95f-f776-4464-8c53-06167f40cc99
    # Setting: Turn off display after (3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e)
    $displayTimeout = "Unknown"
    $displayStatus = "✗ NOT SET TO NEVER"
    $displaySymbol = $BadSymbolHtml
    try {
        if ($activeSchemeGUID -ne "Unknown") {
            $displayOutput = & powercfg /query $activeSchemeGUID 7516b95f-f776-4464-8c53-06167f40cc99 2>$null
            Write-Log "Display subgroup query: $($displayOutput | Out-String)"
            $displayLine = $displayOutput | Select-String "Current AC Power Setting Index" | Select-Object -First 1
            if ($displayLine) {
                $displayValue = [int]($displayLine.ToString() -replace '.*: ','').Trim()
                Write-Log "Display setting value: $displayValue (0x00000000 = Never)"
                # 0 means Never
                if ($displayValue -eq 0) {
                    $displayTimeout = "Never"
                    $displayStatus = "✓ CORRECT (Set to Never)"
                    $displaySymbol = $OkSymbolHtml
                } else {
                    $displayTimeout = "$displayValue seconds"
                    $displayStatus = "✗ NOT SET TO NEVER"
                    $displaySymbol = $BadSymbolHtml
                }
            }
        }
    } catch {
        Write-Log "Error getting display timeout: $($_.Exception.Message)"
    }
    
    Write-Log "Display (Monitor) Shutoff: $displayTimeout - $displayStatus"
    
    # Check Sleep timeout
    # Sleep subgroup: 238c9fa8-0aad-41ed-83f4-97be242c8f20
    # Setting: Sleep after (29f6c1db-86da-48c5-9fdb-f2b67b1f44da)
    $sleepTimeout = "Unknown"
    $sleepStatus = "✗ NOT SET TO NEVER"
    $sleepSymbol = $BadSymbolHtml
    try {
        if ($activeSchemeGUID -ne "Unknown") {
            $sleepOutput = & powercfg /query $activeSchemeGUID 238c9fa8-0aad-41ed-83f4-97be242c8f20 2>$null
            # Look for "Sleep after" and grab the next occurrence of "Current AC Power Setting Index"
            $lines = $sleepOutput -split "`n"
            $sleepAfterFound = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match "Sleep after") {
                    $sleepAfterFound = $true
                }
                if ($sleepAfterFound -and $lines[$i] -match "Current AC Power Setting Index") {
                    $sleepValue = [int]($lines[$i] -replace '.*: ','').Trim()
                    Write-Log "Sleep setting value: $sleepValue (0x00000000 = Never)"
                    if ($sleepValue -eq 0) {
                        $sleepTimeout = "Never"
                        $sleepStatus = "✓ CORRECT (Set to Never)"
                        $sleepSymbol = $OkSymbolHtml
                    } else {
                        $sleepTimeout = "$sleepValue seconds"
                        $sleepStatus = "✗ NOT SET TO NEVER"
                        $sleepSymbol = $BadSymbolHtml
                    }
                    break
                }
            }
        }
    } catch {
        Write-Log "Error getting sleep timeout: $($_.Exception.Message)"
    }
    
    Write-Log "System Sleep Timeout: $sleepTimeout - $sleepStatus"
    
    # Check Hibernate setting
    # Sleep subgroup: 238c9fa8-0aad-41ed-83f4-97be242c8f20
    # Setting: Hibernate after (9d7815a6-7ee4-497e-8888-515a05f02364)
    $hibernateTimeout = "Unknown"
    $hibernateStatus = "✗ NOT SET TO NEVER"
    $hibernateSymbol = $BadSymbolHtml
    try {
        if ($activeSchemeGUID -ne "Unknown") {
            $hibernateOutput = & powercfg /query $activeSchemeGUID 238c9fa8-0aad-41ed-83f4-97be242c8f20 2>$null
            # Look for "Hibernate after" and grab the next occurrence of "Current AC Power Setting Index"
            $lines = $hibernateOutput -split "`n"
            $hibernateAfterFound = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match "Hibernate after") {
                    $hibernateAfterFound = $true
                }
                if ($hibernateAfterFound -and $lines[$i] -match "Current AC Power Setting Index") {
                    $hibernateValue = [int]($lines[$i] -replace '.*: ','').Trim()
                    Write-Log "Hibernate setting value: $hibernateValue (0x00000000 = Never)"
                    if ($hibernateValue -eq 0) {
                        $hibernateTimeout = "Never"
                        $hibernateStatus = "✓ CORRECT (Set to Never)"
                        $hibernateSymbol = $OkSymbolHtml
                    } else {
                        $hibernateTimeout = "$hibernateValue seconds"
                        $hibernateStatus = "✗ NOT SET TO NEVER"
                        $hibernateSymbol = $BadSymbolHtml
                    }
                    break
                }
            }
        }
    } catch {
        Write-Log "Error getting hibernate setting: $($_.Exception.Message)"
    }
    
    Write-Log "Hibernate Setting: $hibernateTimeout - $hibernateStatus"
    
    return @{
        ActiveScheme = $activeScheme
        DisplayTimeout = $displayTimeout
        DisplayStatus = $displayStatus
        DisplaySymbol = $displaySymbol
        SleepTimeout = $sleepTimeout
        SleepStatus = $sleepStatus
        SleepSymbol = $sleepSymbol
        HibernateTimeout = $hibernateTimeout
        HibernateStatus = $hibernateStatus
        HibernateSymbol = $hibernateSymbol
    }
}

$PowerConfigResult = Get-PowerConfigSettings

$B_PowerConfigHeader = @"
<h2>Power Configuration Settings</h2>
<table class='section'>
<tr><th>Setting</th><th>Current Value</th><th>Status</th></tr>
"@

$B_PowerConfigRows = ""
$B_PowerConfigRows += "<tr><td>Active Power Scheme</td><td>$($PowerConfigResult.ActiveScheme)</td><td style='text-align:center;'>N/A</td></tr>`n"
$B_PowerConfigRows += "<tr><td>Display (Monitor) Shutoff</td><td>$($PowerConfigResult.DisplayTimeout)</td><td style='text-align:center;'>$($PowerConfigResult.DisplaySymbol)</td></tr>`n"
$B_PowerConfigRows += "<tr><td>System Sleep Timeout</td><td>$($PowerConfigResult.SleepTimeout)</td><td style='text-align:center;'>$($PowerConfigResult.SleepSymbol)</td></tr>`n"
$B_PowerConfigRows += "<tr><td>Hibernate Setting</td><td>$($PowerConfigResult.HibernateTimeout)</td><td style='text-align:center;'>$($PowerConfigResult.HibernateSymbol)</td></tr>`n"

$B_PowerConfigFooter = "</table>"

$ReportFooter = "<br>`n<div class='small'>Generated: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "</div>`n</body>`n</html>`n"

$FinalHtml = $ReportHeader +
             $SystemSection +
             $ExeSection +
             $AddOnHeader + $AddOnRows + $AddOnFooter +
             $B_LangHeader + $B_LangRows + $B_LangFooter +
             $B_M365Header + $B_M365Rows + $B_M365Footer +
             $B_FontHeader + $B_FontRows + $B_FontFooter +
             $B_LegalHeader + $B_LegalRows + $B_LegalFooter +
             $B_ActivationHeader + $B_ActivationRow + $B_ActivationFooter +
             $B_LocalAdminHeader + $B_LocalAdminRow + $B_LocalAdminFooter +
             $B_PowerConfigHeader + $B_PowerConfigRows + $B_PowerConfigFooter +
             $ReportFooter

# Save combined HTML to C:\Temp
Set-Content -Path $HtmlFile -Value $FinalHtml -Encoding UTF8
Write-Log ("Combined HTML report created at {0}" -f $HtmlFile)

# End log
Write-Log ("===== Script End: {0} =====" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

# Opening the HTML in a browser has been commented out per request:
# try {
#     Start-Process $HtmlFile -ErrorAction SilentlyContinue
# } catch {
#     Write-Log ("Unable to Start-Process {0}: {1}" -f $HtmlFile, $_)
# }

# Output
Write-Output ("Report generated: {0}" -f $HtmlFile)
Write-Output ("Log file: {0}" -f $LogFile)
Write-Output ("Font results: {0}" -f $FontOutput)