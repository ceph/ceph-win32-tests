# We need to run sysprep each time we update the Windows image.

$cbsInitDir = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init"
$cbsInitLogDir = "$cbsInitDir\log"
$unattendFile = "$cbsInitDir\conf\Unattend.xml"

function clear_eventlog ()
{
    $Logs = Get-EventLog -List | ForEach {$_.Log}
    $Logs | % {Clear-EventLog -Log $_ }
    Get-EventLog -List
}

function cleanup_cbsinit () {
    get-service cloudbase* | stop-service
    rm -Recurse -Force "$cbsInitLogDir\*"
}

function remove_unneeded_apps () {
    # Some pre-installed games may prevent us from doing the sysprep.
    $apps = Get-AppxPackage -AllUsers `
        | ?  {$_.Name -notmatch "microsoft|windows|-|InputApp"}
    $apps += Get-AppxPackage -AllUsers | ? {$_.Name -match "bing" }

    $apps | % { echo "Removing $_.Name"; Remove-AppxPackage -AllUsers $_ }
}


clear_eventlog
remove_unneeded_apps

ipconfig /release

C:\Windows\System32\Sysprep\sysprep.exe `
    /generalize /oobe /shutdown `
    /unattend:$unattendFile
