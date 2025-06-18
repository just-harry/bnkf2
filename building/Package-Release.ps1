
<# SPDX-LICENSE-IDENTIFIER: 0BSD #>

[CmdletBinding()]
Param
()

$BuildPath = Join-Path $PSScriptRoot "../build/release"
$PackagePath = Join-Path $PSScriptRoot "../build/package"

$CLIPath = Join-Path $PackagePath cli
$LibrariesPath = Join-Path $PackagePath libraries
$NET46Path = Join-Path $LibrariesPath NET46
$NET60Path = Join-Path $LibrariesPath NET6.0

Remove-Item -Force -Recurse -ErrorAction Ignore -LiteralPath $PackagePath

New-Item -ItemType Directory -Force -Path $CLIPath > $Null
New-Item -ItemType Directory -Force -Path $LibrariesPath > $Null
New-Item -ItemType Directory -Force -Path $LibrariesPath > $Null
New-Item -ItemType Directory -Force -Path $NET46Path > $Null
New-Item -ItemType Directory -Force -Path $NET60Path > $Null


Copy-Item -Force -LiteralPath $BuildPath/bnkf2.dll -Destination $CLIPath
Copy-Item -Force -LiteralPath $BuildPath/bnkf2.exe -Destination $CLIPath
Copy-Item -Force -LiteralPath $BuildPath/zlib1.dll -Destination $CLIPath

Compress-Archive -Force -CompressionLevel Optimal -Path "$([Management.Automation.WildcardPattern]::Escape($CLIPath))/*" -Destination $PackagePath/bnkf2.zip

Copy-Item -Force -LiteralPath $BuildPath/bnkf2.dll.pdb -Destination $CLIPath
Copy-Item -Force -LiteralPath $BuildPath/bnkf2.exe.pdb -Destination $CLIPath
Copy-Item -Force -LiteralPath $BuildPath/zlib1.pdb -Destination $CLIPath

Compress-Archive -Force -CompressionLevel Optimal -Path "$([Management.Automation.WildcardPattern]::Escape($CLIPath))/*" -Destination $PackagePath/bnkf2-with-debug-information.zip

Copy-Item -Force -LiteralPath $BuildPath/bnkf2.dll -Destination $LibrariesPath
Copy-Item -Force -LiteralPath $BuildPath/bnkf2.dll.pdb -Destination $LibrariesPath
Copy-Item -Force -LiteralPath $BuildPath/zlib1.dll -Destination $LibrariesPath
Copy-Item -Force -LiteralPath $BuildPath/zlib1.pdb -Destination $LibrariesPath

Copy-Item -Force -LiteralPath $BuildPath/dotnet/bin/BNKF2.NET/release_net46/BNKF2.NET.dll -Destination $NET46Path
Copy-Item -Force -LiteralPath $BuildPath/dotnet/bin/BNKF2.NET/release_net46/BNKF2.NET.pdb -Destination $NET46Path

Copy-Item -Force -LiteralPath $BuildPath/dotnet/bin/BNKF2.NET/release_net6.0/BNKF2.NET.dll -Destination $NET60Path
Copy-Item -Force -LiteralPath $BuildPath/dotnet/bin/BNKF2.NET/release_net6.0/BNKF2.NET.pdb -Destination $NET60Path
Copy-Item -Force -LiteralPath $BuildPath/dotnet/bin/BNKF2.NET/release_net6.0/BNKF2.NET.deps.json -Destination $NET60Path

Compress-Archive -Force -CompressionLevel Optimal -Path "$([Management.Automation.WildcardPattern]::Escape($LibrariesPath))/*" -Destination $PackagePath/bnkf2-libraries.zip

