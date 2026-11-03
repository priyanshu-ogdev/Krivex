<#
.SYNOPSIS
    Convenience shortcut to launch Krivex Visual Polish Tier training.
#>
param(
    [ValidateSet("a6000-max", "standard", "qdora-12gb")]
    [string]$Profile = "a6000-max",
    [switch]$Interactive,
    [switch]$DryRun,
    [switch]$ForcePrep
)

$Script = Join-Path $PSScriptRoot "scripts\training\run_polish_training.ps1"
& $Script -Profile $Profile -Interactive:$Interactive -DryRun:$DryRun -ForcePrep:$ForcePrep

