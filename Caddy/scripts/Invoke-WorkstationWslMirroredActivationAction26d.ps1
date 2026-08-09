[CmdletBinding()]
param(
    [string]$WslExe = "$env:WINDIR\System32\wsl.exe",
    [string]$Target = "$env:USERPROFILE\.wslconfig",
    [string]$Distribution = "Ubuntu",
    [string]$LinuxUser = "aaron",
    [string]$LinuxInspector = "/home/aaron/code/homelab-server-configs/Caddy/scripts/inspect-workstation-wsl-mirrored-postrestart-action26-d.sh",
    [switch]$AllowNonWindowsTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Prefix = "action_26_d"
$CandidateSha256 = "6dffdf2bfc174eaca2a0bfcf8fe224929fd1006fbb48e3ccf34d642d234ab8a7"
$InspectorSha256 = "c28daa30a7b127d8d6b4ca9e669564350367695e8be4986112b4478d37d23a1d"
$MaximumCaptureBytes = 131072
$MaximumCaptureLines = 2000
$ProcessTimeoutMilliseconds = 30000
$StopTimeoutSeconds = 30
$WorkRoot = Join-Path ([IO.Path]::GetTempPath()) ("caddy-action26-d-" + [guid]::NewGuid().ToString("N"))
$TransactionStarted = $false
$RollbackNeeded = $false
$RollbackProven = $false

function Write-Evidence {
    param([string]$Text)
    [Console]::Out.WriteLine($Text)
}

function Write-Check {
    param([string]$Label, [bool]$Condition)
    if ($Condition) {
        Write-Evidence "${Prefix}_check_${Label}=true"
        return
    }
    [Console]::Error.WriteLine("${Prefix}_check_${Label}=false")
    throw "check failed: $Label"
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-RegularFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $Item = Get-Item -LiteralPath $Path -Force
    return -not (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-SafeText {
    param([string]$Text)
    $Bytes = [Text.Encoding]::UTF8.GetByteCount($Text)
    $Lines = if ($Text.Length -eq 0) { 0 } else { ($Text -split "`n").Count }
    if ($Bytes -gt $MaximumCaptureBytes -or $Lines -gt $MaximumCaptureLines) { return $false }
    if ($Text -match '[^\x09\x0A\x0D\x20-\x7E]') { return $false }
    return $Text -notmatch '(?i)BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:\s*Bearer|Cookie:'
}

function Write-Capture {
    param([string]$Label, [string]$Text)
    $Bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $Lines = if ($Text.Length -eq 0) { 0 } else { ($Text -split "`n").Count }
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try { $Hash = ([BitConverter]::ToString($Hasher.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant() }
    finally { $Hasher.Dispose() }
    Write-Evidence "${Prefix}_capture_${Label}_bytes=$($Bytes.Length)"
    Write-Evidence "${Prefix}_capture_${Label}_lines=$Lines"
    Write-Evidence "${Prefix}_capture_${Label}_sha256=$Hash"
    Write-Check "${Label}_safe" (Test-SafeText $Text)
    Write-Evidence "${Prefix}_capture_${Label}_classification=bounded_safe"
    if ($Text.Length -eq 0) {
        Write-Evidence "${Prefix}_capture_${Label}_content=empty"
    } else {
        Write-Evidence "${Prefix}_capture_${Label}_begin"
        Write-Evidence $Text.TrimEnd("`r", "`n")
        Write-Evidence "${Prefix}_capture_${Label}_end"
    }
}

function Join-ProcessArguments {
    param([string[]]$Items)
    return (($Items | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ')
}

function Invoke-CapturedProcess {
    param([string]$Label, [string]$FilePath, [string[]]$Arguments)
    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $FilePath
    $StartInfo.Arguments = Join-ProcessArguments $Arguments
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    Write-Check "${Label}_process_started" $Process.Start()
    $StdoutTask = $Process.StandardOutput.ReadToEndAsync()
    $StderrTask = $Process.StandardError.ReadToEndAsync()
    $Exited = $Process.WaitForExit($ProcessTimeoutMilliseconds)
    if (-not $Exited) {
        $Process.Kill()
        $Process.WaitForExit()
    }
    $Stdout = $StdoutTask.GetAwaiter().GetResult()
    $Stderr = $StderrTask.GetAwaiter().GetResult()
    $Status = if ($Exited) { $Process.ExitCode } else { 124 }
    $Process.Dispose()
    Write-Evidence "${Prefix}_observed_${Label}_status=$Status"
    Write-Capture "${Label}_stdout" $Stdout
    Write-Capture "${Label}_stderr" $Stderr
    return [pscustomobject]@{ Status = $Status; Stdout = $Stdout; Stderr = $Stderr }
}

function Wait-WslStopped {
    param([string]$Label)
    $Deadline = [DateTime]::UtcNow.AddSeconds($StopTimeoutSeconds)
    $Attempt = 0
    do {
        $Attempt++
        $Result = Invoke-CapturedProcess "${Label}_${Attempt}" $WslExe @("--list", "--running", "--quiet")
        Write-Check "${Label}_${Attempt}_status_zero" ($Result.Status -eq 0)
        if ([string]::IsNullOrWhiteSpace($Result.Stdout)) {
            Write-Evidence "${Prefix}_observed_${Label}_attempts=$Attempt"
            return
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $Deadline)
    throw "WSL did not stop before the bounded deadline"
}

function Invoke-LinuxInspector {
    param([string]$Label, [string]$Expectation)
    return Invoke-CapturedProcess $Label $WslExe @(
        "--distribution", $Distribution,
        "--cd", "/",
        "--user", $LinuxUser,
        "--exec", "/bin/bash", $LinuxInspector, $Expectation
    )
}

function Confirm-InspectorResult {
    param([string]$Label, [object]$Result, [string]$Marker)
    Write-Check "${Label}_status_zero" ($Result.Status -eq 0)
    Write-Check "${Label}_stderr_empty" ([string]::IsNullOrEmpty($Result.Stderr))
    $Lines = @($Result.Stdout -split "`r?`n")
    Write-Check "${Label}_marker_once" (@($Lines | Where-Object { $_ -ceq $Marker }).Count -eq 1)
    Write-Check "${Label}_false_assertions_absent" (@($Lines | Where-Object { $_ -match '^action_26_d_linux_check_.*=false$' }).Count -eq 0)
    Write-Check "${Label}_persistent_mutation_false" (@($Lines | Where-Object { $_ -ceq 'action_26_d_linux_persistent_mutation=false' }).Count -eq 1)
}

function Invoke-Rollback {
    Write-Evidence "${Prefix}_rollback_started=true"
    Write-Check "rollback_target_regular" (Test-RegularFile $Target)
    Write-Check "rollback_target_hash" ((Get-Sha256 $Target) -ceq $CandidateSha256)
    [IO.File]::Delete($Target)
    Write-Check "rollback_target_absent" (-not (Test-Path -LiteralPath $Target))
    $Shutdown = Invoke-CapturedProcess rollback_shutdown $WslExe @("--shutdown")
    Write-Check "rollback_shutdown_status_zero" ($Shutdown.Status -eq 0)
    Wait-WslStopped rollback_stopped
    $InspectorResult = Invoke-LinuxInspector rollback_inspector "--expect-nat"
    Confirm-InspectorResult rollback_inspector $InspectorResult "action_26_d_linux_rollback_acceptance=true"
    $script:RollbackProven = $true
    Write-Evidence "${Prefix}_rollback_complete=true"
}

try {
    New-Item -ItemType Directory -Path $WorkRoot -ErrorAction Stop | Out-Null
    $IsWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    Write-Check windows_host ($IsWindowsHost -or $AllowNonWindowsTest)
    Write-Check not_launched_from_wsl ($AllowNonWindowsTest -or (
        [string]::IsNullOrEmpty($env:WSL_INTEROP) -and [string]::IsNullOrEmpty($env:WSL_DISTRO_NAME)))
    Write-Check wsl_executable_regular (Test-RegularFile $WslExe)
    Write-Check target_regular (Test-RegularFile $Target)
    Write-Check target_hash ((Get-Sha256 $Target) -ceq $CandidateSha256)
    $InspectorWindowsPath = Join-Path $PSScriptRoot "inspect-workstation-wsl-mirrored-postrestart-action26-d.sh"
    Write-Check inspector_regular (Test-RegularFile $InspectorWindowsPath)
    Write-Check inspector_hash ((Get-Sha256 $InspectorWindowsPath) -ceq $InspectorSha256)
    Write-Check windows_temp_present (-not [string]::IsNullOrWhiteSpace([IO.Path]::GetTempPath()))
    Set-Location -LiteralPath ([IO.Path]::GetTempPath())
    $ExpectedTemporaryPath = (Get-Item ([IO.Path]::GetTempPath())).FullName.TrimEnd('\', '/')
    $ObservedTemporaryPath = (Get-Location).Path.TrimEnd('\', '/')
    Write-Check cwd_is_windows_temp ($ObservedTemporaryPath -eq $ExpectedTemporaryPath)
    $DistributionResult = Invoke-CapturedProcess preflight_distributions $WslExe @("--list", "--quiet")
    Write-Check preflight_distributions_status_zero ($DistributionResult.Status -eq 0)
    $InstalledDistributions = @($DistributionResult.Stdout -split "`r?`n" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } | ForEach-Object { $_.Trim() })
    Write-Check preflight_distribution_exact_once (@($InstalledDistributions | Where-Object {
        $_ -ceq $Distribution
    }).Count -eq 1)
    Write-Evidence "${Prefix}_windows_firewall_mutation=false"
    Write-Evidence "${Prefix}_ha_node_administrative_contact=false"
    $TransactionStarted = $true
    $RollbackNeeded = $true
    $Shutdown = Invoke-CapturedProcess activation_shutdown $WslExe @("--shutdown")
    Write-Check activation_shutdown_status_zero ($Shutdown.Status -eq 0)
    Wait-WslStopped activation_stopped
    $InspectorResult = Invoke-LinuxInspector activation_inspector "--expect-mirrored"
    Confirm-InspectorResult activation_inspector $InspectorResult "action_26_d_linux_acceptance=true"
    $RollbackNeeded = $false
    Write-Evidence "${Prefix}_rollback_required=false"
    Write-Evidence "${Prefix}_acceptance=true"
} catch {
    [Console]::Error.WriteLine("${Prefix}_failure=$($_.Exception.Message)")
    if ($TransactionStarted -and $RollbackNeeded) {
        try { Invoke-Rollback }
        catch {
            [Console]::Error.WriteLine("${Prefix}_rollback_failure=$($_.Exception.Message)")
            exit 125
        }
    }
    if ($RollbackProven) { exit 1 }
    exit 1
} finally {
    if (Test-Path -LiteralPath $WorkRoot) { Remove-Item -LiteralPath $WorkRoot -Recurse -Force }
}
