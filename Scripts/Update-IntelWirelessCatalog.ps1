#region Parameters
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WinPEOutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '..\Cache\WinPE\Intel'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CatalogPageUri = 'https://www.intel.com/content/www/us/en/download/18231/intel-proset-wireless-software-and-wi-fi-drivers-for-it-administrators.html',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$FallbackVersion = '24.30.1',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$FallbackFileName = 'WiFi-24.30.1-Driver64-Win10-Win11.zip',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$FallbackReleaseDate = '2026-03-24',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$FallbackSha256 = 'A09AF2CC6E6305E395A553C4CDE4264F554DC7DF29EEF34DBBDE53025464EF8E',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$FallbackDownloadUrl = 'https://downloadmirror.intel.com/915923/WiFi-24.30.1-Driver64-Win10-Win11.zip',

    [Parameter()]
    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
#endregion Parameters

#region Import Helpers

$helpersPath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath @('Helpers', 'FoundryHelpers.psm1')
if (Test-Path -Path $helpersPath) {
    Import-Module -Name $helpersPath -Force -ErrorAction Stop
}
else {
    throw "Helpers module not found at: $helpersPath"
}

#endregion Import Helpers

#region Functions

function Invoke-IntelCatalogRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $headers = @{
        'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) catalog/1.0'
        'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        'Accept-Language' = 'en-US,en;q=0.9'
    }

    return Invoke-WebRequest -Uri $Uri -Headers $headers -TimeoutSec $TimeoutSeconds -ErrorAction Stop
}

function Get-RegexValueOrNull {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return $null
}

function ConvertTo-IsoDateOrFallback {
    param(
        [Parameter()]
        [AllowNull()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Fallback
    )

    if (-not $Value) {
        return $Fallback
    }

    [datetime]$parsed = [datetime]::MinValue
    if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) {
        return $parsed.ToString('yyyy-MM-dd')
    }

    return $Fallback
}

function Get-IntelWirelessMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CatalogPageUri,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [hashtable]$Fallback,

        [Parameter()]
        [AllowNull()]
        [hashtable]$Existing
    )

    try {
        $response = Invoke-IntelCatalogRequest -Uri $CatalogPageUri -TimeoutSeconds $TimeoutSeconds
        $content = [string]$response.Content

        $version = Get-RegexValueOrNull -Text $content -Pattern 'Version\s+([0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)'
        $fileName = Get-RegexValueOrNull -Text $content -Pattern '(WiFi-[A-Za-z0-9._\-]+\.zip)'
        $releaseDate = Get-RegexValueOrNull -Text $content -Pattern 'Date\s+([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})'
        $sha256 = Get-RegexValueOrNull -Text $content -Pattern 'SHA256:\s*([A-F0-9]{64})'
        $downloadUrl = Get-RegexValueOrNull -Text $content -Pattern '(https://downloadmirror\.intel\.com/[0-9]+/[A-Za-z0-9._\-]+\.zip)'

        if (-not $downloadUrl -and $fileName) {
            $mirrorId = Get-RegexValueOrNull -Text $content -Pattern 'downloadmirror\.intel\.com/([0-9]+)/'
            if ($mirrorId) {
                $downloadUrl = "https://downloadmirror.intel.com/$mirrorId/$fileName"
            }
        }

        if (-not $downloadUrl) {
            throw "The Intel page did not expose a direct ZIP download URL."
        }

        return [ordered]@{
            Version = if ($version) { $version } else { $Fallback.Version }
            FileName = if ($fileName) { $fileName } else { $Fallback.FileName }
            ReleaseDate = ConvertTo-IsoDateOrFallback -Value $releaseDate -Fallback $Fallback.ReleaseDate
            Sha256 = if ($sha256) { $sha256.ToUpperInvariant() } else { $Fallback.Sha256 }
            DownloadUrl = $downloadUrl
            UsedFallback = $false
            UsedExisting = $false
        }
    }
    catch {
        if ($Existing) {
            Write-Warning ("Failed to refresh the Intel wireless package metadata from '{0}'. Reusing the previous known-good entry. {1}" -f $CatalogPageUri, $_.Exception.Message)
            return [ordered]@{
                Version = $Existing.Version
                FileName = $Existing.FileName
                ReleaseDate = $Existing.ReleaseDate
                Sha256 = $Existing.Sha256
                DownloadUrl = $Existing.DownloadUrl
                UsedFallback = $false
                UsedExisting = $true
            }
        }

        Write-Warning ("Failed to refresh the Intel wireless package metadata from '{0}'. Using fallback metadata. {1}" -f $CatalogPageUri, $_.Exception.Message)
        return [ordered]@{
            Version = $Fallback.Version
            FileName = $Fallback.FileName
            ReleaseDate = $Fallback.ReleaseDate
            Sha256 = $Fallback.Sha256
            DownloadUrl = $Fallback.DownloadUrl
            UsedFallback = $true
            UsedExisting = $false
        }
    }
}

