# Установщик русского автоперевода для Rat Game (Sokpop Collective)
# Ставит BepInEx 5 + XUnity.AutoTranslator и включает перевод en -> ru.
# Запуск: ПКМ по файлу -> "Выполнить с помощью PowerShell"
#   или: powershell -ExecutionPolicy Bypass -File install_ru.ps1 -GameDir "D:\Games\Rat Game"

param(
    [string]$GameDir = ""
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 1. Поиск папки игры ---
if (-not $GameDir) {
    $candidates = @(
        "C:\Program Files (x86)\Steam\steamapps\common\Rat Game",
        "C:\Program Files\Steam\steamapps\common\Rat Game",
        "D:\SteamLibrary\steamapps\common\Rat Game",
        "D:\Steam\steamapps\common\Rat Game"
    )
    $GameDir = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $GameDir -or -not (Test-Path $GameDir)) {
    Write-Host "Папка игры не найдена." -ForegroundColor Yellow
    Write-Host "Steam -> Rat Game -> ПКМ -> Управление -> Просмотр локальных файлов, скопируйте путь."
    $GameDir = Read-Host "Вставьте путь к папке игры"
}
$GameDir = $GameDir.Trim('"')
Write-Host "Папка игры: $GameDir"

# --- 2. Определяем тип сборки Unity ---
$dataDir = Get-ChildItem $GameDir -Directory -Filter "*_Data" | Select-Object -First 1
$isUnity = (Test-Path "$GameDir\UnityPlayer.dll") -and $dataDir
if (-not $isUnity) {
    Write-Host "Это не похоже на Unity-игру (нет UnityPlayer.dll / *_Data)." -ForegroundColor Red
    Write-Host "Используйте экранный переводчик game_translator.py из прошлого шага."
    exit 1
}
$isIl2cpp = Test-Path "$GameDir\GameAssembly.dll"
$isMono = Test-Path "$($dataDir.FullName)\Managed\Assembly-CSharp.dll"

if ($isIl2cpp) {
    Write-Host "Обнаружена сборка IL2CPP." -ForegroundColor Yellow
    Write-Host @"
Для IL2CPP нужен BepInEx 6 (bleeding edge) - его нельзя надёжно поставить автоматически:
  1. Скачайте 'Unity.IL2CPP-win-x64' с https://builds.bepinex.dev/projects/bepinex_be
  2. Распакуйте в папку игры и один раз запустите игру.
  3. Скачайте XUnity.AutoTranslator-BepInEx-IL2CPP-*.zip с
     https://github.com/bbepis/XUnity.AutoTranslator/releases
     и распакуйте в папку игры.
  4. Скопируйте AutoTranslatorConfig.ini из этой папки в BepInEx\config\.
Если игра падает при запуске - используйте game_translator.py.
"@
    exit 0
}
if (-not $isMono) {
    Write-Host "Не удалось определить тип сборки (Mono/IL2CPP)." -ForegroundColor Red
    exit 1
}
Write-Host "Обнаружена сборка Mono - ставим автоматически." -ForegroundColor Green

# --- 3. Скачивание релизов с GitHub ---
function Get-ReleaseAsset($repo, $include, $exclude) {
    $rels = Invoke-RestMethod "https://api.github.com/repos/$repo/releases" -Headers @{ "User-Agent" = "ratgame-ru" }
    foreach ($r in $rels) {
        if ($r.prerelease -and $repo -like "*BepInEx/BepInEx") { continue }
        foreach ($a in $r.assets) {
            if ($a.name -like $include -and (-not $exclude -or $a.name -notlike $exclude)) { return $a }
        }
    }
    throw "Не найден файл '$include' в $repo (возможно, лимит GitHub API - повторите позже)"
}

$tmp = Join-Path $env:TEMP "ratgame-ru"
New-Item -ItemType Directory -Force $tmp | Out-Null

$bep = Get-ReleaseAsset "BepInEx/BepInEx" "BepInEx_win_x64_5*.zip" $null
$xua = Get-ReleaseAsset "bbepis/XUnity.AutoTranslator" "XUnity.AutoTranslator-BepInEx-*.zip" "*IL2CPP*"

foreach ($a in @($bep, $xua)) {
    $dst = Join-Path $tmp $a.name
    Write-Host "Скачиваю $($a.name) ..."
    Invoke-WebRequest $a.browser_download_url -OutFile $dst
    Expand-Archive $dst -DestinationPath $GameDir -Force
}

# --- 4. Конфиг перевода ---
$cfgDir = "$GameDir\BepInEx\config"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
$srcCfg = Join-Path $PSScriptRoot "AutoTranslatorConfig.ini"
if (Test-Path $srcCfg) {
    Copy-Item $srcCfg "$cfgDir\AutoTranslatorConfig.ini" -Force
    Write-Host "Конфиг скопирован."
}

# --- 5. Свой словарь (необязательно) ---
$trDir = "$GameDir\BepInEx\Translation\ru\Text"
New-Item -ItemType Directory -Force $trDir | Out-Null
$srcDict = Join-Path $PSScriptRoot "_Substitutions.txt"
if (Test-Path $srcDict) { Copy-Item $srcDict "$trDir\_Substitutions.txt" -Force }

Write-Host ""
Write-Host "Готово! Запустите Rat Game. При первом запуске BepInEx может грузиться дольше." -ForegroundColor Green
Write-Host "В игре: ALT+0 - окно настроек перевода, ALT+T - вкл/выкл перевод."
Write-Host "Чтобы удалить: удалите папку BepInEx и файлы winhttp.dll, doorstop_config.ini из папки игры."
