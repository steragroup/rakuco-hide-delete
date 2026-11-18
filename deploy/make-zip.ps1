<#
  職員配布用の zip を作る（管理者用）

  使い方:
    powershell -ExecutionPolicy Bypass -File deploy\make-zip.ps1 -RegPath <管理コンソールでダウンロードした .reg>

  出力: dist\ラクコ拡張インストール.zip（.reg 入り。Git の対象外。社外に出さない）
#>
param([Parameter(Mandatory)][string]$RegPath)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Deploy = Join-Path $Root 'deploy'
if (-not (Test-Path $RegPath)) { throw ".reg が見つかりません: $RegPath" }
$regText = Get-Content $RegPath -Raw
if ($regText -notmatch 'CloudManagementEnrollmentToken') { throw 'この .reg には CloudManagementEnrollmentToken が入っていません。管理コンソールの「管理対象ブラウザ → 登録」でダウンロードしたものを指定してください。' }

$Dist = Join-Path $Root 'dist'
$Stage = Join-Path $Dist 'ラクコ拡張インストール'
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force $Stage | Out-Null
Copy-Item (Join-Path $Deploy 'ラクコ拡張インストール.cmd'), (Join-Path $Deploy 'install.ps1'), (Join-Path $Deploy '使い方.txt') $Stage
Copy-Item $RegPath (Join-Path $Stage 'chrome-enrollment.reg')

$Zip = Join-Path $Dist 'ラクコ拡張インストール.zip'
if (Test-Path $Zip) { Remove-Item $Zip -Force }
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Zip
Remove-Item $Stage -Recurse -Force
Write-Host "作成しました: $Zip" -ForegroundColor Green
Write-Host '社内の共有フォルダなど、関係者だけが見られる場所で配ってください。'