function Get-ExistingIntelCatalogEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        return $null
    }

    [xml]$xml = Get-Content -Path $Path -Raw
    $item = $xml.IntelCatalog.Items.Item
    if (-not $item) {
        return $null
    }

    return [ordered]@{
        Version = if ([string]$item.version) { [string]$item.version } else { $null }
        FileName = if ([string]$item.fileName) { [string]$item.fileName } else { $null }
        ReleaseDate = if ([string]$item.releaseDate) { [string]$item.releaseDate } else { $null }
        Sha256 = if ([string]$item.hashSHA256) { [string]$item.hashSHA256 } else { $null }
        DownloadUrl = if ([string]$item.downloadUrl) { [string]$item.downloadUrl } else { $null }
    }
}

function Write-IntelCatalogXml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$CatalogPageUri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Metadata
    )

    $generatedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $writer = New-CatalogXmlWriter -Path $Path

    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('IntelCatalog')
        $writer.WriteAttributeString('generatedAtUtc', $generatedAtUtc)
        $writer.WriteAttributeString('itemCount', '1')

        $writer.WriteStartElement('Metadata')
        $writer.WriteAttributeString('catalogUrl', $CatalogPageUri)
        $writer.WriteAttributeString('description', 'Intel wireless driver-only ZIP catalog for WinRE Wi-Fi supplementation.')
        $writer.WriteAttributeString('usedFallback', [string]$Metadata.UsedFallback.ToString().ToLowerInvariant())
        $writer.WriteAttributeString('usedExisting', [string]$Metadata.UsedExisting.ToString().ToLowerInvariant())
        $writer.WriteEndElement()

        $writer.WriteStartElement('Items')
        $writer.WriteStartElement('Item')

        $elements = [ordered]@{
            id = 'intel-wireless-winre-x64'
            packageId = 'intel-wireless-winre-x64'
            name = 'Intel Wireless Wi-Fi Drivers for IT Administrators'
            version = $Metadata.Version
            fileName = $Metadata.FileName
            downloadUrl = $Metadata.DownloadUrl
            format = 'zip'
            packageRole = 'WifiSupplement'
            driverFamily = 'IntelWireless'
            releaseDate = $Metadata.ReleaseDate
            osName = 'WinPE'
            osReleaseId = '11'
            osArchitecture = 'x64'
            hashSHA256 = $Metadata.Sha256
        }

        foreach ($element in $elements.GetEnumerator()) {
            $writer.WriteElementString($element.Key, [string]$element.Value)
        }

        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        $writer.Dispose()
    }
}

#endregion Functions

#region Main Execution

$outputPath = Join-Path -Path $WinPEOutputDirectory -ChildPath 'WinPE_Intel.xml'
if (-not (Test-Path -Path $WinPEOutputDirectory)) {
    $null = New-Item -Path $WinPEOutputDirectory -ItemType Directory -Force
}

$fallback = @{
    Version = $FallbackVersion
    FileName = $FallbackFileName
    ReleaseDate = $FallbackReleaseDate
    Sha256 = $FallbackSha256
    DownloadUrl = $FallbackDownloadUrl
}

$existing = Get-ExistingIntelCatalogEntry -Path $outputPath
$metadata = Get-IntelWirelessMetadata -CatalogPageUri $CatalogPageUri -TimeoutSeconds $TimeoutSeconds -Fallback $fallback -Existing $existing
Write-IntelCatalogXml -Path $outputPath -CatalogPageUri $CatalogPageUri -Metadata $metadata

[pscustomobject]@{
    OutputPath = $outputPath
    Version = $metadata.Version
    FileName = $metadata.FileName
    ReleaseDate = $metadata.ReleaseDate
    Sha256 = $metadata.Sha256
    DownloadUrl = $metadata.DownloadUrl
    UsedFallback = $metadata.UsedFallback
    UsedExisting = $metadata.UsedExisting
}

#endregion Main Execution
