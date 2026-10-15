# Local preview of the site/ folder at http://localhost:8765/
# Run scripts/build-data.ps1 first so site/data/changes.json exists.
$port = 8765
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'site'))
$types = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript'; '.json' = 'application/json';
            '.webmanifest' = 'application/manifest+json'; '.png' = 'image/png'; '.css' = 'text/css' }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "LA County Grade Watch running at http://localhost:$port/"
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
  if ($rel -eq '') { $rel = 'index.html' }
  $path = [IO.Path]::GetFullPath((Join-Path $root $rel))
  if ($path.StartsWith($root) -and (Test-Path $path -PathType Leaf)) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $ext = [IO.Path]::GetExtension($path).ToLower()
    $ctx.Response.ContentType = $(if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' })
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  } else {
    $ctx.Response.StatusCode = 404
  }
  $ctx.Response.Close()
}
