[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoUpgrade,
    [switch]$SkipAiInit
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bootstrap = Join-Path $ScriptDir "scripts\windows\bootstrap.ps1"

& $Bootstrap @PSBoundParameters
