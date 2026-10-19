<#
Logical Git backup; dot-sourced after common helpers. Never writes the source repo.

Payload layout for each unchanged git_root alias:
  <alias>/worktree/             exact selected working/untracked files
  <alias>/git/history.bundle    complete refs plus reflog-reachable history
  <alias>/git/index-objects-*   verified pack/idx (and optional rev) for index objects
  <alias>/git/control/          stable HEAD/index/config/excludes/hooks/local reflogs
  <alias>/git/recovery.json     object format, local refs/symrefs, layout/version

Recovery is an explicit offline operator procedure, NOT part of daily backup:
  1. Restore the complete alias into a private staging directory; verify EVERY
     selected file against the enclosing payload manifest before using Git.
  2. Initialize a NEW EMPTY destination with the recorded object_format, using
     fixed git, isolated system/global config, core.hooksPath=/dev/null,
     core.fsmonitor=false and GIT_OPTIONAL_LOCKS=0 as this helper does.
     Do not run checkout/clone into the owner's live source or enable hooks.
  3. git bundle verify <absolute history.bundle> in the empty repository must pass;
     git bundle unbundle <bundle> installs objects and prints OID/ref mappings.
     Restore those refs with git update-ref (only names under refs/), then apply
     recovery.json local symbolic refs with git symbolic-ref. This preserves the
     remote refs observed by the bundle; they are not a freshness guarantee.
  4. Copy index-objects-HASH.pack/.idx/.rev, when present, to the NEW repository's
     .git/objects/pack/pack-HASH.pack/.idx/.rev. Copy control/ contents into its
     .git directory, including exact HEAD/index/sharedindex files and local logs.
     Copy selected worktree/ files into the otherwise EMPTY working tree. Do not
     check out HEAD first: doing so would resurrect intentionally deleted files.
     Inspect preserved config/hooks before enabling ordinary user Git commands;
     keep hooks/fsmonitor disabled during recovery validation.
  5. git fsck --full, git status, git diff --cached --binary --no-ext-diff
     --no-textconv, git stash list and source/manifest hashes validate recovery.
     A valid full restore includes ALL selected files; partial restore is not a
     substitute for working/staged recovery. Excluded build/runtime trees remain
     excluded. Other registered worktrees' unselected working files are not added.

Background remote-ref/reflog/FETCH_HEAD/pack maintenance changes are not compared.
Local refs (including tags/stash/custom refs), local reflogs, HEAD/index/config,
selected files and exported bytes MUST remain stable throughout preparation.
Locks/FETCH_HEAD/remote reflogs/raw object storage are never copied.
Linked-worktree roots, shallow/promisor/reftable layouts, unborn HEAD and active
merge/rebase/cherry-pick/revert states fail closed; no auto-repair/network fetch.
Gitlinks record the commit identity but do not imply submodule working-tree
coverage. Unreferenced unreachable objects are not an authored-history contract.
No source hooks, index refresh, ref write, global safe.directory or policy change.

