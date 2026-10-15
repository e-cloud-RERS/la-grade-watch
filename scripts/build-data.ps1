# Downloads LA County's restaurant inspection + violation CSVs and writes a compact
# site/data/changes.json containing only facilities whose grade changed, with their
# full graded inspection history and the violations cited at each inspection.
# Runs on Windows PowerShell 5.1 and PowerShell 7 (GitHub Actions).
param(
  [string]$OutFile = (Join-Path $PSScriptRoot '..\site\data\changes.json')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName Microsoft.VisualBasic

$Agol = 'https://www.arcgis.com/sharing/rest'
$OrgId = 'RmCCgQtiZLDCtblq'
$Rank = @{ A = 3; B = 2; C = 1 }

# The County republishes each CSV quarterly, sometimes as a new item, so find the newest by title.
function Find-Dataset([string]$Title, [string]$Fallback, [string]$Type = 'CSV') {
  try {
    $q = [uri]::EscapeDataString("title:`"$Title`" AND orgid:$OrgId AND type:`"$Type`"")
    $r = Invoke-RestMethod "$Agol/search?q=$q&sortField=modified&sortOrder=desc&num=10&f=json"
    $hit = $r.results | Where-Object { $_.title -like "$Title*" } | Select-Object -First 1
    if ($hit) { return $hit }
  } catch { Write-Warning "Dataset search failed, using fallback: $_" }
  Invoke-RestMethod "$Agol/content/items/$Fallback`?f=json"
}

function Get-Csv($Item, [string]$Dir) {
  $path = Join-Path $Dir "$($Item.id).csv"
  Write-Host "Downloading $($Item.title)..."
  Invoke-WebRequest "$Agol/content/items/$($Item.id)/data" -OutFile $path -UseBasicParsing
  $path
}

# Streams rows as string arrays; returns a header-name -> column-index map via the callback's first call.
function Read-Csv([string]$Path, [scriptblock]$OnRow) {
  $p = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Path)
  $p.TextFieldType = 'Delimited'; $p.SetDelimiters(','); $p.HasFieldsEnclosedInQuotes = $true
  $h = @{}; $i = 0
  foreach ($name in $p.ReadFields()) { $h[$name.Trim().ToUpper()] = $i++ }
  while (-not $p.EndOfData) { & $OnRow $p.ReadFields() $h }
  $p.Close()
}

# RECORD ID -> "lat,lon" from the County's facility inventory (a feature service, paged 1000 rows at a time).
function Get-Coordinates($Item) {
  Write-Host "Downloading coordinates from $($Item.title)..."
  $coords = @{}
  $base = "$($Item.url)/0/query?where=1%3D1&outFields=RECORD_ID,LATITUDE,LONGITUDE&returnGeometry=false&orderByFields=ObjectId&f=json"
  $offset = 0
  do {
    $r = Invoke-RestMethod "$base&resultOffset=$offset&resultRecordCount=1000"
    foreach ($ft in $r.features) {
      $a = $ft.attributes
      if ($a.RECORD_ID -and $a.LATITUDE -and $a.LONGITUDE) {
        $coords[$a.RECORD_ID.Trim()] = ([math]::Round([double]$a.LATITUDE, 5)).ToString([Globalization.CultureInfo]::InvariantCulture) + ',' +
                                       ([math]::Round([double]$a.LONGITUDE, 5)).ToString([Globalization.CultureInfo]::InvariantCulture)
      }
    }
    $offset += $r.features.Count
  } while ($r.exceededTransferLimit -and $r.features.Count -gt 0)
  Write-Host "$($coords.Count) facilities with coordinates."
  $coords
}

function J([object]$v) {
  if ($null -eq $v) { return 'null' }
  if ($v -is [int] -or $v -is [double]) { return [string]$v }
  $s = [string]$v
  $sb = New-Object System.Text.StringBuilder ($s.Length + 2)
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    switch ($ch) {
      '"' { [void]$sb.Append('\"') } '\' { [void]$sb.Append('\\') }
      default { if ([int]$ch -lt 32) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) } else { [void]$sb.Append($ch) } }
    }
  }
  $sb.Append('"').ToString()
}

