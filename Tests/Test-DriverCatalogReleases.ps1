[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Expected,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Actual,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '../Scripts/Build-UnifiedDriverPackCatalog.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Unified driver catalog script has parser errors: $($parseErrors.Message -join '; ')"
}

$functionDefinitions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
foreach ($functionDefinition in $functionDefinitions) {
    . ([scriptblock]::Create($functionDefinition.Extent.Text))
}

foreach ($case in @(
        @{ Build = '26300'; Release = '26H2' }
        @{ Build = '26200'; Release = '25H2' }
        @{ Build = '26100'; Release = '24H2' }
        @{ Build = '22631'; Release = $null }
        @{ Build = '26301'; Release = $null }
        @{ Build = '28000'; Release = $null }
        @{ Build = '19045'; Release = '22H2' }
    )) {
    Assert-Equal -Expected $case.Release -Actual (Get-ReleaseIdFromBuild -Build $case.Build) -Message "Incorrect driver release for build $($case.Build)."
}

foreach ($case in @(
        @{ Text = 'Windows 11 26h2 x64'; Release = '26H2' }
        @{ Text = 'Surface_Win11_26H2.msi'; Release = '26H2' }
        @{ Text = 'Windows 11 27h1 x64'; Release = '27H1' }
        @{ Text = 'Windows 10 22H2'; Release = '22H2' }
    )) {
    Assert-Equal -Expected $case.Release -Actual (Get-ReleaseIdFromText -Text $case.Text) -Message "Incorrect driver release for '$($case.Text)'."
}

Write-Output 'Driver catalog release tests passed.'
