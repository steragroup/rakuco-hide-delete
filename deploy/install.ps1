<#
  ラクコ 削除ボタン非表示 拡張機能 — PC への導入（ダブルクリック用）

  「ラクコ拡張インストール.cmd」から呼ばれる。やること:
    1. 同じフォルダの .reg（管理コンソールで発行した登録トークン入り）を取り込む（管理者権限）
    2. 本人に確認してから、いつもの Chrome だけを再起動する（タブは復元）
       ※ --user-data-dir を指定して別に動いている Chrome（自動作業用など）には触らない
    3. 登録・設定の受け取り・拡張機能のインストールを確認して結果を表示する

  -CheckOnly : 1・2 をせず、3 の確認だけ行う
  -Quiet     : 画面（メッセージボックス）を出さず、コンソールに表示する（動作確認用）
#>
param([switch]$CheckOnly, [switch]$Quiet)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$ExtId = 'ljjjkbcejfijcmmhjjbgpmcoaibpfpfj'
$Title = 'ラクコ 拡張機能の導入'
$Here = $PSScriptRoot
$LogFile = Join-Path $env:TEMP 'rakuco-extension-install.log'

function Log($m) { $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $m; Write-Host $line; Add-Content -Path $LogFile -Value $line -Encoding UTF8 }
function Msg($text, $buttons = 'OK', $icon = 'Information') {
  if ($Quiet) { Write-Host "[画面表示] $text"; return 'OK' }
  # 他のウィンドウの後ろに隠れないよう、最前面のフォームを親にする
  $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false; WindowState = 'Minimized' }
  try { [System.Windows.Forms.MessageBox]::Show($owner, $text, $Title, $buttons, $icon) } finally { $owner.Dispose() }
}

# 実行中ユーザー（昇格しても、元のユーザーの Chrome を対象にする）
$UserLocalAppData = if ($env:RAKUCO_USER_LOCALAPPDATA) { $env:RAKUCO_USER_LOCALAPPDATA } else { $env:LOCALAPPDATA }
$UserName = if ($env:RAKUCO_USER_NAME) { $env:RAKUCO_USER_NAME } else { $env:USERNAME }
$DefaultUserData = Join-Path $UserLocalAppData 'Google\Chrome\User Data'

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# いつもの Chrome（既定のデータフォルダ）のブラウザ本体プロセス
function Get-DefaultChromeBrowser {
  Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object {
    $cl = $_.CommandLine
    $owner = (Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue).User
    $cl -and $cl -notmatch '--type=' -and $owner -eq $UserName -and (
      $cl -notmatch '--user-data-dir' -or
      $cl -match [regex]::Escape($DefaultUserData)
    )
  }
}

function Stop-ProcessTree([int]$ProcId) {
  $all = Get-CimInstance Win32_Process
  $kids = $all | Where-Object { $_.ParentProcessId -eq $ProcId }
  foreach ($k in $kids) { Stop-ProcessTree $k.ProcessId }
  Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
}

function Get-Status {
  $s = [ordered]@{}
  $s['登録トークン'] = [bool](Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name CloudManagementEnrollmentToken -ErrorAction SilentlyContinue)
  $s['会社の管理下に登録'] = [bool]((Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Google\Enrollment' -Name dmtoken -ErrorAction SilentlyContinue) -or
                               (Get-ItemProperty 'HKLM:\SOFTWARE\Google\Chrome\Enrollment' -Name dmtoken -ErrorAction SilentlyContinue))
  $pol = Join-Path $DefaultUserData 'Policy\Machine Level User Cloud Policy'
  $s['拡張機能の設定を受信'] = (Test-Path $pol) -and ([IO.File]::ReadAllText($pol, [Text.Encoding]::ASCII).Contains($ExtId))
  $installed = @(Get-ChildItem $DefaultUserData -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "Extensions\$ExtId" } | Where-Object { Test-Path $_ })
  $s['拡張機能のインストール'] = $installed.Count -gt 0
  $s['_profiles'] = $installed.Count
  return $s
}

