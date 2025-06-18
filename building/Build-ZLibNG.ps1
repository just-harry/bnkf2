
<# SPDX-LICENSE-IDENTIFIER: 0BSD #>

[CmdletBinding()]
Param
(
	[Parameter()]
		[ValidateNotNull()]
			$Configuration = 'release'
)

$Source = Join-Path $PSScriptRoot ../source
$Dependencies = Join-Path $PSScriptRoot ../dependencies
$BuildPath = Join-Path $PSScriptRoot "../build/$Configuration"
$ZLibBuildPath = Join-Path $BuildPath zlib-ng

New-Item -ItemType Directory -Force -Path $ZLibBuildPath > $Null

Push-Location -LiteralPath $ZLibBuildPath

try
{
	cmake $Dependencies/zlib-ng -T ClangCL -DZLIB_COMPAT=ON -DWITH_GZFILEOP=OFF -DZLIB_ENABLE_TESTS=OFF

	$SolutionConfiguration = if ($Configuration -eq 'release')
	{
		'RelWithDebInfo'
	}
	else
	{
		'Debug'
	}

	devenv zlib.sln /Build "$SolutionConfiguration|x64"
}
finally
{
	Pop-Location
}

