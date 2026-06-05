#region Parameters
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WinPEOutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '..\Cache\WinPE\Intel'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$HardwareIds = @(
        'PCI\VEN_8086&DEV_272B',
        'PCI\VEN_8086&DEV_7E40',
        'PCI\VEN_8086&DEV_2725'
    ),

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

#region Constants

$catalogSearchBaseUri = 'https://www.catalog.update.microsoft.com/Search.aspx?q='
$catalogDownloadDialogUri = 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx'

#endregion Constants

#region Functions

function Invoke-MicrosoftUpdateCatalogGet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $headers = @{
        'User-Agent'      = 'FoundryCatalog/1.0'
        'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        'Accept-Language' = 'en-US,en;q=0.9'
        'Cache-Control'   = 'no-cache'
    }

    return Invoke-WebRequest -Uri $Uri -Headers $headers -TimeoutSec $TimeoutSeconds -ErrorAction Stop
}

function Invoke-MicrosoftUpdateCatalogPost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Body,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $headers = @{
        'User-Agent'      = 'FoundryCatalog/1.0'
        'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        'Accept-Language' = 'en-US,en;q=0.9'
        'Cache-Control'   = 'no-cache'
    }

    return Invoke-WebRequest -Uri $Uri -Method Post -Headers $headers -Body $Body -TimeoutSec $TimeoutSeconds -ErrorAction Stop
}

function ConvertFrom-HtmlText {
    param(
        [Parameter()]
        [AllowNull()]
        [string]$Value
    )

    if (-not $Value) {
        return $null
    }

    $withoutTags = [regex]::Replace($Value, '<[^>]+>', '|')
    $decoded = [System.Net.WebUtility]::HtmlDecode($withoutTags)
    $normalized = [regex]::Replace($decoded, '\|+', '|')
    return $normalized.Trim('|', ' ', "`r", "`n", "`t")
}

function ConvertTo-IsoDateOrNull {
    param(
        [Parameter()]
        [AllowNull()]
        [string]$Value
    )

    if (-not $Value) {
        return $null
    }

    [datetime]$parsed = [datetime]::MinValue
    if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) {
        return $parsed.ToString('yyyy-MM-dd')
    }

    return $null
}

function ConvertTo-VersionOrNull {
    param(
        [Parameter()]
        [AllowNull()]
        [string]$Value
    )

    if (-not $Value) {
        return $null
    }

    try {
        return [version]$Value
    }
    catch {
        return $null
    }
}

function ConvertFrom-Base64Hash {
    param(
        [Parameter()]
        [AllowNull()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Algorithm
    )

    if (-not $Value) {
        return $null
    }

    try {
        return [Convert]::ToHexString([Convert]::FromBase64String($Value)).ToLowerInvariant()
    }
    catch {
        throw "Microsoft Update Catalog returned an invalid $Algorithm hash."
    }
}

function Get-MicrosoftUpdateVersionFromTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $match = [regex]::Match($Title, '\(([0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)\)')
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value
}

function Get-WindowsProductRank {
    param(
        [Parameter()]
        [AllowNull()]
        [string]$Products
    )

    if (-not $Products) {
        return 0
    }

    if ($Products -match 'Windows 11 Client.*25H2') {
        return 50
    }

    if ($Products -match 'Windows 11 Client.*24H2') {
        return 45
    }

    if ($Products -match 'Windows 11 Client.*22H2') {
        return 40
    }

    if ($Products -match 'Windows 11 Client') {
        return 35
    }

    if ($Products -match 'Windows 10') {
        return 20
    }

    return 0
}

function Get-CatalogRowCells {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RowHtml
    )

    return [regex]::Matches($RowHtml, '<td\b[^>]*>(.*?)</td>', [System.Text.RegularExpressions.RegexOptions]::Singleline) |
        ForEach-Object { ConvertFrom-HtmlText -Value $_.Groups[1].Value }
}

function Get-MicrosoftUpdateCatalogSearchResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $searchUri = $catalogSearchBaseUri + [uri]::EscapeDataString($Query)
    $response = Invoke-MicrosoftUpdateCatalogGet -Uri $searchUri -TimeoutSeconds $TimeoutSeconds
    $html = [string]$response.Content

    if ($html -match 'ctl00_catalogBody_noResultText') {
        return @()
    }

    $rows = [regex]::Matches($html, '<tr\b[^>]*>.*?</tr>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $results = foreach ($row in $rows) {
        $rowHtml = $row.Value
        if ($rowHtml -match 'id="headerRow"') {
            continue
        }

        $idMatch = [regex]::Match($rowHtml, 'id="(?<id>[0-9a-fA-F-]{36})"')
        if (-not $idMatch.Success) {
            continue
        }

        $cells = @(Get-CatalogRowCells -RowHtml $rowHtml)
        if ($cells.Count -lt 7) {
            continue
        }

        $title = [string]$cells[1]
        $version = Get-MicrosoftUpdateVersionFromTitle -Title $title
        if (-not $version) {
            continue
        }

        [pscustomobject]@{
            UpdateId = $idMatch.Groups['id'].Value
            Title = $title
            Products = [string]$cells[2]
            Classification = [string]$cells[3]
            LastUpdated = ConvertTo-IsoDateOrNull -Value ([string]$cells[4])
            Version = $version
            VersionObject = ConvertTo-VersionOrNull -Value $version
            Size = [string]$cells[6]
            ProductRank = Get-WindowsProductRank -Products ([string]$cells[2])
            Query = $Query
        }
    }

    return @($results)
}

