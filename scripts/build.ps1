<#
  ラクコ削除ボタン非表示 拡張機能のビルド（GitHub Pages 配布用）

  使い方（リポジトリのフォルダで）:
    初回   : powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -PagesUrl https://<GitHubユーザー名>.github.io/<リポジトリ名>/
    2回目～: powershell -ExecutionPolicy Bypass -File scripts\build.ps1

  やること:
    1. extension\ を一時フォルダにコピーし、manifest.json に update_url を入れる
    2. Chrome で .crx に固める（秘密鍵 keys\rakuco-hide-delete.pem が無ければ新規作成、あれば再利用）
    3. docs\ に rakuco-hide-delete.crx と update.xml を書き出す
    4. 拡張機能 ID を表示し、docs\extension-id.txt に保存する
#>
param(
  [string]$PagesUrl,
  [string]$ChromePath
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Name = 'rakuco-hide-delete'
$ConfigFile = Join-Path $Root 'scripts\pages-url.txt'
$KeyDir = Join-Path $Root 'keys'
$KeyFile = Join-Path $KeyDir "$Name.pem"
$Docs = Join-Path $Root 'docs'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# --- GitHub Pages の URL ---
if ($PagesUrl) {
  if ($PagesUrl -notmatch '^https://') { throw "PagesUrl は https:// で始めてください: $PagesUrl" }
  if (-not $PagesUrl.EndsWith('/')) { $PagesUrl += '/' }
  [IO.File]::WriteAllText($ConfigFile, $PagesUrl, $Utf8NoBom)
} elseif (Test-Path $ConfigFile) {
  $PagesUrl = (Get-Content $ConfigFile -Raw).Trim()
} else {
  throw '初回は -PagesUrl https://<GitHubユーザー名>.github.io/<リポジトリ名>/ を指定してください。'
}
$UpdateUrl = "${PagesUrl}update.xml"
$CrxUrl = "${PagesUrl}$Name.crx"

# --- Chrome の場所 ---
if (-not $ChromePath) {
  $ChromePath = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $ChromePath) { throw 'chrome.exe が見つかりません。-ChromePath で指定してください。' }

# --- 一時フォルダに拡張機能をコピーして update_url を入れる ---
$Work = Join-Path ([IO.Path]::GetTempPath()) ("$Name-build-" + [guid]::NewGuid().ToString('N'))
$Src = Join-Path $Work $Name
New-Item -ItemType Directory -Force $Src | Out-Null
Copy-Item (Join-Path $Root 'extension\*') $Src -Recurse

$ManifestPath = Join-Path $Src 'manifest.json'
$manifest = [IO.File]::ReadAllText($ManifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$Version = $manifest.version
$manifest | Add-Member -NotePropertyName update_url -NotePropertyValue $UpdateUrl -Force
[IO.File]::WriteAllText($ManifestPath, ($manifest | ConvertTo-Json -Depth 10), $Utf8NoBom)

# --- Chrome で .crx にする（起動中の Chrome と混ざらないよう専用プロファイルを使う） ---
$TempProfile = Join-Path $Work 'profile'
$chromeArgs = @("--user-data-dir=`"$TempProfile`"", '--no-message-box', "--pack-extension=`"$Src`"")
if (Test-Path $KeyFile) { $chromeArgs += "--pack-extension-key=`"$KeyFile`"" }
$p = Start-Process -FilePath $ChromePath -ArgumentList $chromeArgs -PassThru -Wait -WindowStyle Hidden

$BuiltCrx = "$Src.crx"
$BuiltPem = "$Src.pem"
if (-not (Test-Path $BuiltCrx)) { throw ".crx の作成に失敗しました（Chrome 終了コード $($p.ExitCode)）。" }
if (-not (Test-Path $KeyFile)) {
  if (-not (Test-Path $BuiltPem)) { throw '秘密鍵（.pem）が作成されませんでした。' }
  New-Item -ItemType Directory -Force $KeyDir | Out-Null
  Move-Item $BuiltPem $KeyFile
  Write-Host "秘密鍵を作成しました: $KeyFile（絶対に GitHub に上げず、別の場所にも控えを保管してください）" -ForegroundColor Yellow
}

# --- .crx（CRX3）のヘッダーから拡張機能 ID を読む ---
function Read-Varint([byte[]]$b, [ref]$i) {
  [uint64]$v = 0; $shift = 0
  while ($true) { $x = $b[$i.Value]; $i.Value++; $v = $v -bor ([uint64]($x -band 0x7F) -shl $shift); if (($x -band 0x80) -eq 0) { break }; $shift += 7 }
  return $v
}
function Get-ProtoField([byte[]]$b, [int]$start, [int]$end, [int]$want) {
  $i = $start
  while ($i -lt $end) {
    $key = Read-Varint $b ([ref]$i); $field = [int]($key -shr 3); $wt = [int]($key -band 7)
    switch ($wt) {
      0 { [void](Read-Varint $b ([ref]$i)) }
      1 { $i += 8 }
      5 { $i += 4 }
      2 {
        $len = [int](Read-Varint $b ([ref]$i))
        if ($field -eq $want) { return ,($b[$i..($i + $len - 1)]) }
        $i += $len
      }
      default { throw "不明な protobuf 形式です（wire type $wt）" }
    }
  }
  return $null
}
$bytes = [IO.File]::ReadAllBytes($BuiltCrx)
if ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'Cr24' -or [BitConverter]::ToUInt32($bytes, 4) -ne 3) { throw 'CRX3 形式ではありません。' }
$hlen = [BitConverter]::ToUInt32($bytes, 8)
$signed = Get-ProtoField $bytes 12 (12 + $hlen) 10000   # signed_header_data
$crxId = Get-ProtoField $signed 0 $signed.Length 1       # SignedData.crx_id（16バイト）
$ExtId = -join ($crxId | ForEach-Object { [char](97 + ($_ -shr 4)); [char](97 + ($_ -band 15)) })

# --- docs\ へ書き出し ---
New-Item -ItemType Directory -Force $Docs | Out-Null
Copy-Item $BuiltCrx (Join-Path $Docs "$Name.crx") -Force
$xml = @"
<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='$ExtId'>
    <updatecheck codebase='$CrxUrl' version='$Version' />
  </app>
</gupdate>
"@
[IO.File]::WriteAllText((Join-Path $Docs 'update.xml'), $xml, $Utf8NoBom)
[IO.File]::WriteAllText((Join-Path $Docs 'extension-id.txt'), $ExtId, $Utf8NoBom)
# GitHub Pages が .crx などをそのまま配るように Jekyll を無効にする
[IO.File]::WriteAllText((Join-Path $Docs '.nojekyll'), '', $Utf8NoBom)

Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "完了しました（バージョン $Version）" -ForegroundColor Green
Write-Host "  拡張機能 ID : $ExtId"
Write-Host "  update.xml  : $UpdateUrl"
Write-Host "  .crx        : $CrxUrl"
Write-Host ''
Write-Host 'docs\ の中身を GitHub に push してください。'
