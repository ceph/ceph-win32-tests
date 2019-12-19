$scriptLocation = [System.IO.Path]::GetDirectoryName(
    $myInvocation.MyCommand.Definition)

. "$scriptLocation\common.ps1"

function add_subunit_result($outputFile, $testName, $result, $startTime,
                            $stopTime, $details, $attachedFile) {
    $tempFile = [System.IO.Path]::GetTempFileName()

    cmd /c "echo $details >> $tempFile"
    cmd /c "echo '' >> $tempFile"
    if ($attachedFile) {
        # CMD 'type' properly handles binary files, unlike PS.
        cmd /c "type $attachedFile >> $tempFile"
    }

    python "$scriptLocation\..\common\publish_subunit_result.py" `
        --test-id=$testName --status=$result --start-time=$startTime `
        --stop-time $stopTime --output-file=$outputFile `
        --attachment-path $tempFile

    check_remove_file $tempFile -silent $true
}

function add_subunit_failure($outputFile, $testName, $startTime,
                             $stopTime, $details, $attachedFile) {
    add_subunit_result $outputFile $testName "fail" $startTime `
                       $stopTime $details $attachedFile
}

function add_subunit_success($outputFile, $testName, $startTime,
                             $stopTime, $details, $attachedFile) {
    add_subunit_result $outputFile $testName "success" $startTime `
                       $stopTime $details $attachedFile
}

function gtest2subunit($xmlPath, $subunitPath, $testPrefix) {
    safe_exec (
        "python `"$scriptLocation\..\common\gtest2subunit.py`" " +
        "--xml-path=$xmlPath --subunit-path=$subunitPath " +
        "--test-prefix=$testPrefix")
}

function generate_subunit_report($subunitPath, $reportDir, $reportName) {
    # Generate some user friendly reports based on the subunit binary file.
    $textResultFile = "$reportDir\$reportName.txt"
    $htmlResultFile = "$reportDir\$reportName.html"

    cmd /c "type $subunitPath | subunit-trace > $textResultFile"
    subunit2html $subunitPath $htmlResultFile
}

function run_gtest($binPath, $resultDir, $timeout=-1, $testFilter) {
    $binName = (split-path -leaf $binPath) -replace ".exe$",""
    $xmlOutputPath = join-path $resultDir ($binName + "_results.xml")
    $consoleOutputPath = join-path $resultDir ($binName + "_results.log")
    $gtestFilterArg = ""

    if ($testFilter) {
        $gtestFilterArg = "--gtest_filter=`"$testFilter`""
    }

    $cmd = ("cmd /c '$binPath --gtest_output=xml:$xmlOutputPath $gtestFilterArg " +
            "> $consoleOutputPath 2>&1'")
    iex_with_timeout $cmd $timeout
}

function get_gtest_list($binPath) {
    safe_exec ("$binPath --gtest_list_tests | " +
               "python `"$scriptLocation\..\common\parse_gtest_list.py`"")
}

function run_gtest_subunit($binPath, $resultDir, $timeout=-1, $testFilter,
                           $subunitOutputPath) {
    $binName = (split-path -leaf $binPath) -replace ".exe$",""
    $xmlOutputPath = join-path $resultDir ($binName + "_results.xml")
    $consoleOutputPath = join-path $resultDir ($binName + "_results.log")

    $startTime = get_unix_time
    try {
        run_gtest $binPath $resultDir $timeout $testFilter
    }
    catch {
        $errMsg = $_.Exception.Message
        throw
    }
    finally {
        $stopTime = get_unix_time
        if (test-path $xmlOutputPath) {
            gtest2subunit $xmlOutputPath $subunitOutputPath $binName
        }
        else {
            if (! $errMsg ) {
                $errMsg = "Missing output xml."
            }
            add_subunit_failure $subunitOutputPath $binName `
                                $startTime $stopTime `
                                $errMsg $consoleOutputPath
        }
    }
}
