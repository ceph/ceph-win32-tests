Param(
    [string]$dumpDir,
    [int]$dumpCount,
    [int]$dumpType
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$scriptLocation = [System.IO.Path]::GetDirectoryName(
    $myInvocation.MyCommand.Definition)

import-module "$scriptLocation\..\utils\windows\all.psm1"


$werRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
$localDumpsRegPath = "$werRegPath\LocalDumps" 

if (!(Test-path $localDumpsRegPath)) {
    log_message "Creating $localDumpsRegPath"
    New-Item -Path $localDumpsRegPath
}

if ($PSBoundParameters.ContainsKey('dumpDir')) {
    log_message "setting $localDumpsRegPath\DumpFolder to $dumpDir"
    Set-ItemProperty `
        -Path $localDumpsRegPath -Name "DumpFolder" `
        -Value $dumpDir -Type ExpandString
}

if ($PSBoundParameters.ContainsKey('dumpCount')) {
    log_message "setting $localDumpsRegPath\DumpCount to $dumpCount"
    Set-ItemProperty `
        -Path $localDumpsRegPath -Name "DumpCount" `
        -Value $dumpCount -Type DWord
}

if ($PSBoundParameters.ContainsKey('dumpType')) {
    log_message "setting $localDumpsRegPath\DumpType to $dumpType"
    Set-ItemProperty `
        -Path $localDumpsRegPath -Name "DumpType" `
        -Value $dumpType -Type DWord
}