function Format-Status($s) {
  ($s.Keys | Where-Object { $_ -notlike '_*' } | ForEach-Object { '{0} {1}' -f $(if ($s[$_]) { '✔' } else { '✖' }), $_ }) -join "`r`n"
}

try {
  Log "開始（CheckOnly=$CheckOnly）"

  if (-not $CheckOnly) {
    # --- 1. .reg の取り込み ---
    $reg = Get-ChildItem $Here -Filter *.reg | Select-Object -First 1
    if (-not $reg) {
      Msg "このフォルダに登録用の .reg ファイルがありません。`r`n配布元（情シス・管理本部）に連絡してください。" 'OK' 'Error' | Out-Null
      exit 1
    }
    if (-not (Test-Admin)) { throw '管理者権限で実行されていません。' }
    Log "取り込み: $($reg.Name)"
    $p = Start-Process -FilePath "$env:WINDIR\System32\reg.exe" -ArgumentList @('import', "`"$($reg.FullName)`"") -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) { throw ".reg の取り込みに失敗しました（終了コード $($p.ExitCode)）。" }
    Log '.reg 取り込み完了'

    # --- 2. Chrome の再起動 ---
    $browser = @(Get-DefaultChromeBrowser)
    $chromeExe = $null
    if ($browser.Count -gt 0) {
      $ans = Msg ("Chrome を再起動します。`r`n`r`n入力途中の内容（送信前のメッセージ・フォームなど）は消えることがあります。保存・送信してから「OK」を押してください。`r`n開いていたタブは再起動後に戻ります。") 'OKCancel' 'Warning'
      if ($ans -ne 'OK') {
        Log '再起動を本人が取り消し'
        Msg "登録は済みました。`r`nChrome を次に起動し直したときに拡張機能が入ります（アドレスバーに chrome://restart と入力して Enter でも可）。" | Out-Null
        exit 0
      }
      $chromeExe = $browser[0].ExecutablePath
      foreach ($b in $browser) { Log "Chrome 終了 PID=$($b.ProcessId)"; Stop-ProcessTree $b.ProcessId }
      Start-Sleep -Seconds 3
    }
    if (-not $chromeExe) {
      $chromeExe = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                     (Join-Path $UserLocalAppData 'Google\Chrome\Application\chrome.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $chromeExe) { throw 'chrome.exe が見つかりません。' }

    # 昇格した権限のまま Chrome を起動しないよう、エクスプローラー経由（通常ユーザー権限）で起動する
    $launcher = Join-Path $UserLocalAppData 'Temp\rakuco-start-chrome.cmd'
    Set-Content -Path $launcher -Value "@start `"`" `"$chromeExe`" --restore-last-session" -Encoding Default
    Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList "`"$launcher`""
    Log "Chrome 再起動: $chromeExe"
  }

  # --- 3. 確認（最大5分待つ） ---
  $deadline = (Get-Date).AddMinutes($(if ($CheckOnly) { 0 } else { 5 }))
  do {
    $s = Get-Status
    if ($s['拡張機能のインストール']) { break }
    Start-Sleep -Seconds 10
  } while ((Get-Date) -lt $deadline)

  $summary = Format-Status $s
  Log ($summary -replace "`r`n", ' / ')
  if ($s['拡張機能のインストール']) {
    Msg "導入が完了しました。`r`n`r`n$summary`r`n`r`nラクコの利用者一覧で「削除する」が表示されなくなります。" | Out-Null
    exit 0
  } else {
    Msg ("まだ拡張機能が入っていません。`r`n`r`n$summary`r`n`r`n数分おいて Chrome をもう一度再起動（chrome://restart）しても入らない場合は、配布元に連絡してください。`r`n記録: $LogFile") 'OK' 'Warning' | Out-Null
    exit 2
  }
} catch {
  Log "エラー: $($_.Exception.Message)"
  Msg ("エラーで止まりました。`r`n`r`n$($_.Exception.Message)`r`n`r`n記録: $LogFile") 'OK' 'Error' | Out-Null
  exit 1
}
