$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Import-Functions([string]$Path) {
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count) { throw ($Errors | Out-String) }
    $Functions = $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    return [scriptblock]::Create(($Functions.Extent.Text -join "`n"))
}

. (Import-Functions (Join-Path $Root "boot.ps1"))
function Test-Windows { }
function Get-GitCommand { return $null }
function Ensure-Git { throw "Dry-run must not require Git." }
$DryRun = $true
$RepositoryUrl = "example"
$TargetDir = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
Main

$DryRun = $false
function Test-GitFailure { $global:LASTEXITCODE = 128 }
$Failed = $false
try { Invoke-RepositoryInstall -Git "Test-GitFailure" }
catch { $Failed = $_.Exception.Message -like "git clone failed*" }
if (-not $Failed) { throw "Clone failure was not propagated." }

. (Import-Functions (Join-Path $Root "scripts/windows/bootstrap.ps1"))
# Package lifecycle tests use mock commands; no software is installed.
$NoUpgrade = $false
$DryRun = $false
$script:Installed = $false
$script:CommandExitCode = 0
$script:Calls = @()
function Test-WingetPackageInstalled { return $script:Installed }
function Invoke-WingetCommand {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $script:Calls += ,$Arguments
    return $script:CommandExitCode
}
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message - expected $Expected, got $Actual" }
}
$Result = Invoke-WingetInstall -PackageId Example.App
Assert-Equal $Result.Status Installed "Missing package"
Assert-Equal $script:Calls[-1][0] install "Missing package command"

$script:Installed = $true
$Result = Invoke-WingetInstall -PackageId Example.App
Assert-Equal $Result.Status Updated "Installed package"
Assert-Equal $script:Calls[-1][0] upgrade "Installed package command"
if ($script:Calls[-1] -notcontains '--include-unknown') { throw "Unknown versions must also be upgraded." }

foreach ($Code in @(-1978335189, 0x8A15002BL)) {
    $script:CommandExitCode = $Code
    Assert-Equal (Invoke-WingetInstall Example.App).Status UpToDate "Already latest"
}
$script:CommandExitCode = 1
Assert-Equal (Invoke-WingetInstall Example.App).Status Failed "Upgrade failure"
$script:Installed = $false
$script:CommandExitCode = -1978335189
Assert-Equal (Invoke-WingetInstall Example.App).Status Failed "Install failure must not be treated as up to date"

$NoUpgrade = $true
$script:Installed = $true
$Before = $script:Calls.Count
Assert-Equal (Invoke-WingetInstall Example.App).Status Skipped "NoUpgrade"
Assert-Equal $script:Calls.Count $Before "NoUpgrade command count"
$script:Installed = $false
$script:CommandExitCode = 0
Assert-Equal (Invoke-WingetInstall Example.App).Status Installed "NoUpgrade still installs missing packages"

$NoUpgrade = $false
$DryRun = $true
$Before = $script:Calls.Count
Assert-Equal (Invoke-WingetInstall Example.App).Status DryRun "Dry-run"
Assert-Equal $script:Calls.Count $Before "Dry-run command count"
$DryRun = $false
$NoUpgrade = $false

# A failure must not stop later package operations, but must fail the batch.
$script:Checked = @()
function Test-WingetPackageInstalled {
    param([string]$PackageId)
    $script:Checked += $PackageId
    if ($PackageId -eq 'Broken.App') { throw "Source unavailable" }
    return $false
}
$Failed = $false
try { Invoke-WingetPackageInstall @('Broken.App', 'Good.App') }
catch { $Failed = $true }
if (-not $Failed -or $script:Checked -notcontains 'Good.App') { throw "Batch failure handling failed." }

# Restore actual functions and test lookup exit codes through a mock executable.
. (Import-Functions (Join-Path $Root "scripts/windows/bootstrap.ps1"))
function Get-WingetCommand { return 'Test-WingetLookup' }
$script:LookupCode = 0
function Test-WingetLookup {
    $global:LASTEXITCODE = $script:LookupCode
    'Example App Example.App 1.0'
}
Assert-Equal (Test-WingetPackageInstalled Example.App) $true "Installed lookup"
$script:LookupCode = -1978335212
Assert-Equal (Test-WingetPackageInstalled Example.App) $false "Missing lookup"
$script:LookupCode = 1
$Failed = $false
try { Test-WingetPackageInstalled Example.App }
catch { $Failed = $true }
if (-not $Failed) { throw "Lookup errors must not be treated as missing packages." }

