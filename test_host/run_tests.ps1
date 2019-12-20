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

function run_gtests_from_dir($testdir, $resultDir, $pattern,
                             $isolatedTestsMapping,
                             $runIsolatedTests,
                             $testType,
                             $subunitOutFile,
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
        if ($runIsolatedTests -and (! $testFilter)) {
            # No isolated tests for this suite.
            continue
        }
        if ((! $runIsolatedTests) -and $testFilter) {
            $testFilter = "-$testFilter"
        }

        notify_starting_test $testName $testType
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
                [string]$testFilter
            )
            import-module $utilsModuleLocation
            try {
                run_gtest_subunit `
                    $testPath $resultDir $testSuiteTimeout $testFilter `
                    $subunitOutFile
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
            subunitOutFile=$subunitOutFile
        })
        $job.RunspacePool = $rsp
        $jobs += @{
            Job=$job;
            Result=$job.BeginInvoke();
            TestName=$testName;
            TestType=$testType
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

    log_message "Running unit tests."
    log_message "Using subunit file: $subunitFile"

    run_gtests_from_dir -testdir $testDir `
                        -resultDir $resultDir `
                        -pattern $testPattern `
                        -isolatedTestsMapping $isolatedUnitTests `
                        -runIsolatedTests $false `
                        -testType "unittests" `
                        -subunitOutFile $subunitFile `
                        -workerCount $workerCount

    # Various tests that are known to crash or hang.
    log_message "Running isolated unit tests."
    run_gtests_from_dir -testdir $testDir `
                        -resultDir $resultDir `
                        -pattern $testPattern `
                        -isolatedTestsMapping $isolatedUnitTests `
                        -runIsolatedTests $true `
                        -testType "unittests_isolated" `
                        -subunitOutFile $subunitFile `
                        -workerCount $workerCount

    generate_subunit_report $subunitFile $resultDir `
                            "unittest_results"
}

ensure_dir_exists $resultDir

clear_test_stats

run_unit_tests

validate_test_run
