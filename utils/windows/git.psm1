$scriptLocation = [System.IO.Path]::GetDirectoryName(
    $myInvocation.MyCommand.Definition)

. "$scriptLocation\common.ps1"

function git_clone_pull($path, $url, $ref="master", $shallow=$false)
{
    log_message "Cloning / pulling: $url, branch: $ref. Path: $path."

    pushd .
    try
    {
        if (!(Test-Path -path $path))
        {
            if ($shallow) {
                safe_exec "git clone -q -b $ref $url $path --depth=1"
            }
            else {
                safe_exec "git clone -q $url $path"
            }

            cd $path
        }
        else
        {
            cd $path

            safe_exec "git remote set-url origin $url"
            safe_exec "git reset --hard"
            safe_exec "git clean -f -d"
            safe_exec "git fetch"
        }

        safe_exec "git checkout $ref"

        if ((git tag) -contains $ref) {
            log_message "Got tag $ref instead of a branch."
            log_message "Skipping doing a pull."
        }
        elseif ($(git log -1 --pretty=format:"%H").StartsWith($ref)){
            log_message "Got a commit id instead of a branch."
            log_message "Skipping doing a pull."
        }
        else {
            safe_exec "git pull"
        }
    }
    finally
    {
        popd
    }
}
