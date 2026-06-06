# Read-only: collect basenames from E:\Ctrl4U, find same basenames elsewhere on E:\
$ErrorActionPreference = 'SilentlyContinue'
$projectRoot = 'E:\Ctrl4U'
$out = Join-Path $projectRoot '_basename_scan_report.txt'

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Ctrl4U basename scan (read-only)')
[void]$sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine('')

$projectExample = @{}
$fileCount = 0
Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Force | ForEach-Object {
    $fileCount++
    $n = $_.Name
    if (-not $projectExample.ContainsKey($n)) {
        $projectExample[$n] = $_.FullName
    }
}
[void]$sb.AppendLine("Ctrl4U files scanned: $fileCount")
[void]$sb.AppendLine("Unique basenames: $($projectExample.Count)")
[void]$sb.AppendLine('')

$basenameSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($k in $projectExample.Keys) {
    [void]$basenameSet.Add($k)
}

$external = @{}

function ShouldSkipPath([string] $p) {
    $norm = $p.ToLowerInvariant().Replace('/', '\').TrimEnd('\')
    if ($norm -eq 'e:\ctrl4u') { return $true }
    return $norm.StartsWith('e:\ctrl4u\')
}

function Add-ExternalMatch([string] $fullPath, [string] $base) {
    if (ShouldSkipPath $fullPath) { return }
    if (-not $script:external.ContainsKey($base)) {
        $script:external[$base] = [System.Collections.Generic.List[string]]::new()
    }
    $script:external[$base].Add($fullPath)
}

# E:\ root files
Get-ChildItem -LiteralPath 'E:\' -File -Force | ForEach-Object {
    if (ShouldSkipPath $_.FullName) { return }
    if ($basenameSet.Contains($_.Name)) {
        Add-ExternalMatch $_.FullName $_.Name
    }
}

# Each top-level directory on E:\
$topDirs = @(Get-ChildItem -LiteralPath 'E:\' -Directory -Force)
$dirIndex = 0
foreach ($d in $topDirs) {
    $dirIndex++
    if (ShouldSkipPath $d.FullName) {
        [void]$sb.AppendLine("SKIP tree: $($d.FullName)")
        continue
    }
    Write-Host "Scanning [$dirIndex/$($topDirs.Count)] $($d.FullName)"
    Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force | ForEach-Object {
        if ($basenameSet.Contains($_.Name)) {
            Add-ExternalMatch $_.FullName $_.Name
        }
    }
}

$totalExternal = 0
foreach ($lst in $external.Values) {
    $totalExternal += $lst.Count
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine("Matched basenames count: $($external.Count)")
[void]$sb.AppendLine("Total external matching files: $totalExternal")
[void]$sb.AppendLine('')

$sortedNames = $external.Keys | Sort-Object
foreach ($name in $sortedNames) {
    $proj = $projectExample[$name]
    [void]$sb.AppendLine("==== $name ====")
    [void]$sb.AppendLine("  [Ctrl4U] $proj")
    foreach ($p in $external[$name]) {
        [void]$sb.AppendLine("  [E:]     $p")
    }
}

[System.IO.File]::WriteAllText($out, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "Report written: $out"
