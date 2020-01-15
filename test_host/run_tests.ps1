Param(
    [Parameter(Mandatory=$true)]
    [string]$testDir,
    [Parameter(Mandatory=$true)]
    [string]$resultDir,
    [Parameter(Mandatory=$true)]
    [string]$cephConfig,
    [int]$testSuiteTimeout=300,
    [int]$workerCount=8
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$isolatedTestsMapping = $false
$env:CEPH_CONF = $cephConfig

$scriptLocation = [System.IO.Path]::GetDirectoryName(
    $myInvocation.MyCommand.Definition)

import-module "$scriptLocation\..\utils\windows\all.psm1"

function clear_test_stats() {
    $env:TEST_FAILED = "0"
}

function validate_test_run() {
    if ($env:TEST_FAILED -ne "0") {
        throw "One or more test suites have failed"
    }

    log_message "All the tests have passed."
}

function notify_starting_test($testDescription, $testType) {
    log_message "Running test: ($testType) $testDescription."
}

function notify_successful_test($testDescription, $testType) {
    log_message "($testType) $testDescription passed."
}

function notify_failed_test($testDescription, $testType, $errMsg) {
    # We're going to resume running tests even if one of the suite fails,
    # throwing an error at the end of the run.
    $env:TEST_FAILED = "1"

    log_message "($testType) $testDescription failed. Error: $errMsg"
}

function get_isolated_tests($testFileName, $isolatedTestsMapping) {
    $isolatedTests = @()
    foreach ($isolatedTestPattern in $isolatedTestsMapping.Keys) {
        if ($testFileName -match $isolatedTestPattern) {
            $isolatedTests += $isolatedTestsMapping[$isolatedTestPattern]
        }
    }
    $isolatedTests
}

function get_matching_pattern($str, $patternList) {
    foreach ($pattern in $patternList) {
        if ($str -match $pattern) {
            return $pattern
        }
    }
}

function run_tests_from_dir(
        $testdir, $resultDir, $pattern,
        $isolatedTestsMapping,
        $testType,
        $runIsolatedTests,
        $subunitOutFile,
        $nonGTestList,
        $workerCount=8) {
    $testList = ls -Recurse $testdir | `
                ? { $_.Name -match $pattern }

    $rsp = [RunspaceFactory]::CreateRunspacePool($workerCount, $workerCount)
    $rsp.Open()
    $jobs = @()
    foreach($testBinary in $testList) {
        $testName = $testBinary.Name
        $testPath = $testBinary.FullName

        $isolatedTests = get_isolated_tests $testName $isolatedTestsMapping
        $testFilter = $isolatedTests -join ":"

        $nonGTestPattern = get_matching_pattern $testName $nonGTestList.Keys
        if ($nonGTestPattern) {
            $isGtest = $false
            $testArgs = $nonGTestList[$nonGTestPattern]
            $tags = "$testType-standalone"
        }
        else {
            $isGtest = $true
            $testArgs = ""
            $tags = "$testType-googletest"
        }

        if ((! $runIsolatedTests) -and $testFilter -eq "*") {
            # This whole test suite is skipped. We won't pass this filter to
            # the binary as it may not use the GTest framework.
            continue
        }
        if ($runIsolatedTests -and (! $testFilter)) {
            # No isolated tests for this suite.
            continue
        }
        if ((! $runIsolatedTests) -and $testFilter) {
            $testFilter = "-$testFilter"
        }

        notify_starting_test $testName $tags
        $job = [Powershell]::Create().AddScript({
            Param(
                [Parameter(Mandatory=$true)]
                [string]$utilsModuleLocation,
                [Parameter(Mandatory=$true)]
                [string]$testPath,
                [Parameter(Mandatory=$true)]
                [string]$resultDir,
                [Parameter(Mandatory=$true)]
                [int]$testSuiteTimeout,
                [Parameter(Mandatory=$true)]
                [string]$subunitOutFile,
                [string]$testFilter,
                [bool]$isGtest
            )
            import-module $utilsModuleLocation
            try {
                if ($isGtest) {
                    run_gtest_subunit `
                        $testPath $resultDir $testSuiteTimeout $testFilter `
                        $subunitOutFile
                }
                else {
                    run_test_subunit `
                        $testPath $resultDir $subunitOutFile `
                        $testSuiteTimeout $testArgs
                }
                
                return @{success=$true}
            }
            catch {
                $errMsg = $_.Exception.Message
                return @{success=$false; errMsg=$errMsg}
            }
        }).AddParameters(@{
            utilsModuleLocation="$scriptLocation\..\utils\windows\all.psm1";
            testPath=$testPath;
            resultDir=$resultDir;
            testSuiteTimeout=$testSuiteTimeout;
            testFilter=$testFilter;
            subunitOutFile=$subunitOutFile;
            isGtest=$isGtest
        })
        $job.RunspacePool = $rsp
        $jobs += @{
            Job=$job;
            Result=$job.BeginInvoke();
            TestName=$testName;
            TestType=$tags
        }
    }

    do {
        Start-Sleep -seconds 10
        $finishedCount = ($jobs | ? {$_.Result.IsCompleted -eq $true}).Count
        $totalCount = ($jobs).Count
        log_message "Finished $finishedCount out of $totalCount jobs."
    } while ($finishedCount -lt $totalCount)

    foreach($r in $jobs) {
        $result = $r.Job.EndInvoke($r.Result)
        if($result.success) {
            notify_successful_test $r.TestName $r.TestType
        }
        else {
            notify_failed_test $r.TestName $r.TestType $result.errMsg
        }
    }
}

function run_unit_tests() {
    $subunitFile = "$resultDir\subunit.out"
    $testPattern="unittest.*.exe|ceph_test.*.exe"
    # Tests that aren't using the google test framework or require specific
    # arguments and will have to begin run differently. The following mapping
    # provides the arguments needed by each test.
    $nonGTestList=@{
        "ceph_test_timers.exe"="";
        "ceph_test_rados_delete_pools_parallel.exe"="";
        "ceph_test_rados_list_parallel.exe"="";
        "ceph_test_rados_open_pools_parallel.exe"="";
        "ceph_test_rados_watch_notify.exe"="";
    }
    # Tests that aren't supposed to be run automatically.
    $manualTests=@{
        "ceph_test_mutate.exe"="*";
        "ceph_test_rewrite_latency.exe"="*";
    }
    $excludedTests=@{
        # This test passes, but it leaks a "sleep" subprocess which
        # hang powershell's job mechanism.
        "unittest_subprocess.exe"="SubProcessTimed.SubshellTimedout";
        "ceph_test_signal_handlers.exe"="*";
        # WIP
        "ceph_test_admin_socket_output.exe"="*";
    }
    $slowTestList=@{
        "ceph_test_rados_api_tier_pp.exe"="*";
    }

    $excludedTests += $manualTests

    log_message "Running unit tests."
    log_message "Using subunit file: $subunitFile"

    run_tests_from_dir -testdir $testDir `
                       -resultDir $resultDir `
                       -pattern $testPattern `
                       -isolatedTestsMapping $excludedTests `
                       -runIsolatedTests $false `
                       -testType "unittests" `
                       -subunitOutFile $subunitFile `
                       -workerCount $workerCount `
                       -nonGTestList $nonGTestList

    # Various tests that are known to crash or hang.
    # log_message "Running isolated unit tests."
    # run_gtests_from_dir -testdir $testDir `
    #                     -resultDir $resultDir `
    #                     -pattern $testPattern `
    #                     -isolatedTestsMapping $isolatedUnitTests `
    #                     -runIsolatedTests $true `
    #                     -testType "unittests_isolated" `
    #                     -subunitOutFile $subunitFile `
    #                     -workerCount $workerCount

    generate_subunit_report $subunitFile $resultDir `
                            "unittest_results"
}

ensure_dir_exists $resultDir

clear_test_stats

run_unit_tests

validate_test_run
