$scriptLocation = [System.IO.Path]::GetDirectoryName(
    $myInvocation.MyCommand.Definition)

. "$scriptLocation\common.ps1"

function _set_env($key, $val, $target="User") {
    $acceptableTargetList = @("process", "user", "machine")
    if ($target.ToLower() -notin $acceptableTargetList) {
        throw ("Cannot set environment variable `"$key`" to `"$val`". " +
               "Unsupported target: `"$target`".")
    }

    $varTarget = [System.EnvironmentVariableTarget]::$target

    [System.Environment]::SetEnvironmentVariable($key, $val, $varTarget)
}

function set_env($key, $val, $target="User") {
    log_message ("Setting environment value: `"$key`" = `"$val`". " +
                 "Target: `"$target`".")
    _set_env $key $val $target
    # You'll always want to set the "Process" target as well, so that
    # it applies to the current process. Just to avoid some weird issues,
    # we're setting it here.
    _set_env $key $val "Process"
}

function get_env($var) {
    [System.Environment]::GetEnvironmentVariable($var)
}

function env_path_var_contains($path, $var="PATH") {
    # This may used for %PATH% and similar environment variables,
    # e.g. PYHTONPATH.
    $normPath = $path.Replace("\", "\\").Trim("\")
    (get_env $var) -imatch "(?:^|;)$normPath\\?(?:$|;)"
}

function add_to_env_path($path, $target="User", $var="PATH"){
    if (!(env_path_var_contains $path $var)) {
        log_message "Adding `"$path`" to %$var%."

        $currentPath = get_env $var
        $newPath = "$currentPath;$path".Trim(";")

        set_env $var $newPath $target
    }
    else {
        log_message "%$var% already contains `"$path`"."
    }
}

function check_elevated() {
    log_message "Checking elevated permissions."

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = new-object System.Security.Principal.WindowsPrincipal(
        $identity)
    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $elevated = $principal.IsInRole($adminRole)
    if (!$elevated) {
        throw "This script requires elevated privileges."
    }
}

function stop_processes($name) {
    log_message "Stopping process(es): `"$name`"."
    get-process $name |  stop-process -PassThru | `
        % { log_message "Stopped process: `"$($_.Name)`"." }
}

function check_windows_feature($featureName) {
    log_message("Ensuring that the following Windows feature is available: " +
                "`"$featureName`".")

    $feature = Get-WindowsOptionalFeature -FeatureName "$featureName" -Online
    if (!($feature)) {
        throw "Could not find Windows feature: `"$featureName`"."
    }
    if ($feature.Count -gt 1) {
        # We're going to allow wildcards.
        log_message ("WARNING: Found multiple features matching " +
                     "the specified name: $($feature.FeatureName). " +
                     "Will ensure that all of them are enabled.")
        log_message $msg
    }

    $feature | `
        ? { $_.State -eq "Enabled" } | `
        % { log_message ("The following Windows feature is available: " +
                         "`"$($_.FeatureName)`".")}
    $disabledFeatures = @()
    $feature | `
        ? { $_.State -ne "Enabled" } | `
        % { $disabledFeatures += $_.FeatureName }

    if ($disabledFeatures) {
        throw "The following Windows features are not enabled: $missingFeatures."
    }
}

function enable_rdp_access() {
    log_message "Enabling RDP access."

    Set-ItemProperty `
        -Path "HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
}

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$JobMgrDefinition = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class JobMgr
{
    public enum JOBOBJECTINFOCLASS
    {
        AssociateCompletionPortInformation = 7,
        BasicLimitInformation = 2,
        BasicUIRestrictions = 4,
        EndOfJobTimeInformation = 6,
        ExtendedLimitInformation = 9,
        SecurityLimitInformation = 5,
        GroupInformation = 11
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public Int64 PerProcessUserTimeLimit;
        public Int64 PerJobUserTimeLimit;
        public UInt32 LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public UInt32 ActiveProcessLimit;
        public Int64 Affinity;
        public UInt32 PriorityClass;
        public UInt32 SchedulingClass;
    }


    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS
    {
        public UInt64 ReadOperationCount;
        public UInt64 WriteOperationCount;
        public UInt64 OtherOperationCount;
        public UInt64 ReadTransferCount;
        public UInt64 WriteTransferCount;
        public UInt64 OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateJobObject(
        IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll")]
    public static extern bool AssignProcessToJobObject(
        IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll")]
    public static extern bool SetInformationJobObject(
        IntPtr hJob, JOBOBJECTINFOCLASS JobObjectInfoClass,
        IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();


    private const UInt32 JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    public void register_current_proc_as_job(string jobName)
    {
        IntPtr hJob = CreateJobObject(IntPtr.Zero, jobName);

        JOBOBJECT_BASIC_LIMIT_INFORMATION info =
            new JOBOBJECT_BASIC_LIMIT_INFORMATION();
        info.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

        JOBOBJECT_EXTENDED_LIMIT_INFORMATION extendedInfo =
            new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        extendedInfo.BasicLimitInformation = info;

        int length = Marshal.SizeOf(
            typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr extendedInfoPtr = Marshal.AllocHGlobal(length);
        Marshal.StructureToPtr(extendedInfo, extendedInfoPtr, false);

        SetInformationJobObject(hJob,
                                JOBOBJECTINFOCLASS.ExtendedLimitInformation,
                                extendedInfoPtr,
                                (uint)length);

        IntPtr hProcess = GetCurrentProcess();
        bool blRc = AssignProcessToJobObject(hJob, hProcess);

        Marshal.FreeHGlobal(extendedInfoPtr);
    }
}
"@


function run_as_job($jobName) {
    # This will ensure that this process's children will be part of the same
    # job object, being stopped along with it when it exits.
    if (! $jobName) {
        $jobName = [guid]::NewGuid().Guid
    }
    Add-Type -TypeDefinition $JobMgrDefinition

    $mgr = New-Object JobMgr
    $mgr.register_current_proc_as_job($jobName)
}
