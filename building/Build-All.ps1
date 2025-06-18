
<# SPDX-LICENSE-IDENTIFIER: 0BSD #>

[CmdletBinding()]
Param
(
	[Parameter()]
		[ValidateNotNull()]
			$Configuration = 'release'
)


function ForEach-InParallel ($InputObject, $ScriptBlock, $ThrottleLimit = [Environment]::ProcessorCount)
{
	if ($PSVersionTable.PSVersion.Major -ge 7)
	{
		$IsSerial = $False
		$InputObject | ForEach-Object -Parallel $ScriptBlock -ThrottleLimit $ThrottleLimit
	}
	else
	{
		$IsSerial = $True
		$InputObject | ForEach-Object -Process $ScriptBlock
	}
}


$ScriptRoot = $PSScriptRoot


ForEach-InParallel $(
	,@('Build-Native.ps1')
	,@('Build-DotNetLibrary.ps1')
) `
{
	if (-not $IsSerial)
	{
		$Configuration = $Using:Configuration
		$ScriptRoot = $Using:ScriptRoot
	}

	foreach ($Script in $_)
	{
		& (Join-Path $ScriptRoot $Script) -Configuration $Configuration
	}
}

