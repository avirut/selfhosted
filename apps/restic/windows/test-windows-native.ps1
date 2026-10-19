param([string]$Sqlite='C:\ProgramData\KroacnetBackup\bin\sqlite3.exe',[string]$Restic='C:\ProgramData\KroacnetBackup\bin\restic.exe')
. "$PSScriptRoot\windows-prepare.ps1"
$fixture=Join-Path $PSScriptRoot ('fixture-'+[Guid]::NewGuid().ToString('N'))
New-PrivateDirectory $fixture
$passed=[Collections.Generic.List[string]]::new()
function Assert-Test([bool]$Value,[string]$Name) { if (-not $Value) { throw ('TEST_FAILED '+$Name) }; $passed.Add($Name) }
function Expect-Refusal([scriptblock]$Action,[string]$Expected,[string]$Name) {
    $seen=$false
    try { & $Action | Out-Null } catch { $seen=$_.Exception.Message -like ('*'+$Expected+'*') }
    Assert-Test $seen $Name
}
function Write-Fixture([string]$Path,[string]$Text) { $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)); [IO.File]::WriteAllText($Path,$Text,$script:Utf8) }
$src=Join-Path $fixture 'source with [brackets]'; New-PrivateDirectory $src
$git=Join-Path $src 'repo'; New-PrivateDirectory $git
Write-Fixture (Join-Path $git '.git\HEAD') 'ref: refs/heads/main'
Write-Fixture (Join-Path $git '.git\refs\heads\main') ('a'*40)
Write-Fixture (Join-Path $git 'tsconfig.json') "{// comment`n unquoted:invalid fixture}"
Write-Fixture (Join-Path $git 'partial.jsonl') '{unfinished'
Write-Fixture (Join-Path $git 'fixture.sqlite') 'not a database fixture'
Write-Fixture (Join-Path $git 'node_modules\ignored.txt') 'ignored'
Write-Fixture (Join-Path $git 'artifacts\ignored.txt') 'ignored'
$runtime=Join-Path $src 'runtime'; New-PrivateDirectory $runtime
Write-Fixture (Join-Path $runtime 'settings.json') '{"good":true}'
Write-Fixture (Join-Path $runtime 'history.jsonl') "{`"first`":1}`r`n{`"second`":2}`n{`"partial`":"
$db=Join-Path $runtime 'state.sqlite'
$r=Invoke-Native $Sqlite @('-batch','-bail','-init','NUL',$db) "PRAGMA journal_mode=WAL; CREATE TABLE t(v); INSERT INTO t VALUES(42);`n" 10
Assert-Test ($r.Exit -eq 0) 'sqlite fixture created'
$stage=Join-Path $fixture 'stage'; New-PrivateDirectory $stage
$testEnv=Join-Path $fixture 'synthetic.env'
$envText=@'
RESTIC_REPOSITORY='s3:https://example.invalid/bucket'
RESTIC_PASSWORD='literal $value with spaces and '"'"'quote'
AWS_ACCESS_KEY_ID='synthetic'
AWS_SECRET_ACCESS_KEY='literal\value=other'
'@
Write-Fixture $testEnv $envText
$parsed=Read-SharedEnv $testEnv
Assert-Test ($parsed.Count -eq 4 -and $parsed.RESTIC_PASSWORD -ceq 'literal $value with spaces and ''quote' -and $parsed.AWS_SECRET_ACCESS_KEY -ceq 'literal\value=other') 'POSIX single quotes and apostrophe concatenation parsed literally'
Write-Fixture $testEnv ($envText+"`nAWS_ACCESS_KEY_ID='duplicate'")
Expect-Refusal { Read-SharedEnv $testEnv } 'duplicate_env_key' 'duplicate env refused'
Write-Fixture $testEnv ($envText.Replace("AWS_ACCESS_KEY_ID='synthetic'",'AWS_ACCESS_KEY_ID=$(should-never-execute)'))
Expect-Refusal { Read-SharedEnv $testEnv } 'invalid_env_quoting' 'shell evaluation syntax refused'
Write-Fixture $testEnv ($envText+"`nRESTIC_PASSWORD_COMMAND='forbidden'")
Expect-Refusal { Read-SharedEnv $testEnv } 'invalid_env' 'external password command refused'
$configPath=Join-Path $fixture 'fixture.json'
$config=@{schema=1;host='chrysaora';stage_dir=$stage;project_root=$fixture;limits=@{max_files=100;max_file_bytes=67108864;max_total_bytes=134217728;max_json_bytes=1048576;max_jsonl_record_bytes=1048576;timeout_seconds=120;sqlite_timeout_seconds=10;busy_timeout_ms=1000};sources=@(@{path=$git;alias='sources/test';required=$true;git_root=$true;excludes=@('node_modules','artifacts')},@{path=$runtime;alias='runtime';required=$true;excludes=@()})}
Write-JsonAtomic $configPath $config
$prepared=Invoke-WindowsPrepare $configPath $stage $Sqlite
$manifest=Get-Content -LiteralPath (Join-Path $prepared.Payload 'manifest.json') -Raw | ConvertFrom-Json
Assert-Test ($prepared.Files -eq 8) 'selected file count and exclusions'
foreach ($rel in @('tsconfig.json','partial.jsonl','fixture.sqlite','.git\HEAD','.git\refs\heads\main')) {
    Assert-Test ((Get-Hash (Join-Path $git $rel)) -eq (Get-Hash (Join-Path $prepared.Payload ('sources\test\'+$rel)))) ('opaque Git bytes '+$rel)
}
$jsonl=Join-Path $prepared.Payload 'runtime\history.jsonl'
Assert-Test ([IO.File]::ReadAllText($jsonl) -ceq "{`"first`":1}`r`n{`"second`":2}`n") 'JSONL exact CRLF/LF complete prefix'
$r=Invoke-Native $Sqlite @('-batch','-bail','-readonly','-init','NUL',(Join-Path $prepared.Payload 'runtime\state.sqlite')) "PRAGMA integrity_check; SELECT v FROM t;`n" 10
Assert-Test ($r.Exit -eq 0 -and $r.Out.Trim() -match '^ok\s+42$') 'online SQLite integrity and logical data'
Assert-PreparedPayload $prepared
Assert-Test $true 'prepared manifest and complete payload verified'
$targetSettings=Join-Path $prepared.Payload 'runtime\settings.json'
Write-Fixture $targetSettings '{"tampered":true}'
Expect-Refusal { Assert-PreparedPayload $prepared } 'payload_changed' 'staging tamper refused'
Write-Fixture $targetSettings '{"good":true}'
Assert-Test (@($manifest.files | Where-Object {$_.path -match '-(wal|shm|journal)$'}).Count -eq 0) 'no raw SQLite sidecars'
Assert-Test ((Test-Path -LiteralPath (Join-Path $stage 'pending\ready.json'))) 'ready only after complete preparation'
$guard=Get-TreeGuard $config.sources[0]
Write-Fixture (Join-Path $git '.git\FETCH_HEAD') 'concurrent fetch'
Expect-Refusal { Assert-TreeEqual $guard (Get-TreeGuard $config.sources[0]) } 'repository_changed' 'Git fetch detected'
Write-Fixture (Join-Path $git '.git\index.lock') 'locked'
Expect-Refusal { Get-TreeGuard $config.sources[0] } 'git_lock_present' 'active Git lock refused'
[IO.File]::Delete((Join-Path $git '.git\index.lock'))
Write-Fixture (Join-Path $runtime 'settings.json') '{broken'
Expect-Refusal { Invoke-WindowsPrepare $configPath $stage $Sqlite } 'invalid_json' 'invalid runtime JSON refused'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $stage 'pending'))) 'failed preparation removes ready and payload'
Write-Fixture (Join-Path $runtime 'settings.json') '{"good":true}'
Write-Fixture (Join-Path $runtime 'history.jsonl') "{broken}`n"
Expect-Refusal { Invoke-WindowsPrepare $configPath $stage $Sqlite } 'invalid_json' 'invalid complete JSONL refused'
Write-Fixture (Join-Path $runtime 'history.jsonl') "{`"good`":1}`n"
$held=[IO.File]::Open((Join-Path $runtime 'settings.json'),'Open','ReadWrite','None')
try { Expect-Refusal { Invoke-WindowsPrepare $configPath $stage $Sqlite } 'being used' 'locked source refused' } finally { $held.Dispose() }
$config.sources+=@{path=(Join-Path $src 'missing');alias='missing';required=$true;excludes=@()}; Write-JsonAtomic $configPath $config
Expect-Refusal { Invoke-WindowsPrepare $configPath $stage $Sqlite } 'required_source_missing' 'required missing source refused'
$config.sources=$config.sources[0..1]; Write-JsonAtomic $configPath $config
$config.limits.max_file_bytes=4; Write-JsonAtomic $configPath $config
Expect-Refusal { Invoke-WindowsPrepare $configPath $stage $Sqlite } 'file_limit' 'oversize file refused'
$config.limits.max_file_bytes=67108864; Write-JsonAtomic $configPath $config
$config.sources+=@{path=$runtime;alias='runtime/overlap';required=$true;excludes=@()}; Write-JsonAtomic $configPath $config
Expect-Refusal { Invoke-WindowsPrepare $configPath $stage $Sqlite } 'alias_overlap' 'overlapping aliases refused'
$config.sources=$config.sources[0..1]; Write-JsonAtomic $configPath $config
$broad=Join-Path $fixture 'broad'; New-PrivateDirectory $broad
$acl=Get-Acl -LiteralPath $broad
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),'Read','Allow'))
Set-Acl -LiteralPath $broad -AclObject $acl
Expect-Refusal { Assert-Private $broad } 'broad_acl' 'broad Users ACL refused'
$link=Join-Path $fixture 'junction'
$null=New-Item -ItemType Junction -Path $link -Target $stage
Expect-Refusal { Assert-PlainPath $link } 'reparse_path' 'real Windows junction refused'
$prepared=Invoke-WindowsPrepare $configPath $stage $Sqlite
$localRepo=Join-Path $fixture 'synthetic-restic-repository'
$syntheticEnv=@{RESTIC_REPOSITORY=$localRepo;RESTIC_PASSWORD='synthetic-test-password-only'}
$r=Invoke-Native $Restic @('--json','--no-cache','init') '' 30 $syntheticEnv
Assert-Test ($r.Exit -eq 0) 'official Restic local synthetic repository'
$r=Invoke-Native $Restic @('--json','--no-cache','backup','--host','chrysaora','--tag','apps','--','payload') '' 60 $syntheticEnv ([IO.Path]::GetDirectoryName($prepared.Payload))
Assert-Test ($r.Exit -eq 0 -and $r.Out -match '"snapshot_id"') 'official Restic backup snapshot'
$restore=Join-Path $fixture 'restored'
$r=Invoke-Native $Restic @('--no-cache','restore','latest','--host','chrysaora','--tag','apps','--target',$restore) '' 60 $syntheticEnv
Assert-Test ($r.Exit -eq 0) 'official Restic isolated restore'
$restoredManifest=@(Get-ChildItem -LiteralPath $restore -Filter 'manifest.json' -Recurse)
Assert-Test ($restoredManifest.Count -eq 1 -and (Get-Hash $restoredManifest[0].FullName) -eq $prepared.ManifestHash) 'restored manifest exact'
$restoredPayload=$restoredManifest[0].DirectoryName
$manifest=Get-Content -LiteralPath $restoredManifest[0].FullName -Raw | ConvertFrom-Json
foreach ($file in $manifest.files) { Assert-Test ((Get-Hash (Join-Path $restoredPayload $file.path.Replace('/','\'))) -eq $file.sha256) ('restored payload '+$file.path) }
$r=Invoke-Native $Restic @('--no-cache','check','--read-data') '' 60 $syntheticEnv
Assert-Test ($r.Exit -eq 0) 'official Restic synthetic repository read-data'
# Keep a synthetic SQLite connection open so committed data remains in WAL.
$walDB=Join-Path $fixture 'open-wal.sqlite'
$walOut=Join-Path $fixture 'online-copy.sqlite'
$si=[Diagnostics.ProcessStartInfo]::new($Sqlite,('-batch -bail -init NUL "'+$walDB+'"'))
$si.UseShellExecute=$false; $si.CreateNoWindow=$true; $si.RedirectStandardInput=$true; $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
$writer=[Diagnostics.Process]::new(); $writer.StartInfo=$si
try {
    $null=$writer.Start()
    $writer.StandardInput.WriteLine("PRAGMA journal_mode=WAL; CREATE TABLE live(v); INSERT INTO live VALUES(91); SELECT 'READY';")
    $writer.StandardInput.Flush()
    foreach ($expected in @('wal','READY')) {
        $lineTask=$writer.StandardOutput.ReadLineAsync()
        if (-not $lineTask.Wait(5000) -or $lineTask.Result -cne $expected) { throw 'wal_fixture_failed' }
    }
    Assert-Test (([IO.FileInfo]::new($walDB+'-wal')).Length -gt 0) 'live committed WAL fixture present'
    $beforeDB=Get-Hash $walDB; $beforeWAL=Get-Hash ($walDB+'-wal')
    $script:Deadline=[DateTime]::UtcNow.AddSeconds(30)
    $copy=Copy-PreparedFile $walDB $walOut $false ([pscustomobject]$config.limits) $Sqlite
    $script:Deadline=$null
    $r=Invoke-Native $Sqlite @('-batch','-bail','-readonly','-init','NUL',$walOut) "PRAGMA integrity_check; SELECT v FROM live;`n" 10
    Assert-Test ($r.Exit -eq 0 -and $r.Out.Trim() -match '^ok\s+91$') 'online backup includes live committed WAL'
    Assert-Test ((Get-Hash $walDB) -ceq $beforeDB -and (Get-Hash ($walDB+'-wal')) -ceq $beforeWAL) 'online reader leaves DB and WAL bytes unchanged'
} finally {
    $writer.StandardInput.Close()
    if (-not $writer.WaitForExit(5000)) { $writer.Kill(); $writer.WaitForExit() }
    $writer.Dispose(); $script:Deadline=$null
}
# Exercise the actual runner's failure/success-preservation path with synthetic state.
Write-JsonAtomic (Join-Path $stage 'last-success.json') @{sentinel='prior success'}
$priorSuccess=Get-Hash (Join-Path $stage 'last-success.json')
$powershell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$r=Invoke-Native $powershell @('-NoProfile','-NonInteractive','-File',"$PSScriptRoot\windows-run.ps1",'-ConfigPath',$configPath,'-EnvPath',$testEnv) '' 60
Assert-Test ($r.Exit -ne 0 -and $r.Error -match 'KROACNET_BACKUP_FAILED invalid_env') 'runner nonzero before cloud on invalid env'
Assert-Test ((Get-Hash (Join-Path $stage 'last-success.json')) -ceq $priorSuccess) 'failure preserves last success'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $stage 'pending'))) 'runner failure never retains stale payload'
$lock=[IO.File]::Open((Join-Path $stage 'native-backup.lock'),'OpenOrCreate','ReadWrite','None')
try {
    $r=Invoke-Native $powershell @('-NoProfile','-NonInteractive','-File',"$PSScriptRoot\windows-run.ps1",'-Mode','Prepare','-ConfigPath',$configPath) '' 20
    Assert-Test ($r.Exit -ne 0 -and $r.Error -match 'backup_already_running') 'runner refuses overlapping backup'
} finally { $lock.Dispose() }
$xml=[xml](Get-Content -LiteralPath "$PSScriptRoot\windows-daily.xml" -Raw)
Assert-Test ($xml.Task.Settings.WakeToRun -eq 'false' -and $xml.Task.Settings.StartWhenAvailable -eq 'true' -and $xml.Task.Triggers.CalendarTrigger.StartBoundary.EndsWith('T04:50:00')) 'task daily catch-up no wake definition'
$receipt=@{utc=[DateTime]::UtcNow.ToString('o');passed=$passed.Count;tests=@($passed.ToArray());fixture=$fixture;cloud_access=$false;real_source_preparation=$false}
Write-JsonAtomic (Join-Path $PSScriptRoot 'test-receipt.json') $receipt
$receipt | ConvertTo-Json -Depth 4
