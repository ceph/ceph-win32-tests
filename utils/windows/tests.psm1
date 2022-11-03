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

    safe_exec "subunit2html $subunitPath $htmlResultFile"

    try {
        safe_exec "type $subunitPath | subunit-trace" | `
            Out-File -Encoding ascii -FilePath $textResultFile
    } catch {
        # subunit-trace returns a non-zero exit code when the subunit file is
        # invalid OR when there are failed tests. This function is only
        # concerned in generating the test report and shouldn't fail if there
        # are test failures.
        log_message "subunit-trace reports failures: $_"
    }
}

function run_gtest($binPath, $resultDir, $timeout=-1, $testFilter, $testSuffix) {
    $binName = (split-path -leaf $binPath) -replace ".exe$",""
    $testName = $binName + $testSuffix
    $xmlOutputPath = join-path $resultDir ($testName + "_results.xml")
    $consoleOutputPath = join-path $resultDir ($testName + "_results.log")
    $gtestFilterArg = ""

    if ($testFilter) {
        $gtestFilterArg = "--gtest_filter=`"$testFilter`""
    }

    $cmd = ("cmd /c '$binPath --gtest_output=xml:$xmlOutputPath $gtestFilterArg " +
            ">> $consoleOutputPath 2>&1'")

    echo $cmd | Out-File -Encoding ascii -FilePath $consoleOutputPath
    iex_with_timeout $cmd $timeout
}

function run_test($binPath, $resultDir, $timeout=-1, $testArgs, $testSuffix) {
    $binName = (split-path -leaf $binPath) -replace ".exe$",""
    $testName = $binName + $testSuffix
    $consoleOutputPath = join-path $resultDir ($testName + "_results.log")

    $cmd = ("cmd /c '$binPath $testArgs " +
            ">> $consoleOutputPath 2>&1'")

    echo $cmd | Out-File -Encoding ascii -FilePath $consoleOutputPath
    iex_with_timeout $cmd $timeout
}

function run_test_subunit($binPath, $resultDir,
                          $subunitOutputPath, $timeout=-1,
                          $testArgs, $testSuffix) {
    $binName = (split-path -leaf $binPath) -replace ".exe$",""
    $testName = $binName + $testSuffix
    $consoleOutputPath = join-path $resultDir ($testName + "_results.log")

    $startTime = get_unix_time
    try {
        run_test $binPath $resultDir $timeout $testArgs $testSuffix
    }
    catch {
        $errMsg = $_.Exception.Message
        $failed = $true
        throw
    }
    finally {
        $stopTime = get_unix_time

        if ($failed) {
            if (! $errMsg ) {
                $errMsg = "Test failed: $testName."
            }
            add_subunit_failure $subunitOutputPath $testName `
                                $startTime $stopTime `
                                $errMsg $consoleOutputPath
        }
        else {
            $testDetails = "Test passed: $testName"
            add_subunit_success $subunitOutputPath $testName `
                                $startTime $stopTime `
                                $testDetails $consoleOutputPath
        }
    }
}

function get_gtest_list($binPath) {
    safe_exec ("$binPath --gtest_list_tests | " +
               "python `"$scriptLocation\..\common\parse_gtest_list.py`"")
}

function run_gtest_subunit($binPath, $resultDir, $timeout=-1, $testFilter,
                           $subunitOutputPath, $testSuffix) {
    $binName = (split-path -leaf $binPath) -replace ".exe$",""
    $testName = $binName + $testSuffix
    $xmlOutputPath = join-path $resultDir ($testName + "_results.xml")
    $consoleOutputPath = join-path $resultDir ($testName + "_results.log")

    $startTime = get_unix_time
    try {
        run_gtest $binPath $resultDir $timeout $testFilter $testSuffix
    }
    catch {
        $errMsg = $_.Exception.Message
        throw
    }
    finally {
        $stopTime = get_unix_time
        if (test-path $xmlOutputPath) {
            gtest2subunit $xmlOutputPath $subunitOutputPath $testName
        }
        else {
            if (! $errMsg ) {
                $errMsg = "Missing output xml."
            }
            add_subunit_failure $subunitOutputPath $testName `
                                $startTime $stopTime `
                                $errMsg $consoleOutputPath
        }
    }
}
