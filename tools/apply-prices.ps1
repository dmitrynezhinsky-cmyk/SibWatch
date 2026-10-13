# Применяет цены из data\prices.json к таблицам на страницах лендинга.
# Заменяет заглушки вида "от ___ ₽" на реальные значения и проверяет свежесть прайса.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\apply-prices.ps1
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [int]$StaleDays = 180
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path
$pricesPath = Join-Path $Root 'data\prices.json'
if (-not (Test-Path $pricesPath)) { Write-Host "Не найден data\prices.json" -ForegroundColor Red; exit 1 }

$data = [IO.File]::ReadAllText($pricesPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$currency = if ($data.currency) { $data.currency } else { '₽' }

function Ok($m)   { Write-Host ("  [OK]  " + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ("  [!]   " + $m) -ForegroundColor Yellow }

# --- Свежесть прайса ---
if ($data.updated) {
  try {
    $upd = [datetime]::Parse($data.updated)
    $age = ([datetime]::Now - $upd).Days
    if ($age -gt $StaleDays) { Warn "прайс обновлялся $age дней назад (порог $StaleDays). Обновите data\prices.json" }
    else { Ok "прайс свежий: обновлён $($data.updated) ($age дн. назад)" }
  } catch { Warn "не удалось прочитать поле updated: $($data.updated)" }
}

$items = @{}
foreach ($prop in $data.items.PSObject.Properties) { $items[$prop.Name] = [string]$prop.Value }
$missing = New-Object System.Collections.Generic.List[string]
$applied = 0

$htmlFiles = Get-ChildItem $Root -Filter *.html -File | Sort-Object Name
foreach ($f in $htmlFiles) {
  $h = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
  $orig = $h
  foreach ($key in $items.Keys) {
    $val = $items[$key]
    if ([string]::IsNullOrWhiteSpace($val)) { if (-not $missing.Contains($key)) { $missing.Add($key) }; continue }
    $priceText = if ($val -match '₽') { $val } else { "от $val $currency" }
    # строка таблицы целиком одной строкой => .*? не переходит на другую строку
    $pattern = '(<tr>.*?' + [regex]::Escape($key) + '.*?class="price-todo">)[^<]*(</span>)'
    $new = [regex]::Replace($h, $pattern, ('${1}' + $priceText + '${2}'))
    if ($new -ne $h) { $applied++; $h = $new }
  }

  # убираем подсказку-заглушку, если в таблицах не осталось незаполненных цен
  $hintPattern = '\r?\n\s*<p class="form__hint">[^<]*<span class="price-todo">[^<]*</span>[^<]*</p>'
  $hasHint = [regex]::IsMatch($h, $hintPattern)
  $total = ([regex]::Matches($h, 'class="price-todo"')).Count
  $tableLeft = $total - $(if ($hasHint) { 1 } else { 0 })
  if ($hasHint -and $tableLeft -eq 0) { $h = [regex]::Replace($h, $hintPattern, '') }

  if ($h -ne $orig) { [IO.File]::WriteAllText($f.FullName, $h, (New-Object Text.UTF8Encoding($false))); Ok "$($f.Name): цены обновлены" }
}

Write-Host ""
if ($applied -eq 0) { Warn "не применено ни одной цены (все значения в prices.json пустые или не найдены совпадения)" }
if ($missing.Count -gt 0) {
  Write-Host "Не заполнены цены (строки остаются заглушками):" -ForegroundColor Yellow
  $missing | Sort-Object | ForEach-Object { Write-Host "   - $_" }
}
Write-Host "Готово." -ForegroundColor Cyan
