param([string]$InputPath='C:\ProgramData\KroacnetBackup\windows.json',[string]$OutputPath="$PSScriptRoot\windows-native.json")
. "$PSScriptRoot\windows-native-common.ps1"
Assert-Private $InputPath
$inputHash=Get-Hash $InputPath
$c=[IO.File]::ReadAllText($InputPath) | ConvertFrom-Json
if ($c.schema -ne 1 -or $c.host -cne 'chrysaora' -or @($c.sources).Count -ne 56) { throw 'unexpected_allowlist' }
# No Python execution/import or changes to path, alias, required, exclusions or Git guards.
$native=[ordered]@{schema=1;host=$c.host;project_root=$c.project_root;stage_dir=$c.stage_dir;limits=$c.limits;sources=@($c.sources)}
Write-JsonAtomic $OutputPath $native
$r=[IO.File]::ReadAllText($OutputPath) | ConvertFrom-Json
if (($c.sources | ConvertTo-Json -Depth 10 -Compress) -cne ($r.sources | ConvertTo-Json -Depth 10 -Compress)) { throw 'source_conversion_mismatch' }
if ((Get-Hash $InputPath) -cne $inputHash) { throw 'input_config_changed' }
@{source_count=56;source_fields_preserved=$true;input_sha256=$inputHash;output_sha256=(Get-Hash $OutputPath)} | ConvertTo-Json -Compress
