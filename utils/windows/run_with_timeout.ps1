Param(
    [Parameter(Mandatory=$true)]
    [string]$cmd,
    [Parameter(Mandatory=$true)]
    [int]$timeoutSec,
    [string]$jobName
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$scriptLocation = [System.IO.Path]::GetDirectoryName(
    $myInvocation.MyCommand.Definition)

. "$scriptLocation\common.ps1"

import-module "$scriptLocation\windows.psm1"

run_as_job $jobName
_iex_with_timeout $cmd $timeoutSec
