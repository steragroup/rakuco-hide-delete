<#
  このPCの Chrome を「Chrome ブラウザ クラウド管理」に登録する（PCごとに一度だけ）

  使い方（管理者として実行した PowerShell で）:
    powershell -ExecutionPolicy Bypass -File enroll-chrome.ps1 -Token <管理コンソールで発行した登録トークン>

  登録を外すとき:
    powershell -ExecutionPolicy Bypass -File enroll-chrome.ps1 -Remove
#>
param(
  [string]$Token,
  [switch]$Mandatory,
  [switch]$Remove
)
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw '管理者として実行してください（PowerShell を右クリック →「管理者として実行」）。' }

$Key = 'HKLM:\SOFTWARE\Policies\Google\Chrome'

if ($Remove) {
  if (Test-Path $Key) {
    Remove-ItemProperty -Path $Key -Name 'CloudManagementEnrollmentToken' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $Key -Name 'CloudManagementEnrollmentMandatory' -ErrorAction SilentlyContinue
  }
  # 登録済みの印（デバイストークン）も消す
  Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Google\Chrome\Enrollment' -Name 'dmtoken' -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Google\Enrollment' -Name 'dmtoken' -ErrorAction SilentlyContinue
  Write-Host '登録トークンを削除しました。管理コンソール側でもこのブラウザを削除してください。Chrome を再起動すると反映されます。' -ForegroundColor Green
  return
}

if (-not $Token) { throw '-Token に登録トークンを指定してください。' }
$Token = $Token.Trim()

New-Item -Path $Key -Force | Out-Null
New-ItemProperty -Path $Key -Name 'CloudManagementEnrollmentToken' -Value $Token -PropertyType String -Force | Out-Null
# -Mandatory 指定時のみ: 登録に失敗したら Chrome を起動させない（ネット不調でも Chrome が使えなくなるので注意）
if ($Mandatory) {
  New-ItemProperty -Path $Key -Name 'CloudManagementEnrollmentMandatory' -Value 1 -PropertyType DWord -Force | Out-Null
}

# 起動中の Chrome を閉じる（次回起動時に登録される）
$running = Get-Process chrome -ErrorAction SilentlyContinue
if ($running) {
  Write-Host 'Chrome を終了します（開いているタブは次回起動時に復元できます）。'
  $running | Stop-Process -Force
}

Write-Host '登録トークンを設定しました。Chrome を起動し、chrome://policy の「Machine policies」に CloudManagementEnrollmentToken が出ていれば成功です。' -ForegroundColor Green
Write-Host '管理コンソールの「デバイス → Chrome → 管理対象ブラウザ」にこのPCが表示されるまで数分かかることがあります。'
