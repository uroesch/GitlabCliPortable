# -----------------------------------------------------------------------------
# Description: Common classes and functions for portable apps powershell
#   scripts
# Author: Urs Roesch <github@bun.ch>
# Version: 0.9.5
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------
$AppRoot         = $(Convert-Path "$PSScriptRoot\..\..")
$AppName         = (Get-Item $AppRoot).Basename
$AppDir          = Join-Path $AppRoot App
$DownloadDir     = Join-Path $AppRoot Download
$AppInfoDir      = Join-Path $AppDir AppInfo
$LauncherDir     = Join-Path $AppInfoDir Launcher
$AppInfoIni      = Join-Path $AppInfoDir appinfo.ini
$UpdateIni       = Join-Path $AppInfoDir update.ini
$LauncherIni     = Join-Path $LauncherDir "$AppName.ini"
$InfraDirDefault = $(Convert-Path "$AppRoot\..")

# -----------------------------------------------------------------------------
# Classes
# -----------------------------------------------------------------------------
Class Download {
  [string] $URL
  [string] $ExtractName
  [string] $TargetName
  [string] $Checksum
  [string] $AppRoot     = $(Convert-Path "$PSScriptRoot\..\..")
  [string] $DownloadDir = $(Switch-Path "$($This.AppRoot)\Download")

  Download(
    [string] $u,
    [string] $en,
    [string] $tn,
    [string] $c
  ){
    $This.URL         = $u
    $This.ExtractName = $en
    $This.TargetName  = $tn
    $This.Checksum    = $c
  }

  [string] Basename() {
    $Elements = ($This.URL.split('?'))[0].split('/')
    $Basename = $Elements[$($Elements.Length-1)]
    return $Basename
  }

  [string] ExtractTo() {
    # If Extract name is empty the downloaded archive has all files
    # placed in the root of the archive. In that case we use the
    # TargetName and and attach it to the script location
    If ($This.ExtractName -eq "") {
      return $(Switch-Path "$($This.DownloadDir)\$($This.TargetName)")
    }
    return $This.DownloadDir
  }

  [string] MoveFrom() {
    If ($This.ExtractName -eq "") {
      return $(Switch-Path "$($This.DownloadDir)\$($This.TargetName)")
    }
    return $(Switch-Path "$($This.DownloadDir)\$($This.ExtractName)")
  }

  [string] MoveTo() {
    return $(Switch-Path "$($This.AppRoot)\App\$($This.TargetName)")
  }

  [string] OutFile() {
    return $(Switch-Path "$($This.DownloadDir)\$($This.Basename())")
  }
}

# -----------------------------------------------------------------------------
# Function
# -----------------------------------------------------------------------------
Function Test-Unix() {
  ($PSScriptRoot)[0] -eq '/'
}

# -----------------------------------------------------------------------------
Function ConvertTo-WindowsPath() {
  param( [string] $Path )
  If (!(Test-Unix)) { return $Path }
  $WinPath = & winepath --windows $Path 2>/dev/null
  Return $WinPath
}

# -----------------------------------------------------------------------------
Function Switch-Path() {
  # Convert Path only Works on Existing Directories :(
  Param( [string] $Path )
  Switch (Test-Unix) {
    $True {
      $From = '\'
      $To   = '/'
      break;
    }
    default {
      $From = '/'
      $To   = '\'
    }
  }
  $Path = $Path.Replace($From, $To)
  Return $Path
}

