# ====================================================================================================
# MDT Task Sequence HTML Report
# Prompt for Specific Task Sequence Folder
# (MDT), task sequences are stored in the deployment share’s Control folder 
# as XML files (TaskSequences.xml and individual ts.xml files under each task sequence ID folder).
# 
# Enter MDT Task Sequence folder path: Desktop OS\Production Images\Windows 11 24H2 
#   (you don't have to put in quotation marks for spaces - above taken from DYMDT01)
# ====================================================================================================

# ----- CONFIGURATION -----

# ----- QUIET CONSOLE OUTPUT -----

Set-PSDebug -Trace 0
$DebugPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'

$DeploymentShare = "D:\DeploymentShare"
$LogFolder = "C:\Temp"

# ----- PROMPT USER FOR MDT TASK SEQUENCE FOLDER -----

Write-Host ""
Write-Host "Example MDT Task Sequence folder paths:" -ForegroundColor Yellow
Write-Host "  Windows 11"
Write-Host "  Servers\Production"
Write-Host "  Imaging\Windows 10"
Write-Host ""

$TSFolderPath = Read-Host "Enter MDT Task Sequence folder path"

Write-Host ""
Write-Host "Output format options:" -ForegroundColor Yellow
Write-Host "  html  = Save HTML report"
Write-Host "  csv   = Save CSV report"
Write-Host "  both  = Save both HTML and CSV"
Write-Host ""

$OutputChoice = (Read-Host "Choose output format (html/csv/both)").ToLower().Trim()

if ($OutputChoice -notin @("html", "csv", "both")) {
    Write-Host "Invalid output selection. Defaulting to 'html'." -ForegroundColor Yellow
    $OutputChoice = "html"
}

# ----- CREATE LOG FOLDER -----

if (!(Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

# ----- TIMESTAMP -----

$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ----- SAFE FILE NAME -----

$SafeFolderName = $TSFolderPath -replace '[\\/:*?"<>|]', '_'

# ----- FILES -----

$HtmlFile = Join-Path $LogFolder "MDT_TS_Report_${SafeFolderName}_$TimeStamp.html"
$CsvFile  = Join-Path $LogFolder "MDT_TS_Report_${SafeFolderName}_$TimeStamp.csv"
$LogFile  = Join-Path $LogFolder "MDT_TS_Report_${SafeFolderName}_$TimeStamp.log"

$ExportHtml = $OutputChoice -in @("html", "both")
$ExportCsv  = $OutputChoice -in @("csv", "both")
$script:CsvRows = @()

# ----- LOGGING FUNCTION -----

function Write-Log {
    param (
        [string]$Message
    )

    $DateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    "$DateTime - $Message" | Out-File $LogFile -Append

    Write-Host "$DateTime - $Message"
}

# ----- START -----

Write-Log "================================================="
Write-Log "MDT Task Sequence HTML Report STARTED"
Write-Log "Selected Folder: $TSFolderPath"
Write-Log "================================================="

# ----- HTML HEADER -----

$Html = @"
<html>
<head>
<title>MDT Task Sequence Report</title>

<style>

body {
    font-family: Arial;
    background-color: #f4f4f4;
    margin: 20px;
}

h1 {
    color: #003366;
}

h2 {
    background-color: #003366;
    color: white;
    padding: 8px;
}

h3 {
    background-color: #d9e6f2;
    padding: 6px;
}

ul {
    margin-top: 5px;
}

li {
    margin-bottom: 4px;
}

.section {
    background-color: white;
    padding: 15px;
    margin-bottom: 20px;
    border-radius: 5px;
    box-shadow: 1px 1px 5px #cccccc;
}

</style>

</head>

<body>

<h1>MDT Task Sequence Report</h1>

<p>
Generated: $(Get-Date)
</p>

<p>
Folder Selected: $TSFolderPath
</p>

"@

try {

    # ----- IMPORT MDT MODULE -----

    Write-Log "Importing MDT PowerShell module..."

    Import-Module "C:\Program Files\Microsoft Deployment Toolkit\Bin\MicrosoftDeploymentToolkit.psd1"

    # ----- CREATE MDT DRIVE -----

    if (!(Get-PSDrive -Name DS001 -ErrorAction SilentlyContinue)) {

        Write-Log "Creating MDT PowerShell Drive..."

        New-PSDrive `
            -Name "DS001" `
            -PSProvider MDTProvider `
            -Root $DeploymentShare `
            -Description "MDT Deployment Share" `
            -NetworkPath "\\localhost\DeploymentShare$" | Out-Null
    }

    # ----- MDT FOLDER PATH -----

    $MDTFolder = "DS001:\Task Sequences\$TSFolderPath"

    Write-Log "Searching MDT folder: $MDTFolder"

    if (!(Test-Path $MDTFolder)) {

        throw "Specified MDT folder does not exist: $MDTFolder"
    }

    # ----- GET TASK SEQUENCES ONLY -----

    $TaskSequences = Get-ChildItem $MDTFolder | Where-Object {
        $_.PSChildName -ne "Folders"
    }

    Write-Log "Found $($TaskSequences.Count) task sequence(s)."

    foreach ($TS in $TaskSequences) {

        Write-Log "Processing Task Sequence: $($TS.Name)"

        $Html += "<div class='section'>"
        $Html += "<h2>$($TS.Name) [$($TS.ID)]</h2>"

        $TSXmlPath = Join-Path $DeploymentShare "Control\$($TS.ID)\ts.xml"

        if (Test-Path $TSXmlPath) {

            [xml]$TSXml = Get-Content $TSXmlPath

            # ----- RECURSIVE FUNCTION -----

            function Add-GroupHtml {
                param (
                    $Groups
                )

                foreach ($Group in $Groups) {

                    $GroupName = $Group.name

                    $script:Html += "<h3>$GroupName</h3>"
                    $script:Html += "<ul>"

                    # ----- STEPS -----

                    foreach ($Step in $Group.step) {

                        $script:Html += "<li>$($Step.name)</li>"

                        $script:CsvRows += [pscustomobject]@{
                            TaskSequence = $TS.Name
                            TaskSequenceID = $TS.ID
                            GroupName = $GroupName
                            StepName = $Step.name
                        }
                    }

                    $script:Html += "</ul>"

                    # ----- SUBGROUPS -----

                    if ($Group.group) {

                        Add-GroupHtml -Groups $Group.group
                    }
                }
            }

            # ----- PROCESS GROUPS -----

            Add-GroupHtml -Groups $TSXml.sequence.group

            Write-Log "Successfully processed $($TS.Name)"
        }
        else {

            Write-Log "ERROR: ts.xml not found for $($TS.Name)"

            $Html += "<p style='color:red;'>ERROR: ts.xml not found.</p>"
        }

        $Html += "</div>"
    }
}
catch {

    Write-Log "ERROR: $($_.Exception.Message)"

    $Html += "<p style='color:red;'>ERROR: $($_.Exception.Message)</p>"
}

# ----- HTML FOOTER -----

$Html += @"

</body>
</html>

"@

# ----- SAVE HTML -----

if ($ExportHtml) {
    $Html | Out-File $HtmlFile -Encoding UTF8
    Write-Log "HTML Report Created: $HtmlFile"
}

if ($ExportCsv) {
    if ($script:CsvRows.Count -gt 0) {
        $script:CsvRows | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
        Write-Log "CSV Report Created: $CsvFile"
    }
    else {
        Write-Log "CSV requested, but no step rows were found to export."
    }
}

Write-Log "MDT Task Sequence HTML Report COMPLETED"

# ----- REPORTS SAVED ONLY (NO AUTO-OPEN) -----
