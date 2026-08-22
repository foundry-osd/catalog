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

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedMessage,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        & $Action
    }
    catch {
        Assert-Equal -Expected $ExpectedMessage -Actual $_.Exception.Message -Message $Message
        return
    }

    throw "$Message Expected an exception."
}

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Scripts\Update-IntelWirelessCatalog.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Intel wireless catalog script has parser errors: $($parseErrors.Message -join '; ')"
}

$functionDefinitions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
foreach ($functionDefinition in $functionDefinitions) {
    . ([scriptblock]::Create($functionDefinition.Extent.Text))
}

$tempDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('foundry-intel-wireless-test-' + [guid]::NewGuid())
try {
    $null = New-Item -Path $tempDirectory -ItemType Directory -Force
    $catalogPath = Join-Path -Path $tempDirectory -ChildPath 'WinPE_Intel.xml'
    [System.IO.File]::WriteAllText($catalogPath, @'
<?xml version="1.0" encoding="utf-8"?>
<IntelCatalog generatedAtUtc="2026-08-21T03:39:20Z" itemCount="1">
  <Metadata catalogUrl="https://www.catalog.update.microsoft.com/" description="test" source="MicrosoftUpdateCatalog" updateId="34cf8ffa-450f-4dcd-bc20-35590c6d5e17" query="PCI\VEN_8086&amp;DEV_7E40" />
  <Items>
    <Item>
      <id>intel-wireless-winre-x64</id>
      <packageId>intel-wireless-winre-x64</packageId>
      <name>Intel Wireless Wi-Fi Drivers from Microsoft Update Catalog</name>
      <version>24.40.0.4</version>
      <fileName>intel-wireless.cab</fileName>
      <downloadUrl>https://download.windowsupdate.com/intel-wireless.cab</downloadUrl>
      <format>cab</format>
      <packageRole>WifiSupplement</packageRole>
      <driverFamily>IntelWireless</driverFamily>
      <releaseDate>2026-04-12</releaseDate>
      <osName>WinPE</osName>
      <osReleaseId>11</osReleaseId>
      <osArchitecture>x64</osArchitecture>
      <hashSHA256>4365da6d3ad51e942d5c091372536d2163dc3ca17fa5e389feedcb29ad5e339f</hashSHA256>
    </Item>
  </Items>
</IntelCatalog>
'@)

    $existingMetadata = Get-ExistingIntelCatalogMetadata -Path $catalogPath
    Assert-Equal -Expected '34cf8ffa-450f-4dcd-bc20-35590c6d5e17' -Actual $existingMetadata.UpdateId -Message 'Existing update ID was not preserved.'
    Assert-Equal -Expected 'PCI\VEN_8086&DEV_7E40' -Actual $existingMetadata.Query -Message 'Existing hardware ID query was not preserved.'
    Assert-Equal -Expected '24.40.0.4' -Actual $existingMetadata.Version -Message 'Existing version was not preserved.'

    function Get-IntelWirelessMicrosoftUpdateMetadata {
        throw 'Simulated Microsoft Update Catalog failure.'
    }

    $fallbackResult = Get-IntelWirelessMetadataWithFallback `
        -HardwareIds @('PCI\VEN_8086&DEV_7E40') `
        -TimeoutSeconds 45 `
        -ExistingMetadata $existingMetadata

    Assert-Equal -Expected $true -Actual $fallbackResult.UsedExisting -Message 'Existing metadata was not selected after refresh failure.'
    Assert-Equal -Expected '24.40.0.4' -Actual $fallbackResult.Metadata.Version -Message 'Fallback metadata version is incorrect.'
    Assert-Equal -Expected '34cf8ffa-450f-4dcd-bc20-35590c6d5e17' -Actual $fallbackResult.Metadata.UpdateId -Message 'Fallback metadata update ID is incorrect.'

    Assert-Throws `
        -Action {
            Get-IntelWirelessMetadataWithFallback `
                -HardwareIds @('PCI\VEN_8086&DEV_7E40') `
                -TimeoutSeconds 45 `
                -ExistingMetadata $null
        } `
        -ExpectedMessage 'Simulated Microsoft Update Catalog failure.' `
        -Message 'Refresh failure without existing metadata was suppressed.'
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}

Write-Output 'Intel wireless catalog fallback tests passed.'
