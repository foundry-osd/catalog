@{
    Releases = @{
        '24H2' = @{
            ReleaseId = '24H2'
            SourceType = 'StaticCab'
            CabUrl = 'https://download.microsoft.com/download/8e0c23e7-ddc2-45c4-b7e1-85a808b408ee/Products-Win11-24H2-6B.cab'
            ExpectedBuildMajor = 26100
        }
        '25H2' = @{
            ReleaseId = '25H2'
            SourceType = 'ArchiveOnly'
            ExpectedBuildMajor = 26200
        }
        '26H2' = @{
            ReleaseId = '26H2'
            SourceType = 'DynamicWindowsUpdate'
            Products = 'PN=Windows.Products.Cab.amd64&V=0.0.0.0'
            DeviceAttributes = 'DUScan=1;OSVersion=10.0.26100.1'
            ExpectedBuildMajor = 26300
        }
    }
}
