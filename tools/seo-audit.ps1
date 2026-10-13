# SEO/GEO-AUDIT для лендинга SibWatch
# Проверяет страницы по чек-листу GEO/AEO.
# Запуск:  powershell -ExecutionPolicy Bypass -File tools\seo-audit.ps1
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path

function Ok($m)   { Write-Host ("  [OK]   " + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ("  [!]    " + $m) -ForegroundColor Yellow }
function Bad($m)  { Write-Host ("  [X]    " + $m) -ForegroundColor Red }
function Head($m) { Write-Host ""; Write-Host ("== " + $m + " ==") -ForegroundColor Cyan }

$htmlFiles = Get-ChildItem $Root -Filter *.html -File | Sort-Object Name
$allText = @{}
foreach ($f in $htmlFiles) { $allText[$f.Name] = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) }

Head "Индексация и базовая разметка"
foreach ($f in $htmlFiles) {
  $h = $allText[$f.Name]
  if ($h -match 'name="robots"[^>]*noindex') { Bad ("$($f.Name): есть noindex — страница закрыта от роботов!") }
  else { Ok ("$($f.Name): noindex отсутствует") }
  if ($h -match '<link\s+rel="canonical"') { Ok ("$($f.Name): canonical есть") } else { Warn ("$($f.Name): нет canonical") }
  if ($h -match '<meta\s+name="viewport"') { } else { Warn ("$($f.Name): нет viewport") }
}

Head "Заголовки (title / description / H1)"
foreach ($f in $htmlFiles) {
  $h = $allText[$f.Name]
  $t = [regex]::Match($h, '(?is)<title>(.*?)</title>').Groups[1].Value.Trim()
  $d = [regex]::Match($h, '(?is)<meta\s+name="description"\s+content="([^"]*)"').Groups[1].Value.Trim()
  $h1s = [regex]::Matches($h, '(?is)<h1[^>]*>(.*?)</h1>')
  $h1 = ($h1s | ForEach-Object { ($_.Groups[1].Value -replace '<[^>]+>','').Trim() }) -join ' | '
  $tlen = $t.Length; $dlen = $d.Length
  $tState = if ($tlen -ge 30 -and $tlen -le 70) { 'OK' } else { 'проверь длину' }
  $dState = if ($dlen -ge 70 -and $dlen -le 180) { 'OK' } else { 'проверь длину' }
  Write-Host ("  $($f.Name)")
  Write-Host ("      title ($tlen) [$tState]: $t")
  Write-Host ("      desc  ($dlen) [$dState]")
  if ($h1s.Count -eq 1) { Write-Host ("      H1 (1): $h1") } else { Warn ("      H1: найдено $($h1s.Count) (должен быть ровно 1)") }
}

Head "Schema.org (JSON-LD)"
foreach ($f in $htmlFiles) {
  $h = $allText[$f.Name]
  $blocks = [regex]::Matches($h, '(?is)<script type="application/ld\+json">(.*?)</script>')
  if ($blocks.Count -eq 0) { Bad ("$($f.Name): JSON-LD не найден"); continue }
  $types = New-Object System.Collections.Generic.List[string]
  $bad = 0
  foreach ($b in $blocks) {
    try { $null = $b.Groups[1].Value.Trim() | ConvertFrom-Json }
    catch { $bad++; continue }
    [regex]::Matches($b.Groups[1].Value, '"@type"\s*:\s*(?:"([^"]+)"|\[([^\]]+)\])') | ForEach-Object {
      if ($_.Groups[1].Success) { $types.Add($_.Groups[1].Value) }
      else { [regex]::Matches($_.Groups[2].Value, '"([^"]+)"') | ForEach-Object { $types.Add($_.Groups[1].Value) } }
    }
  }
  if ($bad -gt 0) { Bad ("$($f.Name): $bad блок(ов) JSON-LD не парсятся") }
  else { Ok ("$($f.Name): JSON-LD валиден, типы: " + (($types | Sort-Object -Unique) -join ', ')) }
}

