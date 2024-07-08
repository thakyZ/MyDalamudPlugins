Param(
  # Only check if download paths resolve.
  [Parameter(Mandatory = $False,
    HelpMessage = "Only check if download paths resolve.")]
  [switch]
  $OnlyCheck = $False,
  # Only check if download paths resolve.
  [Parameter(Mandatory = $False,
    HelpMessage = "Only update the currently passed info.")]
  [switch]
  $Passed = $False
)

Begin {
  Class PluginRepoInstance {
    [System.String]   $Author = "";
    [System.String]   $IconUrl = "";
    [System.String]   $RepoUrl = "";
    [System.String]   $Description = "";
    [System.String[]] $Tags = @();
    [System.String]   $Changelog = "";
    [System.String]   $Name = "";
    [System.String]   $Punchline = "";
    [System.String]   $InternalName = "";
    [System.Int32]    $DalamudApiLevel = 8;
    [System.Boolean]  $IsHide = $False;
    [System.Boolean]  $IsTestingExclusive = $False;
    [System.Int32]    $LastUpdated = 0;
    [System.Int32]    $LoadRequiredState = 0;
    [System.Int32]    $LoadPriority = 0;
    [System.String]   $ApplicableVersion = "any";
    [System.String]   $AssemblyVersion = "1.0.0.0";
    [System.Boolean]  $AcceptsFeedback = $False;
    [System.Boolean]  $LoadSync = $False;
    [System.Boolean]  $CanUnloadAsync = $False;
    [System.Int32]    $DownloadCount = "";
    [System.String]   $DownloadLinkInstall = "";
    [System.String]   $DownloadLinkTesting = "";
    [System.String]   $DownloadLinkUpdate = "";

    SetIsHide($IsHide) {If ($IsHide -ne $this.IsHide) {$this.IsHide = $IsHide}}
    SetIsTestingExclusive($IsTestingExclusive) {If ($IsTestingExclusive -ne $this.IsTestingExclusive) {$this.IsTestingExclusive = $IsTestingExclusive}}
    SetAcceptsFeedback($AcceptsFeedback) {$this.AcceptsFeedback = $False}
    SetIconUrl($IconUrl) {If ($Null -eq $this.IconUrl) {$this.IconUrl = $IconUrl} Else {$TestWebRequest = (Invoke-WebRequest -Uri $this.IconUrl -Method Get -SkipHttpErrorCheck -ErrorAction Stop);If ($TestWebRequest.StatusCode -eq 404) {$this.IconUrl = $IconUrl}}}

    static [PluginRepoInstance] FromHashTable($HashTable) {
      [PluginRepoInstance] $Output = [PluginRepoInstance]::new();
      ForEach($Key in $HashTable.Keys) {
        $IsNull = $False;
        If ($Null -eq $HashTable[$Key]) {
          Write-Error -Message "Inbound hashtable with key, $($Key) resolved to: null";
          $IsNull = $True;
        }
        If ($Null -ne ($Output | Get-Member -Name $Key -MemberType "Property")) {
          If (-not $IsNull) {
            $Output.($Key) = $HashTable[$Key]
          }
        } Else {
          If (-not $IsNull) {
            $Output | Add-Member -Name $Key -MemberType "NoteProperty" -Value $HashTable[$Key];
          }
        }
      }
      Return $Output;
    }

    [Hashtable] ToHashtable() {
      [Hashtable] $Output = @{};
      $Properties = ($this | Get-Member -MemberType "Property")
      ForEach ($Property in $Properties) {
        $Output[$Property.Name] = $this.($Property.Name)
      }
      $NoteProperties = ($this | Get-Member -MemberType "NoteProperty")
      ForEach ($NoteProperty in $NoteProperties) {
        $Output[$NoteProperty.Name] = $this[$NoteProperty];
      }
      Return $Output;
    }

    static [Hashtable[]] ToHashtableList($ConfigList) {
      [Hashtable[]] $Output = @();
      ForEach ($Config in $ConfigList) {
        $Output += $Config.ToHashtable();
      }
      Return $Output;
    }
  }

  # Function to Exit with a specific code.
  Function Exit-WithCode {
    Param(
      # Specifies the exit code to exit the program with.
      [Parameter(Mandatory = $True,
        Position = 0,
        ValueFromPipeline = $True,
        ValueFromPipelineByPropertyName = $True,
        ValueFromRemainingArguments = $True,
        HelpMessage = "The exit code to exit the program with.")]
      [int]
      $Code
    )
    # $Host.SetShouldExit($Code)
    Exit $Code
  }

  If ($Null -eq $env:PAM) {
    Write-Error "Auth Key is null!"
    Exit-WithCode -Code 1
  }

  Function ConvertTo-PascalCase {
    Param(
      # Specifies a hashtable of keys and values to convert the keys to pascal case.
      [Parameter(Mandatory = $True,
        Position = 0,
        ValueFromPipeline = $True,
        ValueFromPipelineByPropertyName = $True,
        ValueFromRemainingArguments = $True,
        HelpMessage = "A hashtable of keys and values to convert the keys to pascal case.")]
      [System.Collections.Hashtable]
      $Data
    )
    $Data2 = $Data.PSObject.Copy()

    ForEach ($Key in $Data.Keys) {
      $OldKey = $Key.ToString();
      $SavedValue = $Data2[$Key];
      If ($OldKey -match "^[a-zA-Z]+(_[a-zA-Z]+)*") {
        $NewKey1 = ($OldKey -Replace "[^0-9A-Z]", " ")
        $NewKey2 = ((Get-Culture).TextInfo.ToTitleCase($NewKey1) -Replace " ")
        $Data2.Remove($OldKey)
        $Data2.Add($NewKey2, $SavedValue)
      }
    }

    Return $Data2;
  }

  Function Test-ConfigFolderPath() {
    Param(
      # Specifies the username of the owner of a repository.
      [Parameter(Mandatory = $True,
        Position = 0,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $True,
        HelpMessage = "The username of the owner of a repository.")]
      [ValidateNotNullOrEmpty()]
      [Alias("User", "Owner")]
      [string]
      $Username,
      # Specifies the name of a repository.
      [Parameter(Mandatory = $True,
        Position = 1,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $True,
        HelpMessage = "The name of a repository.")]
      [ValidateNotNullOrEmpty()]
      [Alias("Repository")]
      [string]
      $Repo,
      # Specifies the main release branch of a repository.
      [Parameter(Mandatory = $True,
        Position = 2,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $True,
        HelpMessage = "The main release branch of a repository.")]
      [ValidateNotNullOrEmpty()]
      [string]
      $Branch,
      # Specifies the config folder of a repository.
      [Parameter(Mandatory = $True,
        Position = 3,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $True,
        HelpMessage = "The config folder of a repository.")]
      [ValidateNotNullOrEmpty()]
      [Alias("Config")]
      [string]
      $ConfigFolder,
      # Specifies the plugin name of the repository.
      [Parameter(Mandatory = $True,
        Position = 4,
        ValueFromPipeline = $False,
        ValueFromPipelineByPropertyName = $True,
        HelpMessage = "The plugin name of the repository.")]
      [ValidateNotNullOrEmpty()]
      [Alias("Plugin")]
      [string]
      $PluginName
    )
    $FileExtensions = @("json", "yaml");

    ForEach ($FileExtension in $FileExtensions) {
      $WebRequestContent = (Invoke-RestMethod -Uri "https://api.github.com/repos/$($Username)/$($Repo)/contents/$($ConfigFolder)$($PluginName).$($FileExtension)" -Method Get -Authentication Bearer -Token $Token -Headers $CommonHeaders -SkipHttpErrorCheck -ErrorAction Continue)

      If ($Null -ne $WebRequestContent -and (($Null -eq $WebRequestContent.message -or $WebRequestContent.message -ne "Not Found") -and ($Null -eq $WebRequestContent.StatusCode -or $WebRequestContent.StatusCode -ne 404))) {
        Return $WebRequestContent;
      }
    }

    Return $WebRequestContent;
  }

  Function Add-MemberProxy {
    [CmdletBinding()]
    Param(
      [Parameter(Mandatory = $True,
        Position = 0)]
      [ValidateNotNullOrEmpty()]
      [System.String]
      $Name,
      [Parameter(Mandatory = $False)]
      [System.Object]
      $Value,
      [Parameter(Mandatory = $False)]
      [System.Object]
      $DefaultValue,
      [Parameter(Mandatory = $True,
        Position = 4,
        ValueFromPipeline = $True)]
      [System.Management.Automation.PSObject]
      $InputObject
    )

    If ($Null -eq ($InputObject | Get-Member -Name $Name)) {
      If ($Null -ne $DefaultValue -and -not [System.String]::IsNullOrEmpty($DefaultValue)) {
        Return $InputObject | Add-Member -MemberType "NoteProperty" -Name $Name -Value $DefaultValue
      } Else {
        Return $InputObject | Add-Member -MemberType "NoteProperty" -Name $Name -Value $DefaultValue
      }
    }
  }

  # cspell:ignore pluginmaster
  # cspell:ignoreRegExp \\uFEFF

  If ($OnlyCheck -eq $True) {
    $Data = (Get-Content -Path "pluginmaster.json" | ConvertFrom-Json);

    ForEach ($Plugin in $Data) {
      $Check = $Null;
      Try {
        $Check = (Invoke-WebRequest -Uri "$($Plugin.DownloadLinkInstall)" -SkipHttpErrorCheck -ErrorAction Stop)

        If ($Check.StatusCode -ne 200 -and $Check.StatusCode -ne 404) {
          Write-Error -Message "Failed to find download uri at $($Plugin.DownloadLinkInstall) ($($Check.StatusCode))";
          Exit-WithCode -Code 1
        } ElseIf ($Check.StatusCode -eq 404) {
          Write-Error -Message "Failed to find download uri at $($Plugin.DownloadLinkInstall) ($($Check.StatusCode))";
          Exit-WithCode -Code 1
        }
      } Catch {
        Write-Error -Message "Failed to find download uri at $($Plugin.DownloadLinkInstall) ($($Check.StatusCode)) $($_.Exception.Message)" -Exception $_.Exception;
        Write-Host -ForegroundColor Red -Object $_.Exception.StackTrace;
        Exit-WithCode -Code 1
      }
    }

    Exit 0;
  }

  Import-Module -Name "powershell-yaml"

  [PluginRepoInstance[]]$PluginsOut = @();

  $PluginList = (Get-Content '.\repos.json' | ConvertFrom-Json -Depth 100 -AsHashtable);

  $Token = (ConvertTo-SecureString -String $env:PAM -AsPlainText);

  If ($Null -eq $Token) {
    Write-Error -Message "`$Token is `$Null";
    Exit-WithCode -Code 1
  }

  $CommonHeaders = @{ Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28" };
  $OctetStreamHeaders = $CommonHeaders;
  # $OctetStreamHeaders.Accept = "application/octet-stream";
} Process {
  $PluginInfo = @{};

  If ($Null -ne $env:PLUGIN_INFO -and -not [System.String]::IsNullOrEmpty($env:PLUGIN_INFO) -and -not [System.String]::IsNullOrWhiteSpace($env:PLUGIN_INFO) -and $env:PLUGIN_INFO -ne '{}') {
    $PluginInfo = ($env:PLUGIN_INFO | ConvertFrom-Json -Depth 100 -AsHashtable)
  }

  $OriginalMaster = (Get-Content -Path (Join-Path -Path $PWD -ChildPath "pluginmaster.json") | ConvertFrom-Json -Depth 100 -AsHashtable);

  ForEach ($Plugin in $PluginList) {
    # Get values from the object
    $Username = $Plugin.username
    $Repo = $Plugin.repo
    $Branch = $Plugin.branch
    $PluginName = $Plugin.pluginName

    $OriginalPluginInfo = ($OriginalMaster | Where-Object { $_.InternalName -eq $PluginName })

    $ConfigFolder = $Plugin.configFolder
    If ($ConfigFolder -eq "") {
      $ConfigFolder = "/"
    } ElseIf (-not $ConfigFolder.EndsWith("/")) {
      $ConfigFolder = "$($ConfigFolder)/"
    }

    Write-Host $PluginName

    # Fetch the release data from the GitHub API
    $Data = $Null;

    Try {
      $Data = (Invoke-RestMethod -Uri "https://api.github.com/repos/$($Username)/$($Repo)/releases/latest" -Method Get -Authentication Bearer -Token $Token -Headers $CommonHeaders -SkipHttpErrorCheck -ErrorAction Stop);

      If ($Null -eq $Data -or (($Null -ne $Data.message -and $Data.message -eq "Not Found") -or ($Null -ne $Data.StatusCode -and $Data.StatusCode -eq 404))) {
        Write-Error -Message "Failed to get release at uri `"https://api.github.com/repos/$($Username)/$($Repo)/releases/latest`" (Null)";
        Exit-WithCode -Code 1
      }
    } Catch {
      Write-Error -Message "Failed to get release at uri `"https://api.github.com/repos/$($Username)/$($Repo)/releases/latest`"\n$($_.Exception.Message)" -Exception $_.Exception;
      Exit-WithCode -Code 1
    }

    If ($Null -eq $Data) {
      Throw "Data content is null"
    } ElseIf ($Null -eq $Data.assets) {
      Write-Host -NoNewline -Object "`$Data =`n> ";
      Write-Output $Data | Out-Host;
      Throw "Data content assets is null"
    } ElseIf ($Null -eq $Data.assets[0]) {
      Throw "Data content assets :first-child is null"
    } ElseIf ($Null -eq $Data.assets[0].download_count) {
      Throw "Data content assets :first-child download_count is null"
    }

    # Get data from the api request.
    $Count = $Data.assets[0].download_count
    $Assembly = $Data.tag_name

    # $DownloadRelease = $Null;

    Try {
      $OctetStreamHeaders.Authentication = "Bearer $($Token)"
      $GetRelease = (Invoke-WebRequest -Uri $Data.assets[0].browser_download_url -Method Get -Headers $CommonHeaders -OutFile (Join-Path -Path $PWD -ChildPath "plugins" -AdditionalChildPath @("$($PluginName)", "latest.zip")) -SkipHttpErrorCheck -ErrorAction Stop -PassThru);

      If ($Null -eq $GetRelease -or (($Null -ne $GetRelease.message -and $GetRelease.message -eq "Not Found") -or ($Null -ne $GetRelease.StatusCode -and $GetRelease.StatusCode -eq 404))) {
        Write-Error -Message "Failed to download at uri $() ($($GetRelease.StatusCode))";
        Exit-WithCode -Code 1
      }
    } Catch {
      Write-Error -Message "Failed to download at uri $($Data.assets[0].browser_download_url) $($_.Exception.Message)" -Exception $_.Exception;
      Write-Host -ForegroundColor Red -Object $_.Exception.StackTrace;
      Exit-WithCode -Code 1
    }

    $LatestFile = $Null;

    Try {
      $LatestFile = (Invoke-RestMethod -Uri "https://api.github.com/repos/$($Username)/MyDalamudPlugins/contents/plugins/$($PluginName)/latest.zip" -Method Get -Authentication Bearer -Token $Token -Headers $CommonHeaders -SkipHttpErrorCheck -ErrorAction Stop);

      If ($Null -eq $LatestFile -or (($Null -ne $LatestFile.message -and $LatestFile.message -eq "Not Found") -or ($Null -ne $LatestFile.StatusCode -and $LatestFile.StatusCode -eq 404))) {
        Write-Error -Message "Failed to get latest file url at uri https://api.github.com/repos/$($Username)/MyDalamudPlugins/contents/plugins/$($PluginName)/latest.zip ($($LatestFile.StatusCode))";
        Exit-WithCode -Code 1
      } ElseIf ($LatestFile.StatusCode -eq 404) {
        $LatestFile = @{ content = "" }
        $LatestFile.content = "{`"download_url`":`"https://raw.githubusercontent.com/$($Username)/MyDalamudPlugins/main/plugins/$($PluginName)/latest.zip`"}";
      }
    } Catch {
      Write-Error -Message "Failed to get latest file url at uri https://api.github.com/repos/$($Username)/MyDalamudPlugins/contents/plugins/$($PluginName)/latest.zip $($_.Exception.Message)" -Exception $_.Exception;
      Write-Host -ForegroundColor Red -Object $_.Exception.StackTrace;
      Exit-WithCode -Code 1
    }

    $Download = $LatestFile.download_url;

    # Get timestamp for the release.
    $Time = [System.Int32](New-TimeSpan -Start (Get-Date "01/01/1970") -End ([DateTime]$Data.published_at)).TotalSeconds

    [PluginRepoInstance]$Config = [PluginRepoInstance]::new();

    If ($PluginInfo.InternalName -ne $OriginalPluginInfo.InternalName) {
      $ConfigData = (Test-ConfigFolderPath -Username $Username -Repo $Repo -Branch $Branch -ConfigFolder $ConfigFolder -PluginName $PluginName);

      If ($Null -ne $ConfigData -and (($Null -eq $ConfigData.message -or $ConfigData.message -ne "Not Found") -and ($Null -eq $ConfigData.StatusCode -or $ConfigData.StatusCode -ne 404))) {
        If ($ConfigData.encoding -eq "base64") {
          Try {
            $DecodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ConfigData.content));
          } Catch {
            Write-Error -Message "Failed to decode config data content."
            Exit-WithCode -Code 1;
          }
        } Else {
          Write-Error -Message "Unknown or new encoding type, `"$($ConfigData.encoding)`".";
          Exit-WithCode -Code 1;
        }

        If ($FileExtensionOfConfig -eq "json") {
          $Content = ($DecodedContent -replace '\uFEFF', '' | ConvertFrom-Json -AsHashtable -Depth 100);
          $Config = [PluginRepoInstance]::FromHashTable($Content);
        } Else {
          $Content = (ConvertTo-PascalCase -Data ($DecodedContent -replace '\uFEFF', '' | ConvertFrom-Yaml));
          $Config = [PluginRepoInstance]::FromHashTable($Content);
        }
      } Else {
        Write-Output $ConfigData | Out-Host;
        Write-Output $CommonHeaders | Out-Host;
        Write-Error "Could not find config file of plugin `"$($PluginName)`".";
        Return $ConfigData;
        Exit-WithCode -Code 1
      }

      # Ensure that config is converted properly.
      If ($Null -eq $Config) {
        Write-Error "Config for plugin $($PluginName) is null!";
        Exit-WithCode -Code 1
      }
    } Else {
      $Config = [PluginRepoInstance]::FromHashTable($PluginInfo);
    }

    # Add additional properties to the config.
    $Config.AssemblyVersion = $Assembly;
    $Config.LastUpdated = $Time;
    $Config.DownloadCount = $Count;
    $Config.DownloadLinkInstall = $Download;
    $Config.DownloadLinkTesting = $Download;
    $Config.DownloadLinkUpdate = $Download;
    $Config.SetIconUrl("https://raw.githubusercontent.com/$($Username)/MyDalamudPlugins/main/plugins/$($PluginName)/images/icon.png");

    # Add to the plugin array.
    $PluginsOut += $Config
  }
} End {
  # Convert plugins to JSON
  $PluginJson = ([PluginRepoInstance]::ToHashTableList($PluginsOut) | ConvertTo-Json)

  # Save repo to file
  Set-Content -Path "pluginmaster.json" -Value $PluginJson
}