# -----------------------------------------------------------------------------
Function Debug() {
  param(
    [string] $Severity,
    [string] $Message
  )
  $Color = 'White'
  $Severity = $Severity.ToUpper()
  Switch ($Severity) {
    'INFO'  { $Color = 'Green';      break }
    'WARN'  { $Color = 'Yellow';     break }
    'ERROR' { $Color = 'DarkYellow'; break }
    'FATAL' { $Color = 'Red';        break }
    default { $Color = 'White';      break }
  }
  If (!($Debug)) { return }
  Write-Host "$(Get-Date -Format u) - " -NoNewline
  Write-Host $Severity": " -NoNewline -ForegroundColor $Color
  Write-Host "$AppName - " -NoNewline
  Write-Host $Message.Replace($(Switch-Path "$AppRoot\"), '')
}

# -----------------------------------------------------------------------------
Function Download-Checksum() {
  Param(
    [String] $Uri,
    [String] $File
  )
  Try {
    $Pattern = "[A-Fa-f0-9]{32,}"
    $OutFile = Join-Path $DownloadDir ($Uri.Split("/"))[-1]
    Debug debug "Downloading checksum file from $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile
    Foreach ($Line in (Get-Content -Path $OutFile)) {
      $Line = $Line.Trim()
      Switch -regex ($Line) {
        "^[A-Fa-f0-9 ]{32,}$" {
          # Apache Directory Studio
          Return $Line -replace "\s+", ""
        }
        "^$Pattern$" {
          # Single line file with checksum only
          Return $Line
        }
        "^$File\s+$Pattern$" {
          # Multiline file with file name prefix
          Return $Line -replace "$File\s+($Pattern)", "`$1"
        }
        "^$Pattern\s+\*?$File$" {
          # Multiline file with file name suffix
          Return $Line -replace "^($Pattern)\s+\*?$File", "`$1"
        }
        "^$Pattern\s+.+/$File$" {
          # Multiline file with multiple entries e.g. putty
          # 2f49ec1e6c35e10c....  w32/putty.zip
          Return $Line -replace "^($Pattern)\s+.*", "`$1"
        }
        default {
          Debug debug "No match in line '$Line'"
        }
      }
    }
  }
  Catch {
    Debug error "Unable to download checksum from URL '$Uri'"
    Exit 124
  }
}

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
Function Compare-Checksum {
  param(
    [string] $Path,
    [string] $Checksum
  )

  Debug debug "Compare-Checksum -> -Path $Path -Checksum $Checksum"
  # The somewhat involved split is here to make it compatible with win10
  ($Algorithm, $Sum) = ($Checksum -replace '::', "`n").Split("`n")
  If ($Sum -like 'http*') {
    $Sum = Download-Checksum -Uri $Sum -File (Get-Item $Path).Name
    $Checksum = $Algorithm + "::" + $Sum
    Debug debug "Checksum from download: $Checksum"
  }
  Debug debug "Get-Checksum -Path $Path -Algorithm $Algorithm"
  $Result = Get-Checksum -Path $Path -Algorithm $Algorithm
  Debug info "Checksum of INI ($($Checksum.ToUpper())) and download ($Result)"
  Return ($Checksum.ToUpper() -eq $Result)
}

# -----------------------------------------------------------------------------
Function Get-Checksum {
  Param(
    [string] $Path,
    [string] $Algorithm
  )
  Debug debug "Get-FileHash -Path $Path -Algorithm $Algorithm"
  $Hash = (Get-FileHash -Path $Path -Algorithm $Algorithm).Hash
  Return ($Algorithm + "::" + $Hash).ToUpper()
}

# -----------------------------------------------------------------------------
Function Update-Checksum {
  Param(
    [string] $Path,
    [string] $Checksum
  )
  Debug debug "Update-Checksum -> -Path $Path -Checksum $Checksum"
  ($Algorithm, $Sum) = ($Checksum -replace '::', "`n").Split("`n")
  If ($Sum -like 'http*') { Return $Checksum }
  Debug debug "Get-Checksum -Path $Path -Algorithm $Algorithm"
  $NewChecksum = Get-Checksum -Path $Path -Algorithm $Algorithm
  Get-Content -Path $UpdateIni | `
    Foreach-Object { $_ -Replace $Checksum, $NewChecksum } | `
    Set-Content -Path $UpdateIni
  Return $NewChecksum
}

# -----------------------------------------------------------------------------
# Export
# -----------------------------------------------------------------------------
Export-ModuleMember -Function Test-Unix
Export-ModuleMember -Function ConvertTo-WindowsPath
Export-ModuleMember -Function Switch-Path
Export-ModuleMember -Function Compare-Checksum
Export-ModuleMember -Function Get-Checksum
Export-ModuleMember -Function Update-Checksum
Export-ModuleMember -Function Debug
Export-ModuleMember -Variable AppRoot
Export-ModuleMember -Variable AppName
Export-ModuleMember -Variable AppDir
Export-ModuleMember -Variable DownloadDir
Export-ModuleMember -Variable AppInfoDir
Export-ModuleMember -Variable LauncherDir
Export-ModuleMember -Variable AppInfoIni
Export-ModuleMember -Variable UpdateIni
Export-ModuleMember -Variable LauncherIni
Export-ModuleMember -Variable InfraDirDefault
