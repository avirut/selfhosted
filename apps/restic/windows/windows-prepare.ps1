# Dot-source from windows-run.ps1. This file never loads credentials or uploads.
. "$PSScriptRoot\windows-native-common.ps1"
. "$PSScriptRoot\windows-git.ps1"
Add-Type -AssemblyName System.Web.Extensions
function Test-JsonText([string]$Text,[int]$Limit) {
    $parser=[Web.Script.Serialization.JavaScriptSerializer]::new()
    $parser.MaxJsonLength=$Limit; $parser.RecursionLimit=2048
    try { $null=$parser.DeserializeObject($Text) } catch { throw 'invalid_json' }
}
function Get-PreparedInventory($Source) {
    $opaque=($Source.PSObject.Properties.Name -contains 'git_root') -and $Source.git_root
    Get-SourceFiles $Source | Where-Object { $opaque -or $_.Path -notmatch '(?i)(\.db|\.sqlite|\.sqlite3)-(wal|shm|journal)$' }
}
function Copy-PreparedFile([string]$Path,[string]$Target,[bool]$Opaque,$Limits,[string]$Sqlite) {
    Test-Deadline
    $null=Assert-PlainPath $Path; $null=Assert-PlainPath $Target
    $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
    $info=[IO.FileInfo]::new($Path)
    if ($info.Length -gt $Limits.max_file_bytes) { throw 'file_limit' }
    $initial=[IO.File]::Open($Path,'Open','Read','ReadWrite')
    try {
        $identity=[KroacnetFileIdentity]::Get($initial)
        $length=$initial.Length; $write=$info.LastWriteTimeUtc.Ticks
        $ext=[IO.Path]::GetExtension($Path).ToLowerInvariant()
        if (-not $Opaque -and $ext -in @('.db','.sqlite','.sqlite3')) {
            foreach ($suffix in @('-wal','-shm','-journal')) { $null=Assert-PlainPath ($Path+$suffix) }
            $dest=$Target.Replace('\','/')
            if ($dest -match '["\r\n]') { throw 'sqlite_path_invalid' }
            $seconds=[int][Math]::Max(1,[Math]::Min($Limits.sqlite_timeout_seconds,($script:Deadline-[DateTime]::UtcNow).TotalSeconds))
            $cmd=".timeout $($Limits.busy_timeout_ms)`n.backup `"$dest`"`n"
            $r=Invoke-Native $Sqlite @('-batch','-bail','-readonly','-init','NUL',$Path) $cmd $seconds
            if ($r.Exit -ne 0) { throw 'sqlite_backup_failed' }
            # Only the newly created stage copy is made self-contained; source stays read-only.
            $r=Invoke-Native $Sqlite @('-batch','-bail','-init','NUL',$Target) "PRAGMA journal_mode=DELETE; PRAGMA integrity_check;`n" $seconds
            if ($r.Exit -ne 0 -or $r.Out.Trim() -cnotmatch '^delete\s+ok$') { throw 'sqlite_integrity_failed' }
            $check=[IO.File]::Open($Path,'Open','Read','ReadWrite')
            try { if ([KroacnetFileIdentity]::Get($check) -cne $identity) { throw 'sqlite_source_replaced' } } finally { $check.Dispose() }
            return @{method='sqlite_cli_online_backup';bytes=([IO.FileInfo]::new($Target)).Length;sha256=(Get-Hash $Target)}
        }
        $output=[IO.File]::Open($Target,'CreateNew','ReadWrite','None')
        try {
            $buffer=New-Object byte[] 1048576; $left=$length
            while ($left -gt 0) {
                Test-Deadline
                $n=$initial.Read($buffer,0,[int][Math]::Min($left,$buffer.Length))
                if ($n -eq 0) { throw 'source_shrank' }
                $output.Write($buffer,0,$n); $left-=$n
            }
            $method='stable_file'; $records=0; $cutoff=$length
            if (-not $Opaque -and $ext -eq '.jsonl') {
                $method='jsonl_prefix'; $cutoff=0; $pos=$length
                while ($pos -gt 0) {
                    $n=[int][Math]::Min($pos,65536); $pos-=$n; $output.Position=$pos
                    $buffer=New-Object byte[] $n; $got=$output.Read($buffer,0,$n)
                    if ($got -ne $n) { throw 'stage_read_failed' }
                    $idx=[Array]::LastIndexOf($buffer,[byte]10)
                    if ($idx -ge 0) { $cutoff=$pos+$idx+1; break }
                    if ($length-$pos -gt $Limits.max_jsonl_record_bytes) { throw 'jsonl_record_limit' }
                }
                $output.SetLength($cutoff)
                $output.Position=0
                $reader=[IO.StreamReader]::new($output,$script:Utf8,$false,65536,$true)
                try {
                    while ($null -ne ($line=$reader.ReadLine())) {
                        Test-Deadline
                        if ($script:Utf8.GetByteCount($line) -gt $Limits.max_jsonl_record_bytes) { throw 'jsonl_record_limit' }
                        Test-JsonText $line $Limits.max_jsonl_record_bytes; $records++
                    }
                } finally { $reader.Dispose() }
            } elseif (-not $Opaque -and $ext -eq '.json') {
                if ($length -gt $Limits.max_json_bytes) { throw 'json_limit' }
                $output.Position=0; $reader=[IO.StreamReader]::new($output,$script:Utf8,$true,4096,$true)
                try { Test-JsonText ($reader.ReadToEnd()) $Limits.max_json_bytes } finally { $reader.Dispose() }
                $method='stable_json'
            }
            $output.Flush($true)
            $copiedHash=Get-PrefixHash $output $cutoff
            $sourceHash=Get-PrefixHash $initial $cutoff
            if ($copiedHash -cne $sourceHash) { throw 'source_changed' }
            $check=[IO.File]::Open($Path,'Open','Read','ReadWrite')
            try {
                if ([KroacnetFileIdentity]::Get($check) -cne $identity) { throw 'source_replaced' }
                if ($check.Length -lt $length -or $initial.Length -lt $length) { throw 'source_shrank' }
                if ((Get-PrefixHash $check $cutoff) -cne $copiedHash) { throw 'source_changed' }
                $now=[IO.FileInfo]::new($Path)
                if ($method -ne 'jsonl_prefix' -and ($now.Length -ne $length -or $now.LastWriteTimeUtc.Ticks -ne $write)) { throw 'source_changed' }
            } finally { $check.Dispose() }
            return @{method=$method;bytes=$cutoff;sha256=$copiedHash;records=$records;initial_bytes=$length;unfinished_bytes=($length-$cutoff)}
        } finally { $output.Dispose() }
    } finally { $initial.Dispose() }
}
function Invoke-WindowsPrepare([string]$ConfigPath,[string]$Stage,[string]$Sqlite='C:\ProgramData\KroacnetBackup\bin\sqlite3.exe') {
    Assert-Private $ConfigPath; Assert-Private $Stage
    $configHash=Get-Hash $ConfigPath
    $config=[IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    if ($config.schema -ne 1 -or $config.host -cne 'chrysaora') { throw 'invalid_config_host' }
    $script:Deadline=[DateTime]::UtcNow.AddSeconds($config.limits.timeout_seconds)
    Remove-OwnedPending $Stage
    $files=[Collections.Generic.List[object]]::new(); $aliases=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $sources=@($config.sources); $guards=@{}; $gitStates=@{}; $inventories=@{}; $missing=[Collections.Generic.List[string]]::new()
    foreach ($source in $sources) {
        $alias=[string]$source.alias
        if ($alias -notmatch '^[A-Za-z0-9_. -]+(/[A-Za-z0-9_. -]+)*$' -or @($alias.Split('/') | Where-Object {$_ -in @('.','..')}).Count -or $alias -eq 'manifest.json') { throw 'invalid_alias' }
        foreach ($prior in $aliases) { if ($alias.StartsWith($prior+'/',[StringComparison]::OrdinalIgnoreCase) -or $prior.StartsWith($alias+'/',[StringComparison]::OrdinalIgnoreCase)) { throw 'alias_overlap' } }
        if (-not $aliases.Add($alias)) { throw 'duplicate_alias' }
        $root=Assert-PlainPath $source.path
        $stageFull=Assert-PlainPath $Stage
        if ($root -eq $stageFull -or $root.StartsWith($stageFull+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'staging_source_overlap' }
        $list=@(Get-PreparedInventory $source)
        foreach ($file in $list) { if ($file.Path.StartsWith($stageFull+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'staging_source_overlap' } }
        $inventories[$alias]=$list
        if (-not (Test-Path -LiteralPath $root)) { $missing.Add($alias) }
        $git=($source.PSObject.Properties.Name -contains 'git_root') -and $source.git_root
        if ($git) {
            if (-not [IO.Directory]::Exists([IO.Path]::Combine($root,'.git'))) { throw 'git_control_directory_missing' }
            $guards[$alias]=Get-TreeGuard $source
            $gitStates[$alias]=Get-GitLocalState $root
        }
    }
    $pending=[IO.Path]::Combine($Stage,'pending'); New-PrivateDirectory $pending
    $payload=[IO.Path]::Combine($pending,'payload'); New-PrivateDirectory $payload
    $total=[long]0
    try {
        foreach ($source in $sources) {
            $opaque=($source.PSObject.Properties.Name -contains 'git_root') -and $source.git_root
            if ($opaque) {
                $destination=[IO.Path]::Combine($payload,($source.alias+'/git').Replace('/','\'))
                $gitFiles=@(Export-GitLogical $gitStates[$source.alias] $destination $config.limits $Sqlite)
                foreach ($f in $gitFiles) {
                    Test-Deadline
                    $bytes=([IO.FileInfo]::new($f.Path)).Length
                    if ($bytes -gt $config.limits.max_file_bytes) { throw 'file_limit' }
                    $files.Add([pscustomobject]@{path=($source.alias+'/git/'+$f.Relative);method='git_logical';bytes=$bytes;sha256=(Get-Hash $f.Path)})
                    $total+=$bytes
                    if ($files.Count -gt $config.limits.max_files -or $total -gt $config.limits.max_total_bytes) { throw 'payload_limit' }
                }
            }
            foreach ($file in $inventories[$source.alias]) {
                Test-Deadline
                $relative=$source.alias
                if ($opaque) { $relative+='/worktree' }
                if ($file.Relative) { $relative+='/'+$file.Relative }
                if (-not $opaque -and $file.Path -match '(?i)(\.db|\.sqlite|\.sqlite3)-(wal|shm|journal)$') { continue }
                $target=[IO.Path]::Combine($payload,$relative.Replace('/','\'))
                $record=Copy-PreparedFile $file.Path $target $opaque $config.limits $Sqlite
                if ($record.bytes -gt $config.limits.max_file_bytes) { throw 'file_limit' }
                $record['path']=$relative; $files.Add([pscustomobject]$record); $total+=$record.bytes
                if ($files.Count -gt $config.limits.max_files -or $total -gt $config.limits.max_total_bytes) { throw 'payload_limit' }
                if ($opaque) {
                    $expected=$guards[$source.alias][$file.Relative].Split(':')[-1]
                    if ($record.sha256 -cne $expected) { throw 'repository_changed' }
                }
            }
        }
        foreach ($source in $sources) {
            if ($guards.ContainsKey($source.alias)) {
                Assert-TreeEqual $guards[$source.alias] (Get-TreeGuard $source)
                Assert-GitLocalEqual $gitStates[$source.alias] (Get-GitLocalState $source.path)
            }
            else {
                $before=@($inventories[$source.alias] | ForEach-Object {$_.Relative} | Sort-Object)
                $after=@(Get-PreparedInventory $source | ForEach-Object {$_.Relative} | Sort-Object)
                if (($before -join "`n") -cne ($after -join "`n")) { throw 'source_inventory_changed' }
            }
        }
        if ((Get-Hash $ConfigPath) -cne $configHash) { throw 'config_changed' }
        foreach ($file in $files) {
            Test-Deadline
            if ((Get-Hash ([IO.Path]::Combine($payload,$file.path.Replace('/','\')))) -cne $file.sha256) { throw 'staged_hash_mismatch' }
        }
        $manifest=[ordered]@{schema=1;host='chrysaora';run_id=[Guid]::NewGuid().ToString();prepared_utc=[DateTime]::UtcNow.ToString('o');config_sha256=$configHash;source_count=$sources.Count;git_representation='git-bundle-index-v1';optional_missing=@($missing);files=@($files.ToArray());file_count=$files.Count;payload_bytes=$total;browser_preferences='excluded_unavailable'}
        Write-JsonAtomic ([IO.Path]::Combine($payload,'manifest.json')) $manifest
        Write-JsonAtomic ([IO.Path]::Combine($pending,'ready.json')) @{run_id=$manifest.run_id;manifest_sha256=(Get-Hash ([IO.Path]::Combine($payload,'manifest.json')))}
        return [pscustomobject]@{RunId=$manifest.run_id;Files=$files.Count;Bytes=$total;Payload=$payload;ManifestHash=(Get-Hash ([IO.Path]::Combine($payload,'manifest.json')))}
    } catch {
        $originalError=$_
        try { Remove-OwnedPending $Stage } catch { }
        throw $originalError
    }
    finally { $script:Deadline=$null }
}
function Assert-PreparedPayload($Prepared) {
    $manifestPath=[IO.Path]::Combine($Prepared.Payload,'manifest.json')
    if ((Get-Hash $manifestPath) -cne $Prepared.ManifestHash) { throw 'manifest_changed' }
    $m=[IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $inventory=@(Get-SourceFiles ([pscustomobject]@{path=$Prepared.Payload;required=$true;excludes=@()}))
    if ($inventory.Count -ne $m.file_count+1) { throw 'payload_inventory_changed' }
    foreach ($f in $m.files) {
        $p=[IO.Path]::Combine($Prepared.Payload,$f.path.Replace('/','\'))
        if (([IO.FileInfo]::new($p)).Length -ne $f.bytes -or (Get-Hash $p) -cne $f.sha256) { throw 'payload_changed' }
    }
}