function ToIso([string]$mdy) {
  $p = $mdy.Trim().Split(' ')[0].Split('/')
  if ($p.Count -ne 3) { return '' }
  '{0}-{1}-{2}' -f $p[2], $p[0].PadLeft(2, '0'), $p[1].PadLeft(2, '0')
}

function TitleCase([string]$s) { (Get-Culture).TextInfo.ToTitleCase($s.Trim().ToLower()) }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("lagw-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
  $inspItem = Find-Dataset 'Environmental Health Restaurant and Market Inspections' '19b6607ac82c4512b10811870975dbdc'
  $violItem = Find-Dataset 'Environmental Health Restaurant and Market Violations' '5eaea9f89b7549ee841da7617d3a9cba'
  $inspCsv = Get-Csv $inspItem $tmp
  $violCsv = Get-Csv $violItem $tmp
  $coords = @{}
  try {
    $coords = Get-Coordinates (Find-Dataset 'Environmental Health Restaurant and Market Inventory' '6715145614f34cce8ac7ded3d8b3a508' 'Feature Service')
  } catch { Write-Warning "Coordinates unavailable; 'Near me' will be disabled: $_" }

  # ---- Inspections, grouped by program (RECORD ID): grades are issued per program ----
  Write-Host 'Reading inspections...'
  $programs = @{}
  $services = New-Object System.Collections.Generic.List[string]
  $script:total = 0
  Read-Csv $inspCsv {
    param($f, $h)
    $script:total++
    $grade = $f[$h['GRADE']].Trim().ToUpper()
    if (-not $Rank.ContainsKey($grade)) { return }
    $svc = TitleCase $f[$h['SERVICE DESCRIPTION']]
    $si = $services.IndexOf($svc); if ($si -lt 0) { $services.Add($svc); $si = $services.Count - 1 }
    $score = 0; $hasScore = [int]::TryParse($f[$h['SCORE']].Trim(), [ref]$score)
    $key = $f[$h['RECORD ID']].Trim()
    if (-not $programs.ContainsKey($key)) { $programs[$key] = New-Object System.Collections.Generic.List[object] }
    $programs[$key].Add([pscustomobject]@{
      date = ToIso $f[$h['ACTIVITY DATE']]; grade = $grade; score = $(if ($hasScore) { $score } else { $null })
      svc = $si; serial = $f[$h['SERIAL NUMBER']].Trim()
      name = $f[$h['FACILITY NAME']].Trim(); addr = $f[$h['FACILITY ADDRESS']].Trim()
      city = $f[$h['FACILITY CITY']].Trim(); zip = $f[$h['FACILITY ZIP']].Trim(); pe = $f[$h['PE DESCRIPTION']].Trim()
    })
  }

  # Keep only programs with at least one grade change.
  $changed = New-Object System.Collections.Generic.List[object]
  $serials = New-Object 'System.Collections.Generic.HashSet[string]'
  $changeCount = 0
  # Every graded facility with its grade/score history, so users can watch places that haven't changed.
  $facilities = New-Object System.Collections.Generic.List[string]
  foreach ($key in $programs.Keys) {
    $list = @($programs[$key] | Sort-Object date, serial)
    $l = $list[-1]
    $hist = foreach ($x in $list) { '["' + $x.date + '","' + $x.grade + '",' + $(if ($null -eq $x.score) { 'null' } else { $x.score }) + ']' }
    $facilities.Add('[' + (J $key) + ',' + (J $l.name) + ',' + (J $l.addr) + ',' + (J $l.city) + ',' + (J $l.zip) + ',[' + ($hist -join ',') + ']]')
    $n = 0
    for ($k = 1; $k -lt $list.Count; $k++) { if ($list[$k].grade -ne $list[$k - 1].grade) { $n++ } }
    if ($n -eq 0) { continue }
    $changeCount += $n
    $changed.Add([pscustomobject]@{ key = $key; list = $list })
    foreach ($x in $list) { [void]$serials.Add($x.serial) }
  }
  Write-Host "$script:total inspections, $($programs.Count) graded programs, $changeCount grade changes in $($changed.Count) programs."

  # ---- Violations for those inspections only ----
  Write-Host 'Reading violations...'
  $viol = @{}
  $codes = @{}
  Read-Csv $violCsv {
    param($f, $h)
    $serial = $f[$h['SERIAL NUMBER']].Trim()
    if (-not $serials.Contains($serial)) { return }
    $code = $f[$h['VIOLATION CODE']].Trim()
    if (-not $codes.ContainsKey($code)) { $codes[$code] = $f[$h['VIOLATION DESCRIPTION']].Trim() }
    $pts = 0.0; [void][double]::TryParse($f[$h['POINTS']].Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$pts)
    if (-not $viol.ContainsKey($serial)) { $viol[$serial] = New-Object System.Collections.Generic.List[string] }
    $viol[$serial].Add('[' + (J $code) + ',' + [string]([math]::Round($pts, 2)) + ']')
  }

  # ---- Write JSON ----
  Write-Host 'Writing JSON...'
  $sb = New-Object System.Text.StringBuilder (4MB)
  [void]$sb.Append('{"generated":').Append((J ([DateTime]::UtcNow.ToString('o'))))
  [void]$sb.Append(',"source":{"inspections":').Append((J $inspItem.title)).Append(',"inspectionsModified":').Append([string]$inspItem.modified)
  [void]$sb.Append(',"violations":').Append((J $violItem.title)).Append(',"violationsModified":').Append([string]$violItem.modified).Append('}')
  [void]$sb.Append(',"stats":{"inspections":').Append($script:total).Append(',"programs":').Append($programs.Count).Append('}')
  [void]$sb.Append(',"services":[').Append((($services | ForEach-Object { J $_ }) -join ',')).Append(']')
  [void]$sb.Append(',"codes":{').Append((($codes.Keys | Sort-Object | ForEach-Object { (J $_) + ':' + (J $codes[$_]) }) -join ',')).Append('}')
  [void]$sb.Append(',"programs":[')
  $first = $true
  foreach ($p in $changed) {
    $last = $p.list[-1]
    if (-not $first) { [void]$sb.Append(',') }; $first = $false
    [void]$sb.Append('[').Append((J $p.key)).Append(',').Append((J $last.name)).Append(',').Append((J $last.addr)).Append(',')
    [void]$sb.Append((J $last.city)).Append(',').Append((J $last.zip)).Append(',').Append((J $last.pe)).Append(',[')
    $ins = foreach ($x in $p.list) {
      $v = if ($viol.ContainsKey($x.serial)) { $viol[$x.serial] -join ',' } else { '' }
      '[' + (J $x.date) + ',' + (J $x.grade) + ',' + (J $x.score) + ',' + $x.svc + ',' + (J $x.serial) + ',[' + $v + ']]'
    }
    $ll = if ($coords.ContainsKey($p.key)) { $coords[$p.key] } else { 'null,null' }
    [void]$sb.Append(($ins -join ',')).Append('],').Append($ll).Append(']')
  }
  [void]$sb.Append(']}')

  $out = [IO.Path]::GetFullPath($OutFile)
  New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
  [IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
  Write-Host ("Wrote {0} ({1:N1} MB)" -f $out, ((Get-Item $out).Length / 1MB))

  $facOut = Join-Path (Split-Path $out) 'facilities.json'
  [IO.File]::WriteAllText($facOut, '{"facilities":[' + ($facilities -join ',') + ']}', (New-Object System.Text.UTF8Encoding $false))
  Write-Host ("Wrote {0} ({1:N1} MB)" -f $facOut, ((Get-Item $facOut).Length / 1MB))
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
