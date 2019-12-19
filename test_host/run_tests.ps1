Param(
    [Parameter(Mandatory=$true)]
    [string]$testDir,
    [Parameter(Mandatory=$true)]
    [string]$resultDir,
    [Parameter(Mandatory=$true)]
    [string]$cephConfig,
    [int]$testSuiteTimeout=300
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
                             $subunitOutFile) {
    $testList = ls -Recurse $testdir | `
                ? { $_.Name -match $pattern }

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

        try {
            notify_starting_test $testName $testType
            run_gtest_subunit `
                $testPath $resultDir $testSuiteTimeout $testFilter `
                $subunitOutFile
            notify_successful_test $testName $testType
        }
        catch {
            $errMsg = $_.Exception.Message
            notify_failed_test $testName $testType $errMsg
        }
    }
}

function run_unit_tests() {
    $subunitFile = "$resultDir\subunit.out"

    log_message "Running unit tests."
    log_message "Using subunit file: $subunitFile"

    $testPattern="unittests.*.exe|ceph_test.*.exe"

    run_gtests_from_dir -testdir $testDir `
                        -resultDir $resultDir `
                        -pattern $testPattern `
                        -isolatedTestsMapping $isolatedUnitTests `
                        -runIsolatedTests $false `
                        -testType "unittests" `
                        -subunitOutFile $subunitFile

    # Various tests that are known to crash or hang.
    log_message "Running isolated unit tests."
    run_gtests_from_dir -testdir $testDir `
                        -resultDir $resultDir `
                        -pattern $testPattern `
                        -isolatedTestsMapping $isolatedUnitTests `
                        -runIsolatedTests $true `
                        -testType "unittests_isolated" `
                        -subunitOutFile $subunitFile

    generate_subunit_report $subunitFile $resultDir `
                            "unittest_results"
}

ensure_dir_exists $resultDir

clear_test_stats

run_unit_tests

validate_test_run
