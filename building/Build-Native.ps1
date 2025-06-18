
<# SPDX-LICENSE-IDENTIFIER: 0BSD #>

[CmdletBinding()]
Param
(
	[Parameter()]
		[ValidateNotNull()]
			$Configuration = 'release'
)

$Source = Join-Path $PSScriptRoot ../source
$BuildPath = Join-Path $PSScriptRoot "../build/$Configuration"
$ZLibBuildPath = Join-Path $BuildPath zlib-ng

New-Item -ItemType Directory -Force -Path $BuildPath > $Null

Push-Location -LiteralPath $BuildPath

try
{
	$SolutionConfiguration = if ($Configuration -eq 'release')
	{
		'RelWithDebInfo'
	}
	else
	{
		'Debug'
	}

	$ZLib = Join-Path $ZLibBuildPath $SolutionConfiguration
	$ZLibFiles = if ($Configuration -eq 'release') {'zlib.lib', 'zlib1.dll', 'zlib.pdb'} else {'zlibd.lib', 'zlibd1.dll', 'zlibd.pdb'}

	if ($ZLibFiles.Where({-not (Test-Path -LiteralPath $ZLib/$_)}, 'First').Count -ne 0)
	{
		& (Join-Path $PSScriptRoot Build-ZLibNG.ps1) -Configuration $Configuration
	}

	$ZLibFiles | % {Copy-Item -LiteralPath $ZLib/$_ -ErrorAction Stop}

	if ($Configuration -ne 'release')
	{
		Remove-Item -LiteralPath zlib.lib -Force -ErrorAction Ignore
		Rename-Item -LiteralPath ./zlibd.lib zlib.lib
		Remove-Item -LiteralPath zlib1.dll -Force -ErrorAction Ignore
		Rename-Item -LiteralPath ./zlibd1.dll zlib1.dll
		Remove-Item -LiteralPath zlib.pdb -Force -ErrorAction Ignore
		Rename-Item -LiteralPath ./zlibd.pdb zlib.pdb
	}

	Remove-Item -LiteralPath zlib1.pdb -Force -ErrorAction Ignore
	Rename-Item -LiteralPath ./zlib.pdb zlib1.pdb

	$CompilationFlags = if ($Configuration -eq 'release')
	{
		'-boundscheck=off'
		'-enable-contracts=false'
		'-checkaction=halt'
		'-release'
	}
	else
	{
		'-d-debug'
	}

	ldc2 -of bnkf2_exports.obj -c -g --shared -fvisibility hidden -dip1000 -betterC $CompilationFlags -enable-cross-module-inlining -O3 $Source/bnkf2/exports.d $Source/bnkf2/core.d $Source/zlib.d
	lld-link /out:bnkf2.dll /dll /noentry /nodefaultlib /debug:full /opt:ref ./bnkf2_exports.obj

	Remove-Item -LiteralPath bnkf2.dll.pdb -Force -ErrorAction Ignore
	Rename-Item -LiteralPath ./bnkf2.pdb bnkf2.dll.pdb

	ldc2 -of bnkf2_cli.obj -c -g -dip1000 -betterC $CompilationFlags -enable-cross-module-inlining -O3 $Source/bnkf2/cli.d $Source/bnkf2/package.d $Source/bnkf2/core.d $Source/zlib.d
	lld-link /out:bnkf2.exe /subsystem:Console /entry:entrypoint /nodefaultlib /debug:full /opt:ref ./bnkf2_cli.obj ./bnkf2.lib ./zlib.lib kernel32.lib

	Remove-Item -LiteralPath bnkf2.exe.pdb -Force -ErrorAction Ignore
	Rename-Item -LiteralPath ./bnkf2.pdb bnkf2.exe.pdb
}
finally
{
	Pop-Location
}

