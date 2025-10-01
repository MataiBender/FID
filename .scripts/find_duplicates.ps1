param([string]$root = (Get-Location).Path)

$exts = '.html','.htm','.css','.js','.png','.jpg','.jpeg','.gif','.svg'
Write-Output "Scanning $root for files..."
$files = Get-ChildItem -Path $root -Recurse -File | Where-Object { $exts -contains $_.Extension.ToLower() }
Write-Output ("Found {0} files to hash" -f $files.Count)

$hashes = @{}
foreach($f in $files){
    try{
        $h = (Get-FileHash -Algorithm SHA256 -Path $f.FullName -ErrorAction Stop).Hash
    } catch { continue }
    if(-not $hashes.ContainsKey($h)){ $hashes[$h] = @() }
    $hashes[$h] += $f.FullName
}

$dups = $hashes.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | Sort-Object Name
Write-Output ("Found {0} duplicate groups" -f $dups.Count)

# Build set of linked files from href/src in HTML files
$linked = New-Object System.Collections.Generic.HashSet[string]
$htmls = Get-ChildItem -Path $root -Recurse -File -Include *.html,*.htm
foreach($html in $htmls){
    $text = Get-Content -Raw -ErrorAction SilentlyContinue $html.FullName
    if(-not $text){ continue }
    $matches = [regex]::Matches($text,'(?:href|src)\s*=\s*"(.*?)"')
    foreach($m in $matches){
        $href = $m.Groups[1].Value.Trim()
        if($href -match '^(https?:|mailto:|#)'){ continue }
        if($href.StartsWith('/')){
            $cand = Join-Path $root $href.TrimStart('/')
        } else {
            $joined = Join-Path $html.DirectoryName $href
            try{ $rp = Resolve-Path -LiteralPath $joined -ErrorAction Stop; $cand = $rp.Path } catch { $cand = $null }
        }
        if($cand -and (Test-Path $cand)){
            $linked.Add((Get-Item $cand).FullName) | Out-Null
        }
    }
}

$out = @()
$count = 0
foreach($entry in $dups){
    $count++
    $out += ("--- DUP GROUP #{0} --- HASH: {1} ---" -f $count,$entry.Name)
    foreach($p in $entry.Value){
        $isLinked = $linked.Contains($p)
        $status = $isLinked ? 'LINKED' : 'UNLINKED'
        $out += ("[{0}] {1}" -f $status,$p)
    }
}
$out += ("--- Done. Duplicate groups found: {0} ---" -f $count)
$out | Out-File -FilePath (Join-Path $root 'duplicate_report.txt') -Encoding utf8
$out | Write-Output

Write-Output "Report written to: $root\duplicate_report.txt"