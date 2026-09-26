<#
.SYNOPSIS
  Builds Hoops and, optionally, drops it into GTA V or packs the release zip.

.DESCRIPTION
  Uses the self-contained Roslyn compiler rather than `dotnet build`, because the machine SDK
  is not reliable here and this needs no MSBuild -- one library, no NuGet, no project file.
  The toolchain is not in this repo: it looks for .\tools\ and then the copy under the hoodrich
  project next door, the same as Overspray.

  THE COURT IS SHARED. src\Hoops\Court\ is the game, and Posted Up carries a copy of it made by
  tools\sync-court.py. Edit it here, then sync; `python tools\sync-court.py --check` says whether
  the two have drifted.

.EXAMPLE
  .\build.ps1
  .\build.ps1 -Deploy            # GTA V must be closed
  .\build.ps1 -Deploy -Hot       # with it running; press Insert in game to reload scripts
  .\build.ps1 -Package           # release\Hoops-<version>.zip
#>
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',

    [switch]$Deploy,

    # Deploy with the game running. ScriptHookVDotNet shadow-copies every script, so the file in
    # scripts\ is not held open and can be replaced; the new one loads on the next reload.
    [switch]$Hot,

    # Builds the release zip in release\, with the tree a player unpacks.
    [switch]$Package,

    [ValidateSet('Legacy', 'Enhanced', 'Both')]
    [string]$Target = 'Both',

    [string]$GtaDir = 'C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V',
    [string]$EnhancedDir = 'C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V Enhanced',

    # Where the compiler lives. Its own tools\ first, then hoodrich's.
    [string]$Tools = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# --- the toolchain ----------------------------------------------------------
if (-not $Tools) {
    foreach ($c in @((Join-Path $root 'tools'), (Join-Path (Split-Path $root -Parent) 'hoodrich\tools'))) {
        if (Test-Path (Join-Path $c 'roslyn\tasks\net472\csc.exe')) { $Tools = $c; break }
    }
}

if (-not $Tools) { throw "No compiler found. Looked in .\tools\ and ..\hoodrich\tools\. Pass -Tools <path>." }

$csc    = Join-Path $Tools 'roslyn\tasks\net472\csc.exe'
$refDir = Join-Path $Tools 'refasm\build\.NETFramework\v4.8'

if (-not (Test-Path $csc))    { throw "Compiler missing: $csc" }
if (-not (Test-Path $refDir)) { throw "net48 reference assemblies missing: $refDir" }

$srcDir = Join-Path $root 'src\Hoops'
$outDir = Join-Path $root 'build'
$outDll = Join-Path $outDir 'Hoops.dll'

# ScriptHookVDotNet to compile against: the Legacy install's, else the Enhanced one's.
$shvdn = Join-Path $GtaDir 'ScriptHookVDotNet3.dll'
if (-not (Test-Path $shvdn)) { $shvdn = Join-Path $EnhancedDir 'ScriptHookVDotNet3.dll' }
if (-not (Test-Path $shvdn)) { throw "ScriptHookVDotNet3.dll not found under $GtaDir or $EnhancedDir" }

# Said out loud every build: the compiler stamps this exact version into the dll, and a player
# on an older ScriptHookVDotNet gets a load failure with nothing logged.
$shvdnVer = [System.Reflection.AssemblyName]::GetAssemblyName($shvdn).Version
Write-Host "ScriptHookVDotNet reference: $shvdnVer  (players need this or newer)" -ForegroundColor DarkCyan

New-Item -ItemType Directory -Force $outDir | Out-Null

