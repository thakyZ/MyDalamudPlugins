Import-Module -Name "powershell-yaml"

$pluginsOut = @()

$DalamudApiLevel = 8;

$pluginList = Get-Content '.\repos.json' | ConvertFrom-Json

# Function to exit with a specific code.
function Exit-WithCode {
  param(
    [int]
    $Code
  )
  $host.SetShouldExit($Code)
  exit $Code
}

if ($null -eq $env:PAM) {
  Write-Error "Auth Key is null!"
  Exit-WithCode -Code 1
}

function ConvertTo-PascalCase {
  param(
    [System.Collections.Hashtable]
    $Data
  )
  $Data2 = $Data.PSObject.Copy()
  $Data.Keys | ForEach-Object {
    $OldKey = $_.ToString();
    $SavedValue = $Data2[$_];
    if ($OldKey -match "^[a-zA-Z]+(_[a-zA-Z]+)*") {
      $NewKey1 = ($OldKey -Replace "[^0-9A-Z]", " ")
      $NewKey2 = ((Get-Culture).TextInfo.ToTitleCase($NewKey1) -Replace " ")
      $Data2.Remove($OldKey)
      $Data2.Add($NewKey2, $SavedValue)
    }
  }
  return $Data2;
}

foreach ($plugin in $pluginList) {
  # Get values from the object
  $username = $plugin.username
  $repo = $plugin.repo
  $branch = $plugin.branch
  $pluginName = $plugin.pluginName
  $configFolder = $plugin.configFolder

  Write-Host $pluginName

  # Fetch the release data from the Gibhub API
  $data = $Null;

  Try {
    $data = (Invoke-WebRequest -Uri "https://api.github.com/repos/$($username)/$($repo)/releases/latest" -Headers @{ Authorization = "Bearer $($env:PAM)"; Accept = "application/vnd.github+json"; } -SkipHttpErrorCheck -ErrorAction Stop);

    If ($data.StatusCode -ne 200) {
      Write-Error -Message "Failed to download at uri $($json.assets[0].browser_download_url) ($($data.StatusCode))" -Exception $_.Exception;
      $data | Out-Host;
      $data.Content | Out-Host;
      Exit 1;
    }
  } Catch {
    Write-Error -Message "Failed to download at uri $($json.assets[0].browser_download_url) $($_.Exception.Message)" -Exception $_.Exception;
    $data | Out-Host;
    $data.Content | Out-Host;
    Exit 1;
  }

  $json = ($data.content | ConvertFrom-Json)

  # Get data from the api request.
  $count = $json.assets[0].download_count
  $assembly = $json.tag_name

  # $download = $json.assets[0].browser_download_url
  $download_release = $Null;

  Try {
    $download_release = (Invoke-WebRequest -Uri "$($json.assets[0].browser_download_url)" -Headers @{ Authorization = "Bearer $($env:PAM)"; Accept = "application/octet-stream"; } -OutFile (Join-Path -Path $PWD -ChildPath "plugins" -AdditionalChildPath @("$($plugin)", "latest.zip")) -SkipHttpErrorCheck -ErrorAction Stop -PassThru);

    If ($download_release.StatusCode -ne 200) {
      Write-Error -Message "Failed to download at uri $($json.assets[0].browser_download_url) ($($download_release.StatusCode))" -Exception $_.Exception;
      $download_release | Out-Host;
      $download_release.Content | Out-Host;
      Exit 1;
    }
  } Catch {
    Write-Error -Message "Failed to download at uri $($json.assets[0].browser_download_url) $($_.Exception.Message)" -Exception $_.Exception;
    $download_release | Out-Host;
    $download_release.Content | Out-Host;
    Exit 1;
  }

  $latest_file_data = $null;

  Try {
    $latest_file_data = (Invoke-WebRequest -Uri "https://api.github.com/repos/$($username)/MyDalamudPlugins/contents/plugins/$($plugin)/latest.zip" -Headers @{ Authorization = "Bearer $($env:PAM)"; Accept = "application/vnd.github+json"; } -SkipHttpErrorCheck -ErrorAction Stop);

    If ($latest_file_data.StatusCode -ne 200) {
      Write-Error -Message "Failed to download at uri $($json.assets[0].browser_download_url) ($($latest_file_data.StatusCode))" -Exception $_.Exception;
      $latest_file_data | Out-Host;
      $latest_file_data.Content | Out-Host;
      Exit 1;
    }
  } Catch {
    Write-Error -Message "Failed to download at uri $($json.assets[0].browser_download_url) $($_.Exception.Message)" -Exception $_.Exception;
    $latest_file_data | Out-Host;
    $latest_file_data.Content | Out-Host;
    Exit 1;
  }

  $latest_file = ($data.content | ConvertFrom-Json)
  $download = $latest_file.download_url;
  
  # Get timestamp for the release.
  $time = [Int](New-TimeSpan -Start (Get-Date "01/01/1970") -End ([DateTime]$json.published_at)).TotalSeconds

  # Get the config data from the repo.
  $config = $null;
  $configData = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$($username)/$($repo)/$($branch)/$($configFolder)/$($pluginName).json" -Headers @{ Authorization = "Bearer $($env:PAM)"; Accept = "application/vnd.github+json"; } -SkipHttpErrorCheck -ErrorAction Continue)
  if ($null -ne $configData -and $configData.BaseResponse.StatusCode -ne 404) {
    $config = ($configData.content -replace '\uFEFF' | ConvertFrom-Json)
  }
  else {
    $configData = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$($username)/$($repo)/$($branch)/$($configFolder)/$($pluginName).yaml" -Headers @{ Authorization = "Bearer $($env:PAM)"; Accept = "application/vnd.github+json"; } -SkipHttpErrorCheck -ErrorAction Continue)
    $config = (ConvertTo-PascalCase -Data ($configData.content -replace '\uFEFF' | ConvertFrom-Yaml))
  }

  # Ensure that config is converted properly.
  if ($null -eq $config) {
    Write-Error "Config for plugin $($plugin) is null!"
    Exit-WithCode -Code 1
  }

  if ($null -eq ($config | Get-Member -Name "DalamudApiLevel")) {
    $config | Add-Member -Name "DalamudApiLevel" -MemberType NoteProperty -Value $DalamudApiLevel
  }

  # Add additional properties to the config.
  $config | Add-Member -Name "IsHide" -MemberType NoteProperty -Value "False"
  $config | Add-Member -Name "IsTestingExclusive" -MemberType NoteProperty -Value "False"
  $config | Add-Member -Name "AssemblyVersion" -MemberType NoteProperty -Value $assembly
  $config | Add-Member -Name "LastUpdated" -MemberType NoteProperty -Value $time
  $config | Add-Member -Name "DownloadCount" -MemberType NoteProperty -Value $count
  $config | Add-Member -Name "DownloadLinkInstall" -MemberType NoteProperty -Value $download
  $config | Add-Member -Name "DownloadLinkTesting" -MemberType NoteProperty -Value $download
  $config | Add-Member -Name "DownloadLinkUpdate" -MemberType NoteProperty -Value $download
  # $config | Add-Member -Name "IconUrl" -MemberType NoteProperty -Value "https://raw.githubusercontent.com/$($username)/$($repo)/$($branch)/icon.png"

  # Add to the plugin array.
  $pluginsOut += $config
}

# Convert plugins to JSON
$pluginJson = ($pluginsOut | ConvertTo-Json)

# Save repo to file
Set-Content -Path "pluginmaster.json" -Value $pluginJson
