# Генерирует JSON-LD (Service + FAQPage + BreadcrumbList) для новой услуги.
# Пример:
#   powershell -ExecutionPolicy Bypass -File tools\new-service-schema.ps1 `
#     -Name "Полировка часов" -Slug "polirovka-chasov" `
#     -Description "Полировка корпуса и браслета часов в Новосибирске" `
#     -Faq "Сколько стоит полировка?|||Зависит от состояния корпуса, уточняется после осмотра.","Сохраняется ли покрытие?|||Да, при необходимости восстанавливаем родиевое покрытие."
param(
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$true)][string]$Slug,
  [string]$Description = "",
  [string]$ServiceType = "",
  [string[]]$Faq = @(),
  [string]$Domain = "https://remont-chasov-nsk.ru",
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'

$url = "$Domain/$Slug.html"
$faqItems = @()
foreach ($q in $Faq) {
  $parts = $q -split '\|\|\|'
  if ($parts.Count -ge 2) {
    $faqItems += [ordered]@{
      '@type' = 'Question'
      name = $parts[0].Trim()
      acceptedAnswer = [ordered]@{ '@type' = 'Answer'; text = $parts[1].Trim() }
    }
  }
}

$graph = @(
  [ordered]@{
    '@type' = 'Service'
    '@id' = "$url#service"
    name = $Name
    serviceType = if ($ServiceType) { $ServiceType } else { $Name }
    description = $Description
    provider = [ordered]@{
      '@type' = 'LocalBusiness'
      name = 'Сервисный центр «Сибвоч»'
      telephone = '+7-383-211-92-80'
      address = [ordered]@{ '@type' = 'PostalAddress'; streetAddress = 'ул. Писарева, 60'; addressLocality = 'Новосибирск'; addressCountry = 'RU' }
    }
    areaServed = [ordered]@{ '@type' = 'City'; name = 'Новосибирск' }
  },
  [ordered]@{
    '@type' = 'BreadcrumbList'
    itemListElement = @(
      [ordered]@{ '@type' = 'ListItem'; position = 1; name = 'Ремонт часов в Новосибирске'; item = "$Domain/" },
      [ordered]@{ '@type' = 'ListItem'; position = 2; name = $Name; item = $url }
    )
  }
)
if ($faqItems.Count -gt 0) {
  $graph += [ordered]@{ '@type' = 'FAQPage'; '@id' = "$url#faq"; mainEntity = $faqItems }
}

$obj = [ordered]@{ '@context' = 'https://schema.org'; '@graph' = $graph }
$json = $obj | ConvertTo-Json -Depth 20

$outDir = Join-Path $Root 'tools\out'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outFile = Join-Path $outDir "$Slug.jsonld"
[IO.File]::WriteAllText($outFile, $json, (New-Object Text.UTF8Encoding($false)))

# самопроверка: получилось ли валидно
try { $null = $json | ConvertFrom-Json; Write-Host "JSON-LD валиден, сохранён: $outFile" -ForegroundColor Green }
catch { Write-Host "Ошибка генерации JSON-LD" -ForegroundColor Red; exit 1 }
Write-Host ""
Write-Host "Вставьте в <head> новой страницы:" -ForegroundColor Cyan
Write-Host '<script type="application/ld+json">'
Write-Host $json
Write-Host '</script>'
