Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-OperatingSystemReleaseConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Definitions
    )

    $entries = if ($Definitions -is [System.Collections.IDictionary]) {
        foreach ($key in $Definitions.Keys) {
            [pscustomobject]@{
                Key = [string]$key
                Definition = $Definitions[$key]
            }
        }
    }
    else {
        foreach ($definition in @($Definitions)) {
            [pscustomobject]@{
                Key = [string]$definition.ReleaseId
                Definition = $definition
            }
        }
    }

    if (@($entries).Count -lt 1) {
        throw 'At least one Windows release must be configured.'
    }

    $releaseIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $buildMajors = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($entry in $entries) {
        $definition = $entry.Definition
        $releaseId = [string]$definition.ReleaseId
        if ([string]::IsNullOrWhiteSpace($releaseId)) {
            throw 'Every Windows release must define ReleaseId.'
        }
        if ($entry.Key -ne $releaseId) {
            throw "Windows release key '$($entry.Key)' does not match ReleaseId '$releaseId'."
        }
        if (-not $releaseIds.Add($releaseId)) {
            throw "Duplicate Windows release: $releaseId"
        }

        [int]$buildMajor = $definition.ExpectedBuildMajor
        if ($buildMajor -lt 1 -or -not $buildMajors.Add($buildMajor)) {
            throw "ExpectedBuildMajor must be positive and unique for Windows release $releaseId."
        }

        $sourceType = [string]$definition.SourceType
        if ($sourceType -notin @('StaticCab', 'DynamicWindowsUpdate', 'ArchiveOnly')) {
            throw "Unsupported source type '$sourceType' for Windows release $releaseId."
        }

        if ($sourceType -eq 'StaticCab') {
            $cabUrl = [string]$definition.CabUrl
            if (-not $cabUrl.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "StaticCab release $releaseId must define an HTTPS CabUrl."
            }
        }
        elseif ($sourceType -eq 'DynamicWindowsUpdate') {
            if ([string]::IsNullOrWhiteSpace([string]$definition.Products) -or
                [string]::IsNullOrWhiteSpace([string]$definition.DeviceAttributes)) {
                throw "DynamicWindowsUpdate release $releaseId must define Products and DeviceAttributes."
            }
        }
    }
}

function Import-OperatingSystemReleaseConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $configuration = Import-PowerShellDataFile -Path $Path
    if (-not $configuration.ContainsKey('Releases')) {
        throw "Release configuration '$Path' does not define Releases."
    }

    Assert-OperatingSystemReleaseConfiguration -Definitions $configuration.Releases

    $result = @{}
    foreach ($releaseId in $configuration.Releases.Keys) {
        $result[[string]$releaseId] = [pscustomobject]$configuration.Releases[$releaseId]
    }

    return $result
}

function Get-OperatingSystemMediaIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
    )

    $match = [regex]::Match(
        $FileName,
        '^(?<buildMajor>\d{5})\.(?<buildUbr>\d+)\.(?<stamp>\d{6})-\d{4}\..+\.esd$',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $match.Success) {
        throw "ESD file name '$FileName' does not contain a supported build and media date."
    }

    $stamp = $match.Groups['stamp'].Value
    $year = 2000 + [int]$stamp.Substring(0, 2)
    $month = [int]$stamp.Substring(2, 2)
    $day = [int]$stamp.Substring(4, 2)
    try {
        $mediaDate = [datetime]::new($year, $month, $day, 0, 0, 0, [System.DateTimeKind]::Utc)
    }
    catch {
        throw "ESD file name '$FileName' contains an invalid media date."
    }

    $buildMajor = [int]$match.Groups['buildMajor'].Value
    $buildUbr = [int]$match.Groups['buildUbr'].Value
    return [pscustomobject]([ordered]@{
            Build = "$buildMajor.$buildUbr"
            BuildMajor = $buildMajor
            BuildUbr = $buildUbr
            MediaDate = $mediaDate
        })
}

function Get-OperatingSystemSnapshotDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $match = [regex]::Match(
        $baseName,
        '^Win(?<windowsMajor>\d+)_(?<releaseId>\d{2}H\d)_(?<buildMajor>\d{5})\.(?<buildUbr>\d+)_(?<mediaDate>\d{8})$',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $match.Success) {
        throw "Source XML name '$FileName' does not use the immutable snapshot format."
    }

    $mediaDateText = $match.Groups['mediaDate'].Value
    try {
        $mediaDate = [datetime]::new(
            [int]$mediaDateText.Substring(0, 4),
            [int]$mediaDateText.Substring(4, 2),
            [int]$mediaDateText.Substring(6, 2),
            0,
            0,
            0,
            [System.DateTimeKind]::Utc
        )
    }
    catch {
        throw "Source XML name '$FileName' contains an invalid media date."
    }

    $buildMajor = [int]$match.Groups['buildMajor'].Value
    $buildUbr = [int]$match.Groups['buildUbr'].Value
    return [pscustomobject]([ordered]@{
            Id = $baseName
            WindowsMajor = $match.Groups['windowsMajor'].Value
            ReleaseId = $match.Groups['releaseId'].Value.ToUpperInvariant()
            Build = "$buildMajor.$buildUbr"
            BuildMajor = $buildMajor
            BuildUbr = $buildUbr
            MediaDate = $mediaDate
        })
}

function Get-OperatingSystemRetentionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Snapshots,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string[]]$TargetReleases,

        [Parameter()]
        [datetime]$ReferenceDateUtc = [datetime]::UtcNow,

        [Parameter()]
        [ValidateRange(1, 120)]
        [int]$RetentionMonths = 12
    )

    $cutoff = [datetime]::new(
        $ReferenceDateUtc.ToUniversalTime().Year,
        $ReferenceDateUtc.ToUniversalTime().Month,
        1,
        0,
        0,
        0,
        [System.DateTimeKind]::Utc
    ).AddMonths(-($RetentionMonths - 1))
    $targets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($releaseId in $TargetReleases) {
        if (-not [string]::IsNullOrWhiteSpace($releaseId)) {
            $null = $targets.Add($releaseId.Trim())
        }
    }

    $keepPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($snapshot in $Snapshots) {
        if (-not $targets.Contains([string]$snapshot.ReleaseId) -or $snapshot.MediaDate -ge $cutoff) {
            $null = $keepPaths.Add([string]$snapshot.Path)
        }
    }

    foreach ($releaseId in $targets) {
        $newest = $Snapshots |
            Where-Object { $_.ReleaseId -eq $releaseId } |
            Sort-Object -Descending -Property MediaDate, BuildMajor, BuildUbr |
            Select-Object -First 1
        if ($newest) {
            $null = $keepPaths.Add([string]$newest.Path)
        }
    }

    return [pscustomobject]@{
        Cutoff = $cutoff
        Keep = @($Snapshots | Where-Object { $keepPaths.Contains([string]$_.Path) })
        Delete = @($Snapshots | Where-Object { -not $keepPaths.Contains([string]$_.Path) })
    }
}

function Publish-OperatingSystemSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StagedPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
    )

    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        $null = New-Item -Path $DestinationDirectory -ItemType Directory -Force
    }

    $destinationPath = Join-Path -Path $DestinationDirectory -ChildPath $FileName
    if (Test-Path -LiteralPath $destinationPath) {
        $stagedHash = (Get-FileHash -LiteralPath $StagedPath -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
        if ($stagedHash -ne $destinationHash) {
            throw "Snapshot '$FileName' already exists with different content."
        }

        return (Get-Item -LiteralPath $destinationPath).FullName
    }

    Copy-Item -LiteralPath $StagedPath -Destination $destinationPath -ErrorAction Stop
    return (Get-Item -LiteralPath $destinationPath).FullName
}

Export-ModuleMember -Function @(
    'Assert-OperatingSystemReleaseConfiguration',
    'Import-OperatingSystemReleaseConfiguration',
    'Get-OperatingSystemMediaIdentity',
    'Get-OperatingSystemSnapshotDefinition',
    'Get-OperatingSystemRetentionPlan',
    'Publish-OperatingSystemSnapshot'
)
