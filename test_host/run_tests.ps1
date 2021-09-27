Param(
    [string]$testDir="${env:SystemDrive}\ceph",
    [string]$resultDir="${env:SystemDrive}\workspace\test_results",
    [string]$cephConfig="$env:ProgramData\ceph\ceph.conf",
    [int]$testSuiteTimeout=300,
    [int]$workerCount=8,
    [bool]$skipSlowTests=$false
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
    log_message "Running test: $testType $testDescription."
}

function notify_successful_test($testDescription, $testType) {
    log_message "$testType $testDescription passed."
}

function notify_failed_test($testDescription, $testType, $errMsg) {
    # We're going to resume running tests even if one of the suite fails,
    # throwing an error at the end of the run.
    $env:TEST_FAILED = "1"

    log_message "$testType $testDescription failed. Error: $errMsg"
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
            $tags = "$testType[standalone]"
        }
        else {
            $isGtest = $true
            $testArgs = ""
            $tags = "$testType[googletest]"
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
        [System.Object[]]$finished = $jobs | ? {$_.Result.IsCompleted -eq $true}
        log_message "Finished $($finished.Count) out of $($jobs.Count) jobs."
    } while ($finished.Count -lt $jobs.Count)

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

function run_tests() {
    $subunitFile = "$resultDir\subunit.out"
    $testPattern="^unittest.*.exe$|^ceph_test.*.exe$"
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
        # This test passes but it leaks a "sleep" subprocess which
        # hangs powershell's job mechanism.
        "unittest_subprocess.exe"="SubProcessTimed.SubshellTimedout";
        "ceph_test_signal_handlers.exe"="*";
        # TODO - we may stick to the client tests, but this may also
        # involve RGW, which we haven't covered yet.
        "ceph_test_admin_socket_output.exe"="*";
        # The following tests fail because of the pseudo-random
        # numbers generated by rand, getting increased chance of
        # false positives.
        "unittest_bloom_filter"=@(
            "BloomFilter.SweepInt",
            "BloomFilter.CompressibleSweep");
        # execinfo.h isn't available on Windows, this may need a
        # different approach.
        "unittest_back_trace.exe"="*";
        # Those tests throttle some operations. We're meeting the
        # high threshold but we miss the low threshold.
        "unittest_throttle.exe"="*";
        # The Mingw C runtime seems to have some issues. Among others,
        # the "%z" flag isn't handled properly by strftime.
        "unittest_time.exe"="TimePoints.stringify"
        "unittest_utime.exe"=@(
            "utime_t.localtime",
            "utime_t.parse_date");
        # The following tests are affected by errno conversions
        "ceph_test_rados_api_snapshots_pp.exe"=`
            # EOLDSNAPC is defined as 85, which overlaps with ERESTART,
            # which will be converted to EINTR
            "LibRadosSnapshotsSelfManagedPP.OrderSnap";
        # cls_helo.cc:write_return_data returns 42, which will be converted
        # TODO: ensure that this won't affect the rados/rbd (e.g. we may
        # end up converting values other than error codes, which is wrong).
        "ceph_test_rados_api_tier_pp.exe"=`
            "LibRadosTwoPoolsPP.HelloWriteReturn";
        # TODO: look into this. seems like a local error (ECANCELED) gets
        # converted to the unix value, yet the test expects the host error.
        "ceph_test_rados_api_aio_pp.exe"="LibRadosAio.OmapPP";
        # TODO: some watch timeout is not honored. Watch3 seems to be broken.
        "ceph_test_rados_api_watch_notify.exe"="LibRadosWatchNotify.Watch3Timeout";
        "ceph_test_rados_api_watch_notify_pp.exe"="*WatchNotify3*";
        # TODO
        "ceph_test_lazy_omap_stats.exe"="*";
        # seems broken. When shutting down timers, it asserts that a lock is
        # set but nobody's locking it. It passes if CEPH_DEBUG_MUTEX is
        # disabled, in which case such checks always return 1.
        "ceph_test_timers.exe"="*";
        # For some reason, the following tests gets WSAECONNREFUSED errors but
        # only when running under a powershell job, passing otherwise.
        "unittest_perf_counters.exe"="*";
        # TODO: Need debugging
        "unittest_compression.exe"="*";
        "unittest_confutils.exe"=@(
            "ConfUtils.ParseFiles0");
        "unittest_fair_mutex.exe"=@(
            "FairMutex.fair");
        "unittest_mempool.exe"=@(
            "mempool.check_shard_select");
    }
    $slowTestList=@{
        # Takes about 20 minutes, all the rest finish in about 5 minutes.
        "ceph_test_rados_api_tier_pp.exe"="*";
    }
    # The following tests have to be run separately.
    $isolatedTests=@{
        "unittest_bufferlist.exe"="*-BufferList.read_file";
        "unittest_admin_socket.exe"="*";
    }

    ($manualTests.Keys + $isolatedTests.Keys) | ForEach-Object { $excludedTests += @{$_="*"} }
    if ($skipSlowTests) {
        $slowTestList.Keys | ForEach-Object { $excludedTests += @{$_="*"} }
    }

    log_message "Running unit tests."
    log_message "Using subunit file: $subunitFile"

    run_tests_from_dir -testdir $testDir `
                       -resultDir $resultDir `
                       -pattern $testPattern `
                       -isolatedTestsMapping $excludedTests `
                       -runIsolatedTests $false `
                       -testType "" `
                       -subunitOutFile $subunitFile `
                       -workerCount $workerCount `
                       -nonGTestList $nonGTestList

    # Various tests that are known to crash, hang or cannot be run in parallel.
    log_message "Running isolated unit tests."
    run_tests_from_dir -testdir $testDir `
                       -resultDir $resultDir `
                       -pattern $testPattern `
                       -isolatedTestsMapping $isolatedTests `
                       -runIsolatedTests $true `
                       -testType "[isolated]" `
                       -subunitOutFile $subunitFile `
                       -workerCount 1 `
                       -nonGTestList $nonGTestList

    generate_subunit_report $subunitFile $resultDir `
                            "test_results"
}

ensure_dir_exists $resultDir

clear_test_stats

run_tests

validate_test_run
