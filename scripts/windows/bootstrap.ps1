[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoUpgrade,
    [switch]$SkipAiInit
)

$ErrorActionPreference = "Stop"
$script:AiInitRequired = $false

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
        throw "winget failed with exit code ${ExitCode}: $($Arguments -join ' ')"
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

    Write-Host "Checking installed package: $PackageId"
    $Output = & $Winget @Arguments 2>&1
    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0) {
        # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND (signed or unsigned HRESULT).
        if (($ExitCode -band 0xffffffffL) -eq 0x8A150014L) {
            return $false
        }
        throw "winget list failed with exit code ${ExitCode}: $PackageId"
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
        Write-Host "[dry-run] If missing: winget install --id $PackageId --exact --silent"
        if (-not $NoUpgrade) {
            Write-Host "[dry-run] If installed: winget upgrade --id $PackageId --exact --silent --include-unknown"
        }
        return [pscustomobject]@{ PackageId = $PackageId; Status = "DryRun"; ExitCode = 0 }
    }

    $Operation = "install"
    if (Test-WingetPackageInstalled -PackageId $PackageId) {
        if ($NoUpgrade) {
            Write-Host "Already installed; upgrades disabled: $PackageId"
            return [pscustomobject]@{ PackageId = $PackageId; Status = "Skipped"; ExitCode = 0 }
        }
        $Operation = "upgrade"
    }

    $Arguments = @(
        $Operation, "--id", $PackageId, "--exact", "--silent",
        "--accept-package-agreements", "--accept-source-agreements"
    )
    if ($Operation -eq "upgrade") { $Arguments += "--include-unknown" }
    $ExitCode = Invoke-WingetCommand -Arguments $Arguments -AllowFailure

    $Status = "Failed"
    if ($ExitCode -eq 0) {
        if ($Operation -eq "upgrade") { $Status = "Updated" }
        else { $Status = "Installed" }
    }
    elseif ($Operation -eq "upgrade" -and ($ExitCode -band 0xffffffffL) -eq 0x8A15002BL) {
        # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE: already current.
        $Status = "UpToDate"
    }
    return [pscustomobject]@{ PackageId = $PackageId; Status = $Status; ExitCode = $ExitCode }
}

function Invoke-WingetPackageInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Packages
    )

    $Results = foreach ($Package in $Packages) {
        try {
            Invoke-WingetInstall -PackageId $Package
        }
        catch {
            Write-Host "Package operation failed: $Package - $($_.Exception.Message)"
            [pscustomobject]@{ PackageId = $Package; Status = "Failed"; ExitCode = -1 }
        }
    }

    $Failed = @($Results | Where-Object { $_.Status -eq "Failed" })

    if ($Failed.Count -eq 0) {
        Write-Host "Winget package installation/update completed."
        return
    }

    Write-Host "Winget package installation/update failed for $($Failed.Count) package(s)."

    foreach ($Item in $Failed) {
        Write-Host "- $($Item.PackageId): exit code $($Item.ExitCode)"
    }

    throw "One or more winget packages failed to install or update."
}

function Test-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-ClaudeCli {
    if (Test-CommandAvailable -Name "claude") {
        if ($NoUpgrade) {
            Write-Host "Already installed; upgrades disabled: Claude CLI"
        }
        elseif ($DryRun) {
            Write-Host "[dry-run] claude update"
        }
        else {
            & claude update
            if ($LASTEXITCODE -ne 0) { throw "Claude CLI update failed with exit code $LASTEXITCODE" }
        }
        return
    }

    if ($DryRun) {
        Write-Host "[dry-run] Download https://claude.ai/install.ps1 with certificate validation and run it."
        return
    }

    $PreviousSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = $PreviousSecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $Installer = Invoke-RestMethod -Uri "https://claude.ai/install.ps1"
        Invoke-Expression $Installer
        $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
        if (-not (Test-CommandAvailable -Name "claude")) {
            throw "Claude CLI installation did not make claude available."
        }
    }
    finally {
        [System.Net.ServicePointManager]::SecurityProtocol = $PreviousSecurityProtocol
    }
}