Head "Единый NAP (телефоны по всем страницам)"
$phones = @{}
foreach ($f in $htmlFiles) {
  [regex]::Matches($allText[$f.Name], '\+7\s?\(?383\)?[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}') | ForEach-Object {
    $p = ($_.Value -replace '[^\d\+]',''); if (-not $phones.ContainsKey($p)) { $phones[$p] = @() }; $phones[$p] += $f.Name
  }
}
foreach ($p in $phones.Keys) { Write-Host ("  $p  ->  " + (($phones[$p] | Sort-Object -Unique) -join ', ')) }
if (($phones.Keys | Measure-Object).Count -le 3) { Ok "телефонов немного, проверь их совпадение с Яндекс.Бизнес и 2GIS" } else { Warn "много разных телефонов — сверь с карточками" }

Head "Изображения: alt и наличие файлов"
foreach ($f in $htmlFiles) {
  $h = $allText[$f.Name]
  $imgs = [regex]::Matches($h, '(?is)<img\b[^>]*>')
  $noalt = 0; $missing = 0
  foreach ($img in $imgs) {
    $tag = $img.Value
    if ($tag -notmatch 'alt="[^"]*"') { $noalt++ }
    $src = [regex]::Match($tag, 'src="([^"]+)"').Groups[1].Value
    if ($src -and $src -notmatch '^https?:') {
      $path = Join-Path $Root ($src -replace '/','\')
      if (-not (Test-Path $path)) { $missing++ ; Warn ("$($f.Name): нет файла $src") }
    }
  }
  if ($noalt -eq 0 -and $missing -eq 0) { Ok ("$($f.Name): $($imgs.Count) изображений, все с alt и на месте") }
  elseif ($noalt -gt 0) { Warn ("$($f.Name): $noalt изображений без alt") }
}

Head "Контент в HTML (а не в JS)"
foreach ($f in $htmlFiles) {
  $h = $allText[$f.Name]
  $visible = [regex]::Replace($h, '(?is)<script.*?</script>|<style.*?</style>', '')
  $text = [regex]::Replace($visible, '(?is)<[^>]+>', ' ')
  $text = ($text -replace '\s+',' ').Trim()
  $words = ($text -split ' ').Count
  if ($words -ge 300) { Ok ("$($f.Name): ~$words слов в HTML") } else { Warn ("$($f.Name): только ~$words слов — мало для цитирования ИИ") }
}

Head "robots.txt и sitemap.xml"
$robotsPath = Join-Path $Root 'robots.txt'
if (Test-Path $robotsPath) {
  $r = [IO.File]::ReadAllText($robotsPath, [Text.Encoding]::UTF8)
  foreach ($bot in @('GPTBot','OAI-SearchBot','PerplexityBot','YandexBot','Bingbot')) {
    if ($r -match $bot) { Ok "robots.txt: $bot разрешён" } else { Warn "robots.txt: нет правила для $bot" }
  }
  if ($r -match 'Sitemap:\s*\S+') { Ok "robots.txt: sitemap указан" } else { Warn "robots.txt: sitemap не указан" }
} else { Bad "robots.txt не найден" }

$smPath = Join-Path $Root 'sitemap.xml'
if (Test-Path $smPath) {
  $sm = [IO.File]::ReadAllText($smPath, [Text.Encoding]::UTF8)
  $locs = [regex]::Matches($sm, '<loc>([^<]+)</loc>') | ForEach-Object { $_.Groups[1].Value }
  Ok "sitemap.xml: $($locs.Count) URL"
  foreach ($f in $htmlFiles) {
    $isIndex = ($f.Name -eq 'index.html')
    $hit = $locs | Where-Object { ($isIndex -and $_ -match '/$') -or ($_ -match [regex]::Escape($f.Name)) }
    if ($hit) { } else { Warn "sitemap.xml: нет URL для $($f.Name)" }
  }
} else { Bad "sitemap.xml не найден" }

Head "Свежесть цен (заглушки)"
foreach ($f in $htmlFiles) {
  $h = $allText[$f.Name]
  $n = ([regex]::Matches($h, 'class="price-todo"')).Count
  if ($n -gt 0) { Warn "$($f.Name): $n цен-заглушек — замените на актуальные" }
}
Write-Host ""
Write-Host "Аудит завершён." -ForegroundColor Cyan
