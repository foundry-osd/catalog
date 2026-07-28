[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Helpers\OperatingSystemCatalog.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

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
        [string]$Message
    )

    try {
        & $Action
    }
    catch {
        return
    }

    throw "$Message Expected an exception."
}

$configPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Config\Windows11Releases.psd1'
$configuration = Import-OperatingSystemReleaseConfiguration -Path $configPath
Assert-Equal -Expected 3 -Actual $configuration.Count -Message 'Release configuration count is incorrect.'
Assert-Equal -Expected 26200 -Actual $configuration['25H2'].ExpectedBuildMajor -Message '25H2 build mapping is incorrect.'

$invalidConfigurations = @(
    @{
        'WrongKey' = [pscustomobject]@{ ReleaseId = '24H2'; SourceType = 'ArchiveOnly'; ExpectedBuildMajor = 26100 }
    },
    @(
        [pscustomobject]@{ ReleaseId = '24H2'; SourceType = 'ArchiveOnly'; ExpectedBuildMajor = 26100 },
        [pscustomobject]@{ ReleaseId = '25H2'; SourceType = 'ArchiveOnly'; ExpectedBuildMajor = 26100 }
    ),
    @([pscustomobject]@{ ReleaseId = '24H2'; SourceType = 'Unknown'; ExpectedBuildMajor = 26100 }),
    @([pscustomobject]@{ ReleaseId = '24H2'; SourceType = 'StaticCab'; ExpectedBuildMajor = 26100; CabUrl = 'http://example.test/products.cab' }),
    @([pscustomobject]@{ ReleaseId = '25H2'; SourceType = 'DynamicWindowsUpdate'; ExpectedBuildMajor = 26200; Products = ''; DeviceAttributes = '' })
)
foreach ($invalidConfiguration in $invalidConfigurations) {
    Assert-Throws -Action { Assert-OperatingSystemReleaseConfiguration -Definitions $invalidConfiguration } -Message 'Invalid configuration was accepted.'
}

$identity = Get-OperatingSystemMediaIdentity -FileName '26200.8873.260710-1234.ge_release_CLIENTCONSUMER_RET_x64FRE_en-us.esd'
Assert-Equal -Expected '26200.8873' -Actual $identity.Build -Message 'Media build is incorrect.'
Assert-Equal -Expected '2026-07-10' -Actual $identity.MediaDate.ToString('yyyy-MM-dd') -Message 'Media date is incorrect.'
Assert-Throws -Action { Get-OperatingSystemMediaIdentity -FileName '26200.8873.261332-1234.invalid.esd' } -Message 'Invalid media date was accepted.'
Assert-Throws -Action { Get-OperatingSystemMediaIdentity -FileName '26200.8873-without-date.esd' } -Message 'Missing media date was accepted.'

$snapshot = Get-OperatingSystemSnapshotDefinition -FileName 'Win11_25H2_26200.8873_20260710.xml'
Assert-Equal -Expected '25H2' -Actual $snapshot.ReleaseId -Message 'Snapshot release is incorrect.'
Assert-Equal -Expected 8873 -Actual $snapshot.BuildUbr -Message 'Snapshot UBR is incorrect.'
Assert-Throws -Action { Get-OperatingSystemSnapshotDefinition -FileName 'Win11_25H2_26200.xml' } -Message 'Legacy snapshot name was accepted.'

$snapshots = @(
    [pscustomobject]@{ Path = '23-old.xml'; ReleaseId = '23H2'; MediaDate = [datetime]'2023-12-04'; BuildMajor = 22631; BuildUbr = 2861 },
    [pscustomobject]@{ Path = '25-old.xml'; ReleaseId = '25H2'; MediaDate = [datetime]'2024-01-10'; BuildMajor = 26200; BuildUbr = 100 },
    [pscustomobject]@{ Path = '25-newest-old.xml'; ReleaseId = '25H2'; MediaDate = [datetime]'2024-02-10'; BuildMajor = 26200; BuildUbr = 200 },
    [pscustomobject]@{ Path = '25-aug-a.xml'; ReleaseId = '25H2'; MediaDate = [datetime]'2025-08-05'; BuildMajor = 26200; BuildUbr = 300 },
    [pscustomobject]@{ Path = '25-aug-b.xml'; ReleaseId = '25H2'; MediaDate = [datetime]'2025-08-20'; BuildMajor = 26200; BuildUbr = 301 },
    [pscustomobject]@{ Path = '25-jul.xml'; ReleaseId = '25H2'; MediaDate = [datetime]'2026-07-10'; BuildMajor = 26200; BuildUbr = 8873 }
)
$retentionPlan = Get-OperatingSystemRetentionPlan -Snapshots $snapshots -TargetReleases @('25H2') -ReferenceDateUtc ([datetime]'2026-07-28') -RetentionMonths 12
Assert-Equal -Expected 4 -Actual $retentionPlan.Keep.Count -Message 'Retention keep count is incorrect.'
Assert-Equal -Expected 2 -Actual $retentionPlan.Delete.Count -Message 'Retention delete count is incorrect.'
Assert-Equal -Expected 1 -Actual @($retentionPlan.Delete | Where-Object Path -eq '25-old.xml').Count -Message 'Oldest targeted snapshot was not deleted.'
Assert-Equal -Expected 0 -Actual @($retentionPlan.Delete | Where-Object ReleaseId -eq '23H2').Count -Message 'Untargeted snapshot was deleted.'

$oldOnlyPlan = Get-OperatingSystemRetentionPlan -Snapshots $snapshots[1..2] -TargetReleases @('25H2') -ReferenceDateUtc ([datetime]'2026-07-28') -RetentionMonths 12
Assert-Equal -Expected '25-newest-old.xml' -Actual $oldOnlyPlan.Keep[0].Path -Message 'Newest old snapshot was not preserved.'

$tempDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('foundry-os-history-test-' + [guid]::NewGuid())
try {
    $null = New-Item -Path $tempDirectory -ItemType Directory -Force
    $stagedPath = Join-Path -Path $tempDirectory -ChildPath 'staged.xml'
    $destinationDirectory = Join-Path -Path $tempDirectory -ChildPath 'published'
    [System.IO.File]::WriteAllText($stagedPath, '<Products />')

    $firstPath = Publish-OperatingSystemSnapshot -StagedPath $stagedPath -DestinationDirectory $destinationDirectory -FileName 'Win11_25H2_26200.8873_20260710.xml'
    $firstHash = (Get-FileHash -LiteralPath $firstPath -Algorithm SHA256).Hash
    $firstWriteTime = (Get-Item -LiteralPath $firstPath).LastWriteTimeUtc

    Start-Sleep -Milliseconds 20
    $secondPath = Publish-OperatingSystemSnapshot -StagedPath $stagedPath -DestinationDirectory $destinationDirectory -FileName 'Win11_25H2_26200.8873_20260710.xml'
    Assert-Equal -Expected $firstHash -Actual (Get-FileHash -LiteralPath $secondPath -Algorithm SHA256).Hash -Message 'Idempotent publish changed the content.'
    Assert-Equal -Expected $firstWriteTime -Actual (Get-Item -LiteralPath $secondPath).LastWriteTimeUtc -Message 'Idempotent publish rewrote the snapshot.'

    [System.IO.File]::WriteAllText($stagedPath, '<Different />')
    Assert-Throws -Action {
        Publish-OperatingSystemSnapshot -StagedPath $stagedPath -DestinationDirectory $destinationDirectory -FileName 'Win11_25H2_26200.8873_20260710.xml'
    } -Message 'Snapshot identity collision was accepted.'
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}

Write-Output 'Operating system catalog history tests passed.'
