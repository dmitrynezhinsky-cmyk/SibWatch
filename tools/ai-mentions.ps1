# Монитор упоминаний бренда в нейросетях (AEO/GEO).
#
# Что делает: задаёт список вопросов нейросети через OpenAI-совместимый API
# и проверяет, упоминается ли «Сибвоч» / SibWatch в ответе. Пишет лог в CSV.
#
# Работает с любым OpenAI-совместимым провайдером (DeepSeek, OpenAI, OpenRouter, локальный сервер).
#
# Примеры:
#   # DeepSeek (рекомендуется для проверки российской видимости)
#   $env:AI_API_KEY="sk-..."
#   powershell -ExecutionPolicy Bypass -File tools\ai-mentions.ps1 -Provider deepseek
#
#   # OpenAI (ChatGPT)
#   powershell -ExecutionPolicy Bypass -File tools\ai-mentions.ps1 -Provider openai -ApiKey "sk-..."
#
#   # Свой endpoint
#   powershell -ExecutionPolicy Bypass -File tools\ai-mentions.ps1 -BaseUrl "https://api.example.com/v1" -Model "my-model" -ApiKey "..."
#
#   # Отчёт по накопленному логу (без запросов к ИИ)
#   powershell -ExecutionPolicy Bypass -File tools\ai-mentions.ps1 -Report
param(
  [ValidateSet('deepseek','openai','custom')][string]$Provider = 'deepseek',
  [string]$BaseUrl = '',
  [string]$Model = '',
  [string]$ApiKey = $env:AI_API_KEY,
  [string]$Brand = 'Сибвоч',
  [string]$BrandAlt = 'SibWatch',
  [int]$SleepSec = 2,
  [switch]$Report,
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root        = (Resolve-Path $Root).Path
$questionsF  = Join-Path $Root 'data\ai-questions.txt'
$logF        = Join-Path $Root 'data\ai-mentions-log.csv'

function Head($m) { Write-Host ""; Write-Host ("== " + $m + " ==") -ForegroundColor Cyan }

# ---------- Режим отчёта ----------
if ($Report) {
  if (-not (Test-Path $logF)) { Write-Host "Лог не найден: $logF. Сначала запустите мониторинг." -ForegroundColor Yellow; exit 0 }
  $rows = @(Import-Csv $logF)
  Head "Итог по провайдерам / моделям"
  $rows | Group-Object provider, model | ForEach-Object {
    $tot = $_.Count
    $men = @($_.Group | Where-Object { $_.mentioned -eq '1' }).Count
    $pct = if ($tot) { [math]::Round(100 * $men / $tot) } else { 0 }
    Write-Host ("  {0,-28} упоминаний: {1}/{2} ({3}%)" -f $_.Name, $men, $tot, $pct)
  }
  Head "Итог по вопросам"
  $rows | Group-Object question | Sort-Object Name | ForEach-Object {
    $tot = $_.Count
    $men = @($_.Group | Where-Object { $_.mentioned -eq '1' }).Count
    $mark = if ($men -gt 0) { 'OK ' } else { '-- ' }
    Write-Host ("  [{0}] {1}  ({2}/{3})" -f $mark, $_.Name, $men, $tot)
  }
  $allTot = $rows.Count
  $allMen = @($rows | Where-Object { $_.mentioned -eq '1' }).Count
  Head "Всего"
  Write-Host ("  Упоминаний «{0}»: {1} из {2} ответов" -f $Brand, $allMen, $allTot) -ForegroundColor Green
  exit 0
}

# ---------- Определяем endpoint ----------
switch ($Provider) {
  'deepseek' { if (-not $BaseUrl) { $BaseUrl = 'https://api.deepseek.com/v1' }; if (-not $Model) { $Model = 'deepseek-chat' } }
  'openai'   { if (-not $BaseUrl) { $BaseUrl = 'https://api.openai.com/v1' };   if (-not $Model) { $Model = 'gpt-4o-mini' } }
}
if (-not $BaseUrl -or -not $Model) {
  Write-Host "Для -Provider custom укажите -BaseUrl и -Model." -ForegroundColor Red; exit 1
}
$endpoint = ($BaseUrl.TrimEnd('/')) + '/chat/completions'

# ---------- Вопросы ----------
if (-not (Test-Path $questionsF)) { Write-Host "Не найден файл вопросов: $questionsF" -ForegroundColor Red; exit 1 }
$questions = Get-Content $questionsF -Encoding UTF8 | Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') }

if (-not $ApiKey) {
  Head "Нужен API-ключ"
  Write-Host "Ручной режим: ключ не задан, запросы к ИИ не отправляются." -ForegroundColor Yellow
  Write-Host "Задайте ключ и повторите, например:" -ForegroundColor Yellow
  Write-Host '  $env:AI_API_KEY="sk-..."' -ForegroundColor Gray
  Write-Host '  powershell -ExecutionPolicy Bypass -File tools\ai-mentions.ps1 -Provider deepseek' -ForegroundColor Gray
  Head ("Вопросы для ручной проверки ({0} шт.) — задайте их в ChatGPT / DeepSeek / Алисе" -f @($questions).Count)
  $i = 0
  foreach ($q in $questions) { $i++; Write-Host ("  {0}. {1}" -f $i, $q) }
  Write-Host ""
  Write-Host "Результаты удобно вести в data\ai-mentions-log.csv, затем: -Report" -ForegroundColor Gray
  exit 0
}

Head "Мониторинг: $Provider / $Model"
$results = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($q in $questions) {
  $i++
  Write-Host ("  [{0}/{1}] {2}" -f $i, @($questions).Count, $q) -NoNewline
  $answer = ''
  $err = $null
  try {
    $body = @{ model = $Model; temperature = 0; messages = @(@{ role = 'user'; content = $q }) } | ConvertTo-Json -Depth 5
    $resp = Invoke-RestMethod -Uri $endpoint -Method Post -TimeoutSec 90 `
      -Headers @{ Authorization = "Bearer $ApiKey" } -ContentType 'application/json; charset=utf-8' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body))
    $answer = [string]$resp.choices[0].message.content
  } catch { $err = $_.Exception.Message }

  if ($err) { Write-Host "  (ошибка: $err)" -ForegroundColor Red; continue }

  $pos = -1
  foreach ($term in @($Brand, $BrandAlt)) {
    $idx = $answer.IndexOf($term, [StringComparison]::OrdinalIgnoreCase)
    if ($idx -ge 0 -and ($pos -lt 0 -or $idx -lt $pos)) { $pos = $idx }
  }
  $mentioned = if ($pos -ge 0) { 1 } else { 0 }
  $color = if ($mentioned) { 'Green' } else { 'Yellow' }
  Write-Host ("  -> {0}" -f $(if ($mentioned) { "УПОМИНАЕТСЯ (позиция $pos)" } else { "нет упоминания" })) -ForegroundColor $color

  $snippet = $answer
  if ($snippet.Length -gt 400) { $snippet = $snippet.Substring(0, 400) + '...' }
  $results.Add([pscustomobject]@{
    timestamp  = (Get-Date).ToString('s')
    provider   = $Provider
    model      = $Model
    question   = $q
    mentioned  = $mentioned
    position   = $pos
    answer_len = $answer.Length
    snippet    = ($snippet -replace '\s+', ' ').Trim()
  })
  if ($SleepSec -gt 0) { Start-Sleep -Seconds $SleepSec }
}

if ($results.Count -gt 0) {
  $results | Export-Csv -Path $logF -Append -NoTypeInformation -Encoding UTF8
  $men = @($results | Where-Object { $_.mentioned -eq 1 }).Count
  Head "Готово"
  Write-Host ("  Упоминаний: {0} из {1}. Лог: {2}" -f $men, $results.Count, $logF) -ForegroundColor Green
  Write-Host "  Сводка: powershell -ExecutionPolicy Bypass -File tools\ai-mentions.ps1 -Report" -ForegroundColor Gray
} else {
  Head "Запросы завершились без ответов (проверьте ключ/endpoint)." 
}
