
<# SPDX-LICENSE-IDENTIFIER: 0BSD #>

[CmdletBinding()]
Param
(
	[Parameter()]
		[ValidateNotNull()]
			$Configuration = 'release'
)

$Source = Join-Path $PSScriptRoot ../source
$Libraries = Join-Path $PSScriptRoot ../libraries
$BuildPath = Join-Path $PSScriptRoot "../build/$Configuration"
$DotNetBuildPath = Join-Path $BuildPath dotnet

New-Item -ItemType Directory -Force -Path $DotNetBuildPath > $Null

Push-Location -LiteralPath $DotNetBuildPath

try
{
	dotnet build -c $Configuration --artifacts-path . $Libraries/csharp
}
finally
{
	Pop-Location
}

