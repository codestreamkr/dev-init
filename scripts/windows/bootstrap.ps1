[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoUpgrade,
    [switch]$SkipAiInit
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Resolve-Path (Join-Path $ScriptDir "..\..")
$PackageFile = Join-Path $RootDir "config\winget\packages.txt"

function Test-Windows {
    if ([Environment]::OSVersion.Platform -ne "Win32NT") {
        throw "This script must run on Windows."
    }
}

function Test-Winget {
    [void](Get-WingetCommand)
}

function Get-WingetCommand {
    $WingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue

    if (-not $WingetCommand) {
        $WingetCommand = Get-Command winget -ErrorAction SilentlyContinue
    }

    if (-not $WingetCommand) {
        throw "winget is not installed. Install App Installer from Microsoft Store first."
    }

    return $WingetCommand.Source
}

function Invoke-WingetCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $Winget = Get-WingetCommand

    Write-Host "Running: $Winget $($Arguments -join ' ')"
    & $Winget @Arguments | ForEach-Object { Write-Host $_ }
    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0 -and -not $AllowFailure) {
        throw "winget failed with exit code $ExitCode: $($Arguments -join ' ')"
    }

    return $ExitCode
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

    throw "git is not available. Reopen PowerShell after Git installation and run this script again."
}

function Get-WingetPackages {
    if (-not (Test-Path $PackageFile)) {
        throw "Package file not found: $PackageFile"
    }

    Get-Content $PackageFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") }
}

function Test-WingetPackageInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    $Winget = Get-WingetCommand
    $Arguments = @(
        "list",
        "--id",
        $PackageId,
        "--exact",
        "--accept-source-agreements"
    )

    Write-Host "Running: $Winget $($Arguments -join ' ')"
    $Output = & $Winget @Arguments 2>&1
    $ExitCode = $LASTEXITCODE

    foreach ($Line in $Output) {
        Write-Host $Line
    }

    if ($ExitCode -ne 0) {
        return $false
    }

    $PackagePattern = "(^|\s)$([regex]::Escape($PackageId))(\s|$)"
    return [bool]($Output | Where-Object { $_ -match $PackagePattern })
}

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    if ($DryRun) {
        Write-Host "[dry-run] winget list --id $PackageId --exact"
        Write-Host "[dry-run] winget install --id $PackageId --exact --silent"
        return [pscustomobject]@{
            PackageId = $PackageId
            Status = "DryRun"
            ExitCode = 0
        }
    }

    if (Test-WingetPackageInstalled -PackageId $PackageId) {
        Write-Host "Already installed: $PackageId"
        return [pscustomobject]@{
            PackageId = $PackageId
            Status = "Skipped"
            ExitCode = 0
        }
    }

    $ExitCode = Invoke-WingetCommand -Arguments @(
        "install",
        "--id",
        $PackageId,
        "--exact",
        "--silent",
        "--accept-package-agreements",
        "--accept-source-agreements"
    ) -AllowFailure

    if ($ExitCode -eq 0) {
        return [pscustomobject]@{
            PackageId = $PackageId
            Status = "Installed"
            ExitCode = 0
        }
    }

    return [pscustomobject]@{
        PackageId = $PackageId
        Status = "Failed"
        ExitCode = $ExitCode
    }
}

function Invoke-WingetPackageInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Packages
    )

    $Results = foreach ($Package in $Packages) {
        Invoke-WingetInstall -PackageId $Package
    }

    $Failed = @($Results | Where-Object { $_.Status -eq "Failed" })

    if ($Failed.Count -eq 0) {
        Write-Host "Winget package installation completed."
        return
    }

    Write-Host "Winget package installation failed for $($Failed.Count) package(s)."

    foreach ($Item in $Failed) {
        Write-Host "- $($Item.PackageId): exit code $($Item.ExitCode)"
    }

    throw "One or more winget packages failed to install."
}

function Write-WingetUpgradeNotice {
    if ($NoUpgrade) {
        return
    }

    Write-Host "Skipping winget upgrade --all during bootstrap."
    Write-Host "Reason: App Installer upgrades require a new PowerShell session before winget can run reliably."
}

function Install-ClaudeCli {
    if ($DryRun) {
        Write-Host "[dry-run] Install Claude CLI with temporary certificate validation bypass, then restore callback."
        return
    }

    Write-Host "Installing Claude CLI with temporary certificate validation bypass..."

    $prev = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

    try {
        irm https://claude.ai/install.ps1 | iex
    }
    finally {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $prev
    }
}

function Invoke-GitClone {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $Git = Get-GitCommand

    if (Test-Path $Destination) {
        Remove-Item -Recurse -Force $Destination
    }

    & $Git clone $Repository $Destination
}

function Invoke-AiInit {
    if ($SkipAiInit) {
        return
    }

    $CodexDir = Join-Path $env:TEMP "codex-init"
    $ClaudeDir = Join-Path $env:TEMP "claude-init"

    if ($DryRun) {
        Write-Host "[dry-run] git clone https://github.com/codestreamkr/chatgpt-codex-init.git $CodexDir"
        Write-Host "[dry-run] & $CodexDir\install.ps1"
        Write-Host "[dry-run] git clone https://github.com/codestreamkr/claude-code-init.git $ClaudeDir"
        Write-Host "[dry-run] & $ClaudeDir\install.ps1"
        return
    }

    Invoke-GitClone -Repository "https://github.com/codestreamkr/chatgpt-codex-init.git" -Destination $CodexDir
    & (Join-Path $CodexDir "install.ps1")

    Invoke-GitClone -Repository "https://github.com/codestreamkr/claude-code-init.git" -Destination $ClaudeDir
    & (Join-Path $ClaudeDir "install.ps1")
}

function Main {
    Test-Windows
    Test-Winget

    $Packages = Get-WingetPackages

    Write-WingetUpgradeNotice

    Invoke-WingetPackageInstall -Packages $Packages

    Install-ClaudeCli
    Invoke-AiInit
}

Main
