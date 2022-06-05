# PowerShell Depolyment Script - Boilerplate
#
# @version: 0.2
# @autor Benedikt Wurz, Dominik Beyerle
# @LastModified 4.3.2022
# @Info: Download exe form Server to LocalTemp Folder
#        check if older version is installed, if so upgrade
#        delete installfile
#
#
### Install Software #Software Name#

Param
(
    [Alias('n')]
    [Parameter(Mandatory = $false)]
    [Switch] $printPackageName,         #switch to print package name according to configuration
    [Alias('c')]
    [Parameter(Mandatory = $false)]
    [Switch] $generateConfig            #switch to generate configuration file, if you want to save configuration from script - not recommended
)

##check OS Architecture
$computerInfo =Get-ComputerInfo("OsArchitecture")
if ($computerInfo.OsArchitecture -eq '64-Bit'){
   $arch = "x64"
}else{
   $arch = "x86"
}

$loadFromConfig         =   $true                                   #set to true if configuration should be loaded from local .config.json file
$deleteInstaller        =   $false                                  #set true if the provided installer / downloaded installed should be deleted after installation
$downloadFromServer     =   $false                                  #set true if installer should be downloaded from reposetory server or false if it should be loaded from $installFile path
$server                 =   ""                                      #the server where the packages are stored
$supportMultipleArch    =   $false                                  #set to true if the given installer/package support x64 and x86 architecture          
$version                =   ""                                      #the version number of the package
$packagePrefix          =   ""                                      #string before package-name e.g: "agent"
$packageName            =   ""                                      #the name of the package
$packageSuffix          =   ""                                      #string after package-name  e.g: "agent"
$packageExtension       =   ""                                      #the extension of the installer package (most of the times .msi or .exe)
$installfile            =   ''                                      #the local installer file-path, used when $downloadFromServer == false
$forceInstall           =   $false                                  #whether the installation should be enforced or not
$setupOptions           =   ""                                      #the setup options - like silent install or no restart
$customPackagePattern   =   ""                                      #if not empty, this name will be used as filename

#always use this variable if you want to access current direcotry - do not use .\

