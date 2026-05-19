[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoUpgrade,
    [switch]$SkipAiInit
)

$ErrorActionPreference = "Stop"

$RepositoryUrl = "https://github.com/codestreamkr/dev-init.git"
$TargetDir = Join-Path $env:TEMP "dev-init"
$InstallParameters = @{}

if ($DryRun) {
    $InstallParameters["DryRun"] = $true
}

if ($NoUpgrade) {
    $InstallParameters["NoUpgrade"] = $true
}

if ($SkipAiInit) {
    $InstallParameters["SkipAiInit"] = $true
}

function Test-Windows {
    if ([Environment]::OSVersion.Platform -ne "Win32NT") {
        throw "This script must run on Windows."
    }
}

function Test-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is not installed. Install App Installer from Microsoft Store first."
    }
}

function Get-GitCommand {
    $GitCommand = Get-Command git -ErrorAction SilentlyContinue

    if ($GitCommand) {
        return $GitCommand.Source
    }

    $Candidates = @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "$env:ProgramFiles\Git\bin\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
        "${env:ProgramFiles(x86)}\Git\bin\git.exe"
    )

    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path $Candidate)) {
            return $Candidate
        }
    }

    return $null
}

function Install-Git {
    Test-Winget

    if ($DryRun) {
        Write-Host "[dry-run] winget install --id Git.Git --exact --silent"
        return
    }

    winget install `
        --id Git.Git `
        --exact `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements
}

function Ensure-Git {
    $Git = Get-GitCommand

    if ($Git) {
        return $Git
    }

    Install-Git

    $Git = Get-GitCommand

    if ($Git) {
        return $Git
    }

    throw "git was installed, but it is not available in this PowerShell session. Reopen PowerShell and run this command again."
}

function Invoke-RepositoryInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Git
    )

    if ($DryRun) {
        Write-Host "[dry-run] Remove $TargetDir"
        Write-Host "[dry-run] git clone $RepositoryUrl $TargetDir"
        Write-Host "[dry-run] & $TargetDir\install.ps1"
        return
    }

    if (Test-Path $TargetDir) {
        Remove-Item -Recurse -Force $TargetDir
    }

    & $Git clone $RepositoryUrl $TargetDir

    $Install = Join-Path $TargetDir "install.ps1"
    & $Install @InstallParameters
}

function Main {
    Test-Windows

    $Git = Ensure-Git
    Invoke-RepositoryInstall -Git $Git
}

Main