# Existing Claude updates by default, skips only with NoUpgrade, propagates failure.
function Test-CommandAvailable { return $true }
$script:ClaudeCalls = 0
$script:ClaudeExit = 0
function claude { $script:ClaudeCalls++; $global:LASTEXITCODE = $script:ClaudeExit }
Install-ClaudeCli
Assert-Equal $script:ClaudeCalls 1 "Claude default update"
$NoUpgrade = $true
Install-ClaudeCli
Assert-Equal $script:ClaudeCalls 1 "Claude NoUpgrade"
$NoUpgrade = $false
$DryRun = $true
Install-ClaudeCli
Assert-Equal $script:ClaudeCalls 1 "Claude dry-run"
$DryRun = $false
$script:ClaudeExit = 1
$Failed = $false
try { Install-ClaudeCli }
catch { $Failed = $true }
if (-not $Failed) { throw "Claude update failure must propagate." }

$OriginalLocalAppData = $env:LOCALAPPDATA
$TestDirectory = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
$env:LOCALAPPDATA = $TestDirectory
$DryRun = $false
$script:Runs = 0
$script:AiInitRequired = $false
function Test-CommandAvailable { return $true }
function Invoke-GitClone { }
function Invoke-PowerShellScript { $script:Runs++ }
try {
    Invoke-AiInitRepository -CommandName codex -Repository example -Destination unused
    Invoke-AiInitRepository -CommandName codex -Repository example -Destination unused
    if ($script:Runs -ne 1) { throw "Initialization must run once even when CLI exists." }

    # Old per-CLI markers must not prevent the shared initialization.
    New-Item -ItemType File -Path (Join-Path $TestDirectory "dev-init/claude.initialized") | Out-Null
    $Before = $script:Runs
    Invoke-AiInit
    Invoke-AiInit
    Assert-Equal $script:Runs ($Before + 1) "Shared initialization must run once despite old markers"
    $Before = $script:Runs
    $script:AiInitRequired = $true
    Invoke-AiInit
    Assert-Equal $script:Runs ($Before + 1) "New CLI must refresh links despite the shared marker"
    $script:AiInitRequired = $false
    Remove-Item (Join-Path $TestDirectory "dev-init/claude.initialized")

    function Invoke-PowerShellScript { throw "Install failed" }
    $Failed = $false
    try { Invoke-AiInitRepository -CommandName claude -Repository example -Destination unused }
    catch { $Failed = $true }
    if (-not $Failed) { throw "Initialization failure was not propagated." }
    if (Test-Path (Join-Path $TestDirectory "dev-init/claude.initialized")) {
        throw "Failed initialization must not create a marker."
    }
    Write-Host "Windows regression checks passed."
}
finally {
    $env:LOCALAPPDATA = $OriginalLocalAppData
    if (Test-Path $TestDirectory) { Remove-Item -Recurse -Force $TestDirectory }
}

# Check the entrypoint routes to the shared repository once and honors SkipAiInit.
$script:Routes = @()
function Invoke-AiInitRepository {
    param($CommandName, $Repository, $Destination)
    $script:Routes += [pscustomobject]@{ Name = $CommandName; Repository = $Repository; Destination = $Destination }
}
$SkipAiInit = $false
Invoke-AiInit
$SkipAiInit = $true
Invoke-AiInit
Assert-Equal $script:Routes.Count 1 "AI entrypoint invocation count"
Assert-Equal $script:Routes[0].Name 'ai-comm-init' "AI marker identity"
Assert-Equal $script:Routes[0].Repository 'https://github.com/codestreamkr/ai-comm-init.git' "AI repository"
Assert-Equal $script:Routes[0].Destination (Join-Path $env:TEMP 'ai-comm-init') "AI destination"
Write-Host "Shared AI entrypoint checks passed."

