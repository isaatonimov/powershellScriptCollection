# PowerShell Depolyment Script - Boilerplate
#
# @version: 4.0
# @autor Dominik Beyerle
# @LastModified 10.03.2022
# @Info: 
#        Imports Hosts lists in csv format, then executes powershell script over psexec on all hosts
#        updates status of csv list and overrides the given csv.
#        Takes Username, csvPath and scriptfile-location as parameters
#        Password will be prompted once
#
#        you can define location / domain-name aliases
#        csv lists can be scraped from glpi and have to contain: name | location | ip |
#
[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [string] $userName,
    [Parameter(Mandatory=$true)]
    [string] $scriptFile,
    [Parameter(Mandatory=$true)]
    [string] $csvPath,
    [Parameter(Mandatory=$false)]
    [switch] $automaticWakeUp
)

function WakeUpIfOffline()
{
    param
    (
        [Parameter(Mandatory=$true)]
        [array] $hostObjects
    )

    Import-Module ".\magic_packets.psm1" -Force

    Write-Host "Automatic Wake Up is activated, testing connections to hosts."


    for($i = 0; $i++; $i -eq 2)
    {
        foreach($hostO in $hostObjects)
        {
            if($hostO.isUp -eq $true)
            {
                Write-Host ("{0} already up, not checking." -f $hostO.name)
            }
            elseif(Test-Connection $hostO.ip -Quiet)
            {
                Write-Host ("{0} up." -f $hostO.name)
            }
            else
            {
                Write-Host ("{0} is down. Waking up" -f $hostO.name)
                Invoke-WakeOnLan -MacAddress $mac
            }
        }
    }


}

$psExecLocation             = "C:\Windows\System32\PsExec.exe"  #the location of the psexec.exe
$hostsPerLocation           = 20                                #how many hosts per location to update

$csvPath = $csvPath.trim('"')
$csvData = Import-Csv -Path $csvPath -Delimiter ";"

$password  = Read-Host "Type in Password for User $userName"
Clear-Host

#for powershell
$psExecCommandList  = @("powershell.exe -noprofile -executionpolicy bypass -file $scriptFile")

#for batch
#$psExecCommandList  = @("$scriptFile")

$psExecCommandLine = ""

for($i=0; $i -lt $psExecCommandList.length; $i++)
{
    if($i -eq $psExecCommandList.length -1)
    {
        $psExecCommandLine += $psExecCommandList[$i]
    }
    else 
    {
        $psExecCommandLine += $psExecCommandList[$i] + " ^& "
    }
}

$hosts          = @()
$domains        = @{#obfuscated}

$domainCounter  = @{#obfuscated}

foreach($line in $csvData)
{
    $hosti = New-Object -TypeName psobject -Property @{
        name        = $line.name
        location    = $line.location
        ip          = $line.ip
        status      = $line.status
        isUp        = $false
    }

    $hosts += $hosti
}


$domainToUse
$locationName

$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $psExecLocation
$pinfo.RedirectStandardError = $true
$pinfo.RedirectStandardOutput = $true
$pinfo.UseShellExecute = $false

foreach($h in $hosts)
{
    foreach($entry in $domains.GetEnumerator())
    {
        if($h.location -match $entry.Key)
        {
            $domainToUse = $entry.Value
            $locationName = $entry.Key
        }
    }

    $currentHostIp = $h.ip

    Write-Host ("Trying to establish Connection to Host {0}, with IP: {1}" -f $h.name, $h.ip)

    if((!($h.status)) -and ($h.ip) -and (Test-Connection $h.ip -Quiet) -and ($domainCounter[$locationName] -le $hostsPerLocation))
    {
        $domainCounter[$locationName]++ #increase location counter, don't allow more than $hostsPerLocation - executions.

        $pinfo.Arguments = "\\$currentHostIp -u $domainToUse\$userName -p $password -s cmd /c ($psExecCommandLine)"

        $hiddenPasswordArguments = "\\$currentHostIp -u $domainToUse\$userName -p ******* -s cmd /c ($psExecCommandLine)"

        Write-Host ("Trying to execute the following in psexec: {0}" -f $hiddenPasswordArguments)

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()

        Write-Host $stdout

        $exitCode = $p.ExitCode

        if($exitCode -eq 0)
        {
            $h.status = "Script executed successfully."
        }
        elseif($exitCode -eq 1)
        {
            $h.status = "Error ocurred."
        }
        elseif ($exitCode -eq 2)
        {
            $h.status = "Already uptodate."
        }
        else
        {
            $h.status = "Exit Code: $exitCode, unkown."
        }

        Write-Host ($h.status)
    }
    else
    {
        $h.status = "Not reachable."
    }
}

#Write New csv list

#Write-Host "List will be overwritten."

#"name;location;ip;status" | Out-File -FilePath $csvPath -Force
#foreach($h in $hosts){ ("{0};{1};{2};{3}" -f $h.name, $h.location, $h.ip, $h.status) | Out-File -FilePath $csvPath -Append -Force}