function Get-MicrosoftUpdateCatalogDownloads {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UpdateId,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $payload = '[{"size":0,"updateID":"' + $UpdateId + '","uidInfo":"' + $UpdateId + '"}]'
    $response = Invoke-MicrosoftUpdateCatalogPost `
        -Uri $catalogDownloadDialogUri `
        -Body @{ updateIDs = $payload } `
        -TimeoutSeconds $TimeoutSeconds

    $html = [string]$response.Content
    $regex = [regex]::new(
        "downloadInformation\[\d+\]\.files\[(?<index>\d+)\]\.(?<name>[A-Za-z0-9_]+)\s*=\s*'(?<value>(?:\\'|[^'])*)'",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $files = @{}
    foreach ($match in $regex.Matches($html)) {
        $index = [int]$match.Groups['index'].Value
        if (-not $files.ContainsKey($index)) {
            $files[$index] = @{}
        }

        $value = $match.Groups['value'].Value.Replace("\'", "'").Replace("\\", "\")
        $files[$index][$match.Groups['name'].Value] = $value
    }

    return @(
        foreach ($index in ($files.Keys | Sort-Object)) {
            $file = $files[$index]
            $downloadUrl = [string]$file.url
            if (-not $downloadUrl) {
                continue
            }

            [pscustomobject]@{
                FileName = [string]$file.fileName
                DownloadUrl = $downloadUrl.Replace('www.download.windowsupdate', 'download.windowsupdate', [System.StringComparison]::OrdinalIgnoreCase)
                Sha1 = ConvertFrom-Base64Hash -Value ([string]$file.digest) -Algorithm 'SHA1'
                Sha256 = ConvertFrom-Base64Hash -Value ([string]$file.sha256) -Algorithm 'SHA256'
                Architectures = [string]$file.architectures
                Languages = [string]$file.languages
            }
        }
    )
}

function Get-IntelWirelessMicrosoftUpdateMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$HardwareIds,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $allResults = foreach ($hardwareId in $HardwareIds) {
        Get-MicrosoftUpdateCatalogSearchResults -Query $hardwareId -TimeoutSeconds $TimeoutSeconds
    }

    $candidates = @(
        $allResults |
            Where-Object {
                $_.VersionObject -and
                $_.Title -match '^Intel net Driver Update' -and
                $_.Classification -match 'Drivers \(Networking\)' -and
                $_.Products -match 'Windows 11 Client'
            } |
            Sort-Object `
                @{ Expression = { $_.VersionObject }; Descending = $true },
                @{ Expression = { if ($_.LastUpdated) { [datetime]$_.LastUpdated } else { [datetime]::MinValue } }; Descending = $true },
                @{ Expression = { $_.ProductRank }; Descending = $true },
                @{ Expression = { $_.UpdateId }; Descending = $false }
    )

    if ($candidates.Count -eq 0) {
        throw "Microsoft Update Catalog did not return any Windows 11 Intel networking driver updates for the configured hardware IDs."
    }

    foreach ($candidate in $candidates) {
        $downloads = @(Get-MicrosoftUpdateCatalogDownloads -UpdateId $candidate.UpdateId -TimeoutSeconds $TimeoutSeconds)
        $cab = $downloads |
            Where-Object { $_.DownloadUrl -match '\.cab($|\?)' -and $_.Sha256 } |
            Select-Object -First 1

        if (-not $cab) {
            continue
        }

        return [ordered]@{
            Version = $candidate.Version
            FileName = if ($cab.FileName) { $cab.FileName } else { Split-Path -Path ([uri]$cab.DownloadUrl).LocalPath -Leaf }
            ReleaseDate = $candidate.LastUpdated
            Sha256 = $cab.Sha256
            DownloadUrl = $cab.DownloadUrl
            UpdateId = $candidate.UpdateId
            Query = $candidate.Query
        }
    }

    throw "Microsoft Update Catalog returned Intel networking updates, but none exposed a CAB download with a SHA256 hash."
}

function Write-IntelCatalogXml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

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
        $writer.WriteAttributeString('catalogUrl', 'https://www.catalog.update.microsoft.com/')
        $writer.WriteAttributeString('description', 'Intel wireless driver CAB catalog from Microsoft Update Catalog for WinRE Wi-Fi supplementation.')
        $writer.WriteAttributeString('source', 'MicrosoftUpdateCatalog')
        $writer.WriteAttributeString('updateId', [string]$Metadata.UpdateId)
        $writer.WriteAttributeString('query', [string]$Metadata.Query)
        $writer.WriteEndElement()

        $writer.WriteStartElement('Items')
        $writer.WriteStartElement('Item')

        $elements = [ordered]@{
            id = 'intel-wireless-winre-x64'
            packageId = 'intel-wireless-winre-x64'
            name = 'Intel Wireless Wi-Fi Drivers from Microsoft Update Catalog'
            version = $Metadata.Version
            fileName = $Metadata.FileName
            downloadUrl = $Metadata.DownloadUrl
            format = 'cab'
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

$metadata = Get-IntelWirelessMicrosoftUpdateMetadata -HardwareIds $HardwareIds -TimeoutSeconds $TimeoutSeconds
Write-IntelCatalogXml -Path $outputPath -Metadata $metadata

[pscustomobject]@{
    OutputPath = $outputPath
    Version = $metadata.Version
    FileName = $metadata.FileName
    ReleaseDate = $metadata.ReleaseDate
    Sha256 = $metadata.Sha256
    DownloadUrl = $metadata.DownloadUrl
    Source = 'MicrosoftUpdateCatalog'
    UpdateId = $metadata.UpdateId
    Query = $metadata.Query
}

#endregion Main Execution
