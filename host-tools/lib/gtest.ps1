# lib\gtest.ps1 - GoogleTest のソース取得 (trigger_gtest.flag)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

function Write-GtestMarker($value) {
    Write-RunId
    try {
        [System.IO.File]::WriteAllText($GtestResultFile, $value)
        Write-Host "[MARKER] $value -> $GtestResultFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "[MARKER] FAILED to write $GtestResultFile : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 失敗を記録する。gtest_error.log を書いたあとに、完了マーカー (FAILED) を書く。
function Write-GtestFailure([string[]]$lines) {
    Write-Host "[GTEST] FAILED" -ForegroundColor Red
    $lines | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    (@("[ENVIRONMENT ERROR - not a source code problem]") + @($lines)) | Out-File $GtestErrorLog -Encoding utf8
    Write-GtestMarker "FAILED"
}

# 取得して <TargetDir>\ThirdParty\googletest に置く。成功したら OK、失敗したら FAILED をマーカーに書く。
function Invoke-GtestFetch([string]$tagLine) {
    $tag = "$tagLine".Trim()
    if (-not $tag) { $tag = $GtestTag }
    # タグは、コマンドの引数や URL に渡るので、決まった形だけを許可する
    if ($tag -notmatch '^(v|release-)\d+\.\d+(\.\d+)?$') {
        Write-GtestFailure @("ERROR: invalid GoogleTest tag: '$tag' (allowed: v1.17.0 / release-1.12.1)")
        return
    }
    $dest    = Join-Path $TargetDir "ThirdParty\googletest"
    $verFile = Join-Path $dest "VERSION.txt"
    $headerP = Join-Path $dest "include\gtest\gtest.h"
    # すでに同じタグが置かれていれば、取得しない (冪等)。判定の材料は、毎回、表示する (実機での原因調べのため)。
    $haveHeader = Test-Path -LiteralPath $headerP
    $haveVer = "<none>"
    if (Test-Path -LiteralPath $verFile) {
        $haveVer = ("" + (Get-Content -LiteralPath $verFile -Raw)).Trim([char]0xFEFF, [char]32, [char]9, [char]13, [char]10)
    }
    Write-Host "[GTEST] check: wanted='$tag' / VERSION.txt='$haveVer' / gtest.h exists=$haveHeader" -ForegroundColor DarkGray
    if ($haveHeader -and ($haveVer -ieq $tag)) {
        Write-Host "[GTEST] $tag is already in $dest" -ForegroundColor Green
        Write-GtestMarker "OK"
        return
    }

    Write-Host "[GTEST] Fetching GoogleTest $tag ..." -ForegroundColor Yellow
    $tmp = Join-Path $LogDir "gtest_tmp"
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $log = @()
    $src = $null

    # PS 5.1 は Stop 下でネイティブの stderr を例外にするため、ここでは Continue にする
    $ErrorActionPreference = "Continue"
    try {
        # 1. git
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $cloneDir = Join-Path $tmp "clone"
            $out = & git clone --depth 1 --branch $tag "$GtestRepoUrl.git" $cloneDir 2>&1
            $code = $LASTEXITCODE
            $log += @($out | ForEach-Object { "$_" })
            if ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $cloneDir "googletest\include\gtest\gtest.h"))) {
                $src = Join-Path $cloneDir "googletest"
            } else {
                $log += "git clone failed (exit code $code). Trying the zip download."
            }
        } else {
            $log += "git was not found. Using the zip download."
        }
        # 2. zip
        if (-not $src) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $zip = Join-Path $tmp "googletest.zip"
                Invoke-WebRequest -Uri "$GtestRepoUrl/archive/refs/tags/$tag.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
                Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp "zip") -Force -ErrorAction Stop
                $root = Get-ChildItem -LiteralPath (Join-Path $tmp "zip") -Directory | Select-Object -First 1
                if ($root -and (Test-Path -LiteralPath (Join-Path $root.FullName "googletest\include\gtest\gtest.h"))) {
                    $src = Join-Path $root.FullName "googletest"
                } else {
                    $log += "The zip was downloaded, but googletest\include\gtest\gtest.h was not found in it."
                }
            } catch {
                $log += "zip download failed: $($_.Exception.Message)"
            }
        }
    } finally {
        $ErrorActionPreference = "Stop"
    }

    if (-not $src) {
        Write-GtestFailure (@("ERROR: could not get GoogleTest $tag from $GtestRepoUrl (check the network / proxy / the tag name).") + $log)
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    foreach ($need in @("include\gtest\gtest.h", "src\gtest-all.cc", "src\gtest_main.cc")) {
        if (-not (Test-Path -LiteralPath (Join-Path $src $need))) {
            Write-GtestFailure @("ERROR: the fetched GoogleTest has no googletest\$need (unexpected layout).")
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
    }

    # include / src / LICENSE だけを置く (サイズを小さく。ビルドに要るものだけ)
    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $src "include") -Destination $dest -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $src "src") -Destination $dest -Recurse -Force
    $license = Join-Path (Split-Path $src -Parent) "LICENSE"
    if (Test-Path -LiteralPath $license) { Copy-Item -LiteralPath $license -Destination $dest -Force }
    [System.IO.File]::WriteAllText($verFile, $tag)
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "[GTEST] GoogleTest $tag -> $dest" -ForegroundColor Green
    Write-GtestMarker "OK"
}
