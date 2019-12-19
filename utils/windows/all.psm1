$scriptLocation = [System.IO.Path]::GetDirectoryName(
    $myInvocation.MyCommand.Definition)

. "$scriptLocation\common.ps1"

import-module "$scriptLocation\pathutils.psm1"
import-module "$scriptLocation\windows.psm1"
import-module "$scriptLocation\msys.psm1"
import-module "$scriptLocation\tests.psm1"
import-module "$scriptLocation\git.psm1"

Export-ModuleMember -function "*"
