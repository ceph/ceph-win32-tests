$scriptLocation = [System.IO.Path]::GetDirectoryName(
    $myInvocation.MyCommand.Definition)

. "$scriptLocation\common.ps1"

function tar_msys() {
    # We're doing some plumbing to get tar working properly without
    # messing with PATH. This probably means that this can't be piped.
    #
    # msys provides tar. Apparently, Windows 10 includes tarbsd as well,
    # but it won't work with msys' bzip2. We don't want to add
    # the msys' bin dir to PATH "globally", as that will break other
    # binaries, e.g. "cmd".

    $pathBackup = "$($env:PATH)"
    $env:PATH ="$msysBinDir;$($env:PATH)"

    try {
        tar.exe @args
        if ($LASTEXITCODE) {
            throw "Command failed: tar $args"
        }
    }
    finally {
        $env:PATH = $pathBackup
    }
}

function convert_to_msys_path($path) {
    # We'll need posix paths.
    # c:\test\abcd becomes /c/test/abcd
    return ($path -replace "^([a-z]):\\",'/$1/') -replace "\\", "/"
}
