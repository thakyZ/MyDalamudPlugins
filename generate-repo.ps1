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

foreach ($plugin in $pluginList) {
  # Get values from the object
  $username = $plugin.username
  $repo = $plugin.repo
  $branch = $plugin.branch
  $pluginName = $plugin.pluginName
  $configFolder = $plugin.configFolder
  
  Write-Host $pluginName

  # Fetch the release data from the Gibhub API
  $data = (Invoke-WebRequest -Uri "https://api.github.com/repos/$($username)/$($repo)/releases/latest" -Headers @{ Authorization = "Bearer $($env:PAM)" })
  $json = ($data.content | ConvertFrom-Json)

  # Get data from the api request.
  $count = $json.assets[0].download_count
  $assembly = $json.tag_name

  $download = $json.assets[0].browser_download_url
  # Get timestamp for the release.
  $time = [Int](New-TimeSpan -Start (Get-Date "01/01/1970") -End ([DateTime]$json.published_at)).TotalSeconds

  # Get the config data from the repo.
  $config = $null;
  $configData = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$($username)/$($repo)/$($branch)/$($configFolder)/$($pluginName).json" -SkipHttpErrorCheck -ErrorAction Continue)
  if ($null -ne $configData -and $configData.BaseResponse.StatusCode -ne 404) {
    $config = ($configData.content -replace '\uFEFF' | ConvertFrom-Json)
  } else {
    $configData = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$($username)/$($repo)/$($branch)/$($configFolder)/$($pluginName).yaml" -SkipHttpErrorCheck -ErrorAction Continue)
    $config = ($configData.content -replace '\uFEFF' | ConvertFrom-Yaml)
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