function Install-NativeAiCli {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$InstallerUrl
    )

    $env:PATH = "$env:LOCALAPPDATA\agy\bin;$env:USERPROFILE\.local\bin;$env:USERPROFILE\.grok\bin;$env:PATH"
    if (Test-CommandAvailable -Name $CommandName) {
        if ($NoUpgrade) {
            Write-Host "Already installed; upgrades disabled: $CommandName"
        }
        elseif ($DryRun) {
            Write-Host "[dry-run] $CommandName update"
        }
        else {
            & $CommandName update
            if ($LASTEXITCODE -ne 0) { throw "$CommandName update failed with exit code $LASTEXITCODE" }
        }
        return
    }
    if ($DryRun) {
        Write-Host "[dry-run] Download $InstallerUrl and run the native installer."
        return
    }

    $InstallerPath = Join-Path $env:TEMP ("dev-init-" + [guid]::NewGuid() + ".ps1")
    $PreviousSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = $PreviousSecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $Installer = Invoke-RestMethod -Uri $InstallerUrl
        Set-Content -LiteralPath $InstallerPath -Value $Installer -Encoding UTF8
        Invoke-PowerShellScript -ScriptPath $InstallerPath
        $env:PATH = "$env:LOCALAPPDATA\agy\bin;$env:USERPROFILE\.local\bin;$env:USERPROFILE\.grok\bin;$env:PATH"
        if (-not (Test-CommandAvailable -Name $CommandName)) {
            throw "$CommandName installation did not make the command available."
        }
        $script:AiInitRequired = $true
    }
    finally {
        [System.Net.ServicePointManager]::SecurityProtocol = $PreviousSecurityProtocol
        if (Test-Path -LiteralPath $InstallerPath) { Remove-Item -LiteralPath $InstallerPath }
    }
}

function Install-PiCli {
    $AlreadyInstalled = Test-CommandAvailable -Name "pi"
    if ($AlreadyInstalled -and $NoUpgrade) {
        Write-Host "Already installed; upgrades disabled: Pi CLI"
        return
    }
    $NpmPrefix = Join-Path $env:APPDATA "npm"
    if ($DryRun) {
        Write-Host "[dry-run] npm.cmd install --global --prefix $NpmPrefix --ignore-scripts @earendil-works/pi-coding-agent@latest"
        return
    }

    & npm.cmd install --global --prefix $NpmPrefix --ignore-scripts @earendil-works/pi-coding-agent@latest
    if ($LASTEXITCODE -ne 0) { throw "Pi CLI installation/update failed with exit code $LASTEXITCODE" }
    $env:PATH = "$NpmPrefix;$env:PATH"
    if (-not (Test-CommandAvailable -Name "pi")) { throw "Pi CLI installation did not make pi available." }
    if (-not $AlreadyInstalled) { $script:AiInitRequired = $true }
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
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code ${LASTEXITCODE}: $Repository"
    }
}

function Invoke-PowerShellScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $PowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue

    if (-not $PowerShell) {
        throw "powershell.exe is not available."
    }

    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $ScriptPath
    )

    Write-Host "Running: $($PowerShell.Source) $($Arguments -join ' ')"
    & $PowerShell.Source @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "PowerShell script failed with exit code ${LASTEXITCODE}: $ScriptPath"
    }
}

function Invoke-AiInitRepository {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $StateDir = Join-Path $env:LOCALAPPDATA "dev-init"
    $Marker = Join-Path $StateDir "$CommandName.initialized"

    if ((Test-Path $Marker) -and -not $script:AiInitRequired) {
        Write-Host "Already initialized: $CommandName"
        return
    }

    if ($DryRun) {
        Write-Host "[dry-run] git clone $Repository $Destination"
        Write-Host "[dry-run] powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Destination\install.ps1"
        return
    }

    Invoke-GitClone -Repository $Repository -Destination $Destination
    Invoke-PowerShellScript -ScriptPath (Join-Path $Destination "install.ps1")
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    New-Item -ItemType File -Force -Path $Marker | Out-Null
}

function Invoke-AiInit {
    if ($SkipAiInit) {
        return
    }

    $AiInitDir = Join-Path $env:TEMP "ai-comm-init"

    Invoke-AiInitRepository `
        -CommandName "ai-comm-init" `
        -Repository "https://github.com/codestreamkr/ai-comm-init.git" `
        -Destination $AiInitDir
}

function Main {
    Test-Windows
    Test-Winget

    $Packages = Get-WingetPackages

    Invoke-WingetPackageInstall -Packages $Packages

    # Refresh user and machine PATH after winget installs Node and other CLIs.
    if (-not $DryRun) {
        $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User") + ";" + $env:PATH
    }
    Install-ClaudeCli
    Install-NativeAiCli -CommandName "agy" -InstallerUrl "https://antigravity.google/cli/install.ps1"
    Install-NativeAiCli -CommandName "grok" -InstallerUrl "https://x.ai/cli/install.ps1"
    Install-PiCli
    Invoke-AiInit
}

Main