# Native AI CLI lifecycle tests use functions instead of installed applications.
. (Import-Functions (Join-Path $Root "scripts/windows/bootstrap.ps1"))
$NoUpgrade = $false
$DryRun = $false
$script:AiInitRequired = $false
$script:CliInstalled = $true
$script:CliCalls = 0
$script:CliExit = 0
function Test-CommandAvailable { return $script:CliInstalled }
function agy { $script:CliCalls++; $global:LASTEXITCODE = $script:CliExit }
function grok { $script:CliCalls++; $global:LASTEXITCODE = $script:CliExit }
foreach ($Name in @('agy', 'grok')) {
    $Before = $script:CliCalls
    Install-NativeAiCli -CommandName $Name -InstallerUrl 'https://example.invalid/install.ps1'
    Assert-Equal $script:CliCalls ($Before + 1) "Native CLI update"
    $NoUpgrade = $true
    Install-NativeAiCli -CommandName $Name -InstallerUrl 'https://example.invalid/install.ps1'
    Assert-Equal $script:CliCalls ($Before + 1) "Native CLI NoUpgrade"
    $NoUpgrade = $false
    $DryRun = $true
    Install-NativeAiCli -CommandName $Name -InstallerUrl 'https://example.invalid/install.ps1'
    Assert-Equal $script:CliCalls ($Before + 1) "Native CLI dry-run"
    $DryRun = $false
    $script:CliExit = 7
    $Failed = $false
    try { Install-NativeAiCli -CommandName $Name -InstallerUrl 'https://example.invalid/install.ps1' }
    catch { $Failed = $true }
    if (-not $Failed) { throw "Native CLI update failure must propagate." }
    $script:CliExit = 0
}

$script:Downloads = 0
function Invoke-RestMethod {
    param($Uri)
    Assert-Equal $Uri 'https://example.invalid/install.ps1' "Native installer URL"
    $script:Downloads++
    return '# Mock installer'
}
function Invoke-PowerShellScript {
    param($ScriptPath)
    if (-not (Test-Path $ScriptPath)) { throw "Installer must be saved before execution." }
    $script:CliInstalled = $true
}
foreach ($Name in @('agy', 'grok')) {
    $script:CliInstalled = $false
    $script:AiInitRequired = $false
    $Before = $script:Downloads
    $DryRun = $true
    Install-NativeAiCli -CommandName $Name -InstallerUrl 'https://example.invalid/install.ps1'
    Assert-Equal $script:Downloads $Before "Missing native CLI dry-run"
    $DryRun = $false
    Install-NativeAiCli -CommandName $Name -InstallerUrl 'https://example.invalid/install.ps1'
    Assert-Equal $script:Downloads ($Before + 1) "Missing native CLI download"
    Assert-Equal $script:AiInitRequired $true "New native CLI requires links"
}

$script:InstallerPath = $null
function Invoke-PowerShellScript {
    param($ScriptPath)
    $script:InstallerPath = $ScriptPath
    throw "Mock installer failure"
}
$script:CliInstalled = $false
$script:AiInitRequired = $false
$Failed = $false
try { Install-NativeAiCli -CommandName agy -InstallerUrl 'https://example.invalid/install.ps1' }
catch { $Failed = $true }
if (-not $Failed) { throw "Native installer failure must propagate." }
if (-not $script:InstallerPath -or (Test-Path $script:InstallerPath)) {
    throw "Failed native installation must remove its temporary installer."
}
Assert-Equal $script:AiInitRequired $false "Failed installation must not mark links for refresh"

$OriginalAppData = $env:APPDATA
if (-not $env:APPDATA) { $env:APPDATA = $env:TEMP }
$script:NpmCalls = @()
$script:NpmExit = 0
function npm.cmd {
    $script:NpmCalls += ,$args
    $script:CliInstalled = $true
    $global:LASTEXITCODE = $script:NpmExit
}
try {
    $script:CliInstalled = $false
    $script:AiInitRequired = $false
    Install-PiCli
    Assert-Equal $script:AiInitRequired $true "New Pi requires links"
    $ExpectedPrefix = Join-Path $env:APPDATA 'npm'
    Assert-Equal ($script:NpmCalls[-1] -join '|') "install|--global|--prefix|$ExpectedPrefix|--ignore-scripts|@earendil-works/pi-coding-agent@latest" "Pi npm arguments"
    $Before = $script:NpmCalls.Count
    Install-PiCli
    Assert-Equal $script:NpmCalls.Count ($Before + 1) "Pi default update"
    $NoUpgrade = $true
    Install-PiCli
    Assert-Equal $script:NpmCalls.Count ($Before + 1) "Pi NoUpgrade"
    $NoUpgrade = $false
    $DryRun = $true
    Install-PiCli
    Assert-Equal $script:NpmCalls.Count ($Before + 1) "Pi dry-run"
    $DryRun = $false
    $script:NpmExit = 7
    $Failed = $false
    try { Install-PiCli }
    catch { $Failed = $true }
    if (-not $Failed) { throw "Pi npm failure must propagate." }
}
finally { $env:APPDATA = $OriginalAppData }
Write-Host "Additional AI CLI regression checks passed."