Primary Git contracts: https://git-scm.com/docs/git-bundle
https://git-scm.com/docs/git-pack-objects and https://git-scm.com/docs/git-rev-list
#>
$script:GitExe='C:\Program Files\Git\cmd\git.exe'
function Invoke-BackupGit([string]$Root,[string[]]$Arguments,[string]$InputText='') {
    $rootFull=Assert-PlainPath $Root
    Test-Deadline
    $seconds=120
    if ($script:Deadline) { $seconds=[int][Math]::Max(1,[Math]::Min(120,($script:Deadline-[DateTime]::UtcNow).TotalSeconds)) }
    $envValues=@{GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_SYSTEM='/dev/null';GIT_CONFIG_GLOBAL='/dev/null';GIT_OPTIONAL_LOCKS='0';GIT_TERMINAL_PROMPT='0';GIT_NO_LAZY_FETCH='1'}
    $prefix=@('--no-replace-objects','-c',('safe.directory='+$rootFull),'-c','core.fsmonitor=false','-c','core.hooksPath=/dev/null','-c','gc.auto=0','-c','maintenance.auto=false','-C',$rootFull)
    $r=Invoke-Native $script:GitExe ($prefix+$Arguments) $InputText $seconds $envValues
    if ($r.Exit -ne 0) { throw 'git_command_failed' }
    return $r.Out
}
function Get-GitControlFiles([string]$Root) {
    $dir=Assert-PlainPath ([IO.Path]::Combine($Root,'.git'))
    if (-not [IO.Directory]::Exists($dir)) { throw 'git_control_directory_missing' }
    # Fail closed on operation state that needs a separate recovery contract.
    foreach ($name in @('commondir','shallow','MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','REBASE_HEAD','rebase-apply','rebase-merge','sequencer','index.lock','HEAD.lock','config.lock','objects/info/alternates')) {
        if (Test-Path -LiteralPath ([IO.Path]::Combine($dir,$name.Replace('/','\')))) { throw 'git_operation_or_layout_unsupported' }
    }
    foreach ($name in @('HEAD','index','config','config.worktree','description','ORIG_HEAD','info/exclude','info/attributes')) {
        $path=[IO.Path]::Combine($dir,$name.Replace('/','\')); $null=Assert-PlainPath $path
        if ([IO.File]::Exists($path)) { [pscustomobject]@{Path=$path;Relative=$name} }
    }
    foreach ($path in [IO.Directory]::EnumerateFiles($dir,'sharedindex.*')) {
        $null=Assert-PlainPath $path; [pscustomobject]@{Path=$path;Relative=[IO.Path]::GetFileName($path)}
    }
    foreach ($sub in @('logs','hooks')) {
        $base=[IO.Path]::Combine($dir,$sub)
        if ([IO.Directory]::Exists($base)) {
            # Fetch reflogs are transient; local reflogs preserve stash history/recovery.
            $source=[pscustomobject]@{path=$base;required=$true;excludes=@('refs/remotes','*.lock')}
            foreach ($f in @(Get-SourceFiles $source)) { [pscustomobject]@{Path=$f.Path;Relative=($sub+'/'+$f.Relative)} }
        }
    }
}
function Get-GitLocalState([string]$Root) {
    $controls=@(Get-GitControlFiles $Root)
    $top=(Invoke-BackupGit $Root @('rev-parse','--show-toplevel')).Trim()
    if ([IO.Path]::GetFullPath($top) -ine [IO.Path]::GetFullPath($Root)) { throw 'git_root_mismatch' }
    $format=(Invoke-BackupGit $Root @('rev-parse','--show-object-format')).Trim()
    if ($format -notin @('sha1','sha256')) { throw 'git_object_format_unsupported' }
    $configText=Invoke-BackupGit $Root @('config','--local','--list')
    if ($configText -match '(?im)^(extensions\.(partialclone|refstorage)|remote\..*\.promisor)=') { throw 'git_operation_or_layout_unsupported' }
    $refs=[Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($line in ((Invoke-BackupGit $Root @('for-each-ref','--format=%(refname) %(objectname) %(symref)')) -split "`n")) {
        if (-not $line) { continue }
        if ($line -notmatch '^(refs/\S+) ([0-9a-f]{40,64}) ?(.*)$') { throw 'git_ref_invalid' }
        if ($Matches[1].StartsWith('refs/remotes/')) { continue }
        $refs.Add($Matches[1],($Matches[2]+' '+$Matches[3].TrimEnd("`r")))
    }
    $head=(Invoke-BackupGit $Root @('rev-parse','--verify','HEAD')).Trim()
    $map=[Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($f in $controls) {
        $i=[IO.FileInfo]::new($f.Path)
        $map.Add($f.Relative,('{0}:{1}:{2}:{3}' -f $i.Length,$i.LastWriteTimeUtc.Ticks,$i.CreationTimeUtc.Ticks,(Get-Hash $f.Path)))
    }
    # Read index entries without refresh or optional locks. Pack all non-gitlink
    # objects, including conflict stages, intent-to-add and sparse tree entries.
    $objects=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in ((Invoke-BackupGit $Root @('ls-files','--stage','-z')) -split "`0")) {
        if (-not $entry) { continue }
        if ($entry -notmatch '^(\d{6}) ([0-9a-f]{40,64}) [0-3]\t') { throw 'git_index_invalid' }
        if ($Matches[1] -ne '160000' -and $Matches[2] -notmatch '^0+$') { $null=$objects.Add($Matches[2]) }
    }
    return [pscustomobject]@{Root=$Root;Head=$head;Format=$format;Refs=$refs;Controls=$map;ControlFiles=$controls;IndexObjects=@($objects | Sort-Object)}
}
function Assert-GitLocalEqual($Before,$After) {
    if ($Before.Head -cne $After.Head -or $Before.Format -cne $After.Format) { throw 'repository_changed' }
    Assert-TreeEqual $Before.Refs $After.Refs
    Assert-TreeEqual $Before.Controls $After.Controls
    if (($Before.IndexObjects -join "`n") -cne ($After.IndexObjects -join "`n")) { throw 'repository_changed' }
}
function Export-GitLogical($State,[string]$Destination,$Limits,[string]$Sqlite) {
    $null=Assert-PlainPath $Destination
    $null=[IO.Directory]::CreateDirectory($Destination)
    $bundle=[IO.Path]::Combine($Destination,'history.bundle')
    # --reflog also retains older stash/local reflog objects. No revision limits,
    # shallow exclusions, remote fetch, source refs or source config writes.
    $null=Invoke-BackupGit $State.Root @('bundle','create',$bundle,'--all','--reflog')
    $null=Invoke-BackupGit $State.Root @('bundle','verify',$bundle)
    $bundleRefs=@{}
    foreach ($line in ((Invoke-BackupGit $State.Root @('bundle','list-heads',$bundle)) -split "`n")) {
        if (-not $line) { continue }
        if ($line -notmatch '^([0-9a-f]{40,64}) (.+)$') { throw 'git_bundle_ref_invalid' }
        $bundleRefs[$Matches[2].TrimEnd("`r")]=$Matches[1]
    }
    foreach ($ref in $State.Refs.Keys) {
        if (-not $bundleRefs.ContainsKey($ref) -or $bundleRefs[$ref] -cne $State.Refs[$ref].Split(' ')[0]) { throw 'repository_changed' }
    }
    if (-not $bundleRefs.ContainsKey('HEAD') -or $bundleRefs['HEAD'] -cne $State.Head) { throw 'repository_changed' }
    $indexPack=$null
    if ($State.IndexObjects.Count) {
        $prefix=[IO.Path]::Combine($Destination,'index-objects')
        $hash=(Invoke-BackupGit $State.Root @('pack-objects','--revs',$prefix) (($State.IndexObjects -join "`n")+"`n")).Trim()
        if ($hash -notmatch '^[0-9a-f]{40,64}$') { throw 'git_index_pack_invalid' }
        $indexPack='index-objects-'+$hash
        $null=Invoke-BackupGit $State.Root @('verify-pack',([IO.Path]::Combine($Destination,$indexPack+'.idx')))
    }
    foreach ($f in $State.ControlFiles) {
        $target=[IO.Path]::Combine($Destination,('control/'+$f.Relative).Replace('/','\'))
        $record=Copy-PreparedFile $f.Path $target $true $Limits $Sqlite
        if ($record.sha256 -cne $State.Controls[$f.Relative].Split(':')[-1]) { throw 'repository_changed' }
    }
    Assert-GitLocalEqual $State (Get-GitLocalState $State.Root)
    $refs=@($State.Refs.Keys | ForEach-Object { @{name=$_;oid=$State.Refs[$_].Split(' ')[0];symref=$State.Refs[$_].Substring($State.Refs[$_].IndexOf(' ')+1)} })
    Write-JsonAtomic ([IO.Path]::Combine($Destination,'recovery.json')) @{schema=1;representation='git-bundle-index-v1';object_format=$State.Format;head=$State.Head;local_refs=$refs;index_pack=$indexPack;bundle='history.bundle';controls='control';working_tree='../worktree';remote_refs='point_in_time_bundle_only';excluded_control='fetch bookkeeping, remote reflogs, locks, other worktree administrative state'}
    Get-SourceFiles ([pscustomobject]@{path=$Destination;required=$true;excludes=@()})
}