# --- references: the BCL and SHVDN, nothing else ------------------------------
$refs = @()
foreach ($n in @('mscorlib.dll', 'System.dll', 'System.Core.dll', 'System.Drawing.dll',
                 'System.Windows.Forms.dll', 'System.Numerics.dll')) {
    $p = Join-Path $refDir $n
    if (-not (Test-Path $p)) { throw "Reference assembly missing: $p" }
    $refs += "/reference:`"$p`""
}
$refs += "/reference:`"$shvdn`""

$sources = Get-ChildItem $srcDir -Recurse -Filter *.cs |
    Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' } |
    ForEach-Object { $_.FullName }

if (-not $sources) { throw "No .cs sources found under $srcDir" }

$opts = @(
    '/target:library', '/platform:x64', '/langversion:9.0', '/nologo', '/warnaserror-',
    '/warn:4', '/nostdlib+', '/utf8output', "/out:`"$outDll`""
)

if ($Configuration -eq 'Debug') { $opts += '/debug:portable', '/define:DEBUG;TRACE', '/optimize-' }
else                            { $opts += '/debug-', '/optimize+' }

$rsp = Join-Path $outDir 'build.rsp'
($opts + $refs + ($sources | ForEach-Object { "`"$_`"" })) | Set-Content -Path $rsp -Encoding UTF8

Write-Host "Compiling $($sources.Count) source files -> $outDll ($Configuration)" -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
& $csc "@$rsp"
$exit = $LASTEXITCODE
$sw.Stop()

if ($exit -ne 0) { throw "Compilation failed (csc exit $exit)." }
Write-Host ("OK  {0:N0} bytes in {1:N1}s" -f (Get-Item $outDll).Length, $sw.Elapsed.TotalSeconds) -ForegroundColor Green

# --- deploy -----------------------------------------------------------------
function Deploy-To([string]$dir, [string]$label) {
    if (-not (Test-Path $dir)) { Write-Host "  skip   $label (not installed)" -ForegroundColor DarkGray; return }

    $scripts = Join-Path $dir 'scripts'
    New-Item -ItemType Directory -Force $scripts | Out-Null

    Copy-Item $outDll (Join-Path $scripts 'Hoops.dll') -Force

    # The ini is the player's: put there once, never overwritten.
    $iniSrc = Join-Path $root 'Hoops.ini'
    $iniDst = Join-Path $scripts 'Hoops.ini'

    if (Test-Path $iniDst) { Write-Host "  keep   Hoops.ini" -ForegroundColor DarkGray }
    else { Copy-Item $iniSrc $iniDst; Write-Host "  new    Hoops.ini" -ForegroundColor Green }

    # The art is ours, and always the latest.
    $artSrc = Join-Path $root 'data\icons'
    $artDst = Join-Path $scripts 'Hoops\icons'
    New-Item -ItemType Directory -Force $artDst | Out-Null

    $n = 0
    foreach ($f in Get-ChildItem $artSrc -Filter *.png) {
        $to = Join-Path $artDst $f.Name
        if ((Test-Path $to) -and (Get-FileHash $to).Hash -eq (Get-FileHash $f.FullName).Hash) { continue }
        Copy-Item $f.FullName $to -Force
        $n++
    }

    if ($n -gt 0) { Write-Host "  art    $n file(s)" -ForegroundColor Green }
    else          { Write-Host "  art    up to date" -ForegroundColor DarkGray }

    if (Test-Path (Join-Path $scripts 'Hoodrich.dll')) {
        Write-Host "  note   Posted Up is installed here: Hoops stands down unless StandDownForPostedUp=false." -ForegroundColor Yellow
    }

    Write-Host "  ok     $label" -ForegroundColor Green
}

if ($Deploy) {
    if (-not $Hot) {
        $running = Get-Process GTA5, GTA5_Enhanced -ErrorAction SilentlyContinue
        if ($running) { throw "GTA V is running - close it, or deploy with -Hot and press Insert in game." }
    }

    if ($Target -in 'Legacy', 'Both')   { Deploy-To $GtaDir      'Legacy' }
    if ($Target -in 'Enhanced', 'Both') { Deploy-To $EnhancedDir 'Enhanced' }

    Write-Host "Deploy complete." -ForegroundColor Green
}

# --- package ----------------------------------------------------------------
#
# The zip is the install: somebody drags "scripts" into the GTA folder. So the tree is built
# explicitly and then CHECKED, because a zip that quietly ships one file short is a support
# thread, not a release.
if ($Package) {
    $ver = (Select-String -Path (Join-Path $root 'src\Hoops\Core\Log.cs') `
                          -Pattern 'Version = "([^"]+)"').Matches[0].Groups[1].Value

    $stage = Join-Path $root 'build\pkg'
    $zip = Join-Path $root ('release\Hoops-' + $ver + '.zip')

    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force (Join-Path $stage 'scripts\Hoops\icons') | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $root 'release') | Out-Null

    Copy-Item $outDll                              (Join-Path $stage 'scripts\Hoops.dll')
    Copy-Item (Join-Path $root 'Hoops.ini')        (Join-Path $stage 'scripts\Hoops.ini')
    Copy-Item (Join-Path $root 'README.txt')       (Join-Path $stage 'README.txt')
    Copy-Item (Join-Path $root 'release\CHANGES.txt') (Join-Path $stage 'CHANGES.txt')

    foreach ($p in Get-ChildItem (Join-Path $root 'data\icons') -Filter *.png) {
        Copy-Item $p.FullName (Join-Path $stage 'scripts\Hoops\icons')
    }

    [string[]]$must = @(
        'README.txt',
        'CHANGES.txt',
        'scripts\Hoops.dll',
        'scripts\Hoops.ini',
        'scripts\Hoops\icons\seal.png',
        'scripts\Hoops\icons\seal-face.png',
        'scripts\Hoops\icons\seal-ring.png'
    )

    $missing = @()
    foreach ($m in $must) { if (-not (Test-Path (Join-Path $stage $m))) { $missing += $m } }
    if ($missing) { throw "Package is missing: $($missing -join ', ')" }

    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal

    Write-Host ""
    Write-Host ("Packaged  {0}" -f (Split-Path $zip -Leaf)) -ForegroundColor Green
    foreach ($m in $must) {
        $f = Get-Item (Join-Path $stage $m)
        Write-Host ("  {0,-38} {1,9:N0} bytes" -f $m, $f.Length) -ForegroundColor DarkGray
    }
    Write-Host ("  {0,-38} {1,9:N0} bytes" -f '(zip)', (Get-Item $zip).Length)
}