$parentDirectory = split-path -parent $MyInvocation.MyCommand.Definition 
$configFiles = Get-ChildItem -Path (("{0}\*" -f ($parentDirectory)) -File -Include *.config.json

if(($loadFromConfig -eq $true) -and ($configFiles.count -gt 0))
{
    Write-Host ("Loading config: {0}" -f $configFiles[0].FullName) -ForegroundColor Green
    $configuration = (Get-Content $configFiles[0] | ConvertFrom-Json).configuration

    $deleteInstaller        =   $configuration.deleteInstaller
    $downloadFromServer     =   $configuration.downloadFromServer
    $server                 =   $configuration.server
    $supportMultipleArch    =   $configuration.supportMultipleArch
    $version                =   $configuration.version
    $packagePrefix          =   $configuration.packagePrefix
    $packageName            =   $configuration.packageName
    $packageSuffix          =   $configuration.packageSuffix
    $packageExtension       =   $configuration.packageExtension
    $installfile            =   $configuration.installfile
    $forceInstall           =   $configuration.forceInstall
    $setupOptions           =   $configuration.setupOptions
    $customPackagePattern   =   $configuration.customPackagePattern
}

if($supportMultipleArch)    {$arch = "x86_x64"}

$patternHash = @{"%version%" = $version; "%packagePrefix%" = $packagePrefix; "%packageName%" = $packageName; "%packageSuffix%" = $packageSuffix; 
                 "%packageExtension%" = $packageExtension; "%arch%" = $arch}

#here additional steps post completion can be set - in this example the configuration of a standard pdf viewer via the SFTA - script

#if accessing script files use absolut paths or use the $parentDirectory variable to get path of script
$executeAfterCompletion = {
    #example
    #powershell -ExecutionPolicy Bypass -command "& { . $parentDirectory\SFTA.ps1; Set-FTA AcroExch.Document.DC .pdf }"
    #Write-Host "Set Adobe DC as standard for .pdf files."
}

#filename pattern creation
if($packagePrefix)                          {   $filename = "$packagePrefix"+"-"+"$packageName"+"_"+$arch+"_"+"$version"+"$packageExtension"    }
if($packageSuffix)                          {   $filename = "$packageName"+"-"+"$packageSuffix"+"_"+$arch+"_"+"$version"+"$packageExtension"    }
if($packagePrefix -and $packageSuffix)      {   $filename = "$packagePrefix"+"-"+"$packageName"+"_"+"$packageSuffix"+"_"+$arch+"_"+"$version"+"$packageExtension"   }
if(!$packagePrefix -and !$packageSuffix)    {   $filename = "$packageName"+"_"+$arch+"_"+"$version"+"$packageExtension"   }

#replace all keywords in customPackagePattern and set as package/file - name
#also do it for keywords stored in installFile config entry
if($customPackagePattern)                   
{   
    $customPackageName = $customPackagePattern

    foreach($entry in $patternHash.GetEnumerator())
    {
        $customPackageName = $customPackageName.replace($entry.Key,$entry.Value);
        $installFile = $installfile.replace($entry.Key,$entry.Value);
    }

    $filename = $customPackageName
}

if($printPackageName)
{
    Write-Host "Package should be named: '$filename'."

    if(!$generateConfig) {exit}
}

if($generateConfig)
{
    Write-Host "Generating config..."

    $configurationObject = New-Object -TypeName psobject -Property @{

        loadFromConfig         =   $loadFromConfig
        deleteInstaller        =   $deleteInstaller
        downloadFromServer     =   $downloadFromServer
        server                 =   $server
        supportMultipleArch    =   $supportMultipleArch             
        version                =   $version    
        packagePrefix          =   $packagePrefix                  
        packageName            =   $packageName           
        packageSuffix          =   $packageSuffix
        packageExtension       =   $packageSuffix              
        installfile            =   $installfile
        forceInstall           =   $forceInstall
        setupOptions           =   $setupOptions
        $customPackagePattern  =   $customPackagePatter
    }

    $wrapperObject = New-Object -TypeName psobject -Property @{
        configuration = $configurationObject
    }

    $wrapperObject | ConvertTo-Json > .\"$packageName.config.json"

    Write-Host "Saved config under: .\$packageName.config.json"

    exit
}

$header = "Install $packageName - Script $version"
$banner = "#" * $header.Length
Write-Host $banner -ForegroundColor Cyan
Write-Host $header -ForegroundColor Cyan
Write-Host $banner -ForegroundColor Cyan


## check and get Installed Version
$oldProgramm = Get-Package -name $packageName* -ErrorAction Ignore

if ($null -eq $oldProgramm)
{
    write-Host "No $packageName is Installed " -ForegroundColor Red
    write-Host "DO Force Installation" -ForegroundColor Red
    $forceInstall =$true    
}
else
{
	$oldVersion = $oldProgramm.Version
    Write-Host "Installed Version $oldVersion" -ForegroundColor Yellow
}

if (($forceInstall -eq $false) -and ($oldProgramm.Version -eq $version))
{
    Write-Host 'The same Version is currently installed on this Machine.'
    Write-host 'Installaltion Aborted.'

    ## Version welche installiert werden soll ist bereits installiert
    exit 2
}

if($downloadFromServer)
{
    ## wenn das File Bereits Besteht muss die Alte gelöscht werden

    if (Test-Path $installfile)
    {
        Write-Host 'Remove Old Install FIle ' -ForegroundColor Yellow
        Remove-Item -Path $installfile
    }

    ## download File from Deploy Server

    write-host "Download File: $server/$filename  To:  $installfile"  -ForegroundColor Green

    if(!(Test-Path (Split-Path $installfile)))
    {
        New-Item -ItemType Directory -Path (Split-Path $installfile) | Out-Null
    }
    
    Invoke-WebRequest -Uri "$server/$filename" -Outfile $installfile -Verbose
}

## Install software
write-host "Install Program: $programmName Version: $version" -ForegroundColor Green
write-host "Execute $installfile  $setupOptions" -ForegroundColor Yellow
Start-Process $installfile  $setupOptions -Wait


## wenn das File Bereits Besteht muss die Alte gelöscht werden
if ((Test-Path $installfile) -and $deleteInstaller)
{
    Write-Host 'Installer File Deleted.'
    Remove-Item -Path $installfile
}

## Check if File Is installed
$newVersion = Get-Package -name "$programmName*"

if(!$oldVersion)
{
    write-host 'Installed Version ' $newVersion.Version
}
else
{
    write-host 'Upgraded from Version ' $oldVersion.version ' to Version ' $newVersion.Version
}

& $executeAfterCompletion

