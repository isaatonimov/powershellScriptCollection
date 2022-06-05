#Author: Dominik Beyerle
#Last Edit: 23.03.2022
#Function: Counts how many files of given file extension are in directory.

param
(
    [Parameter(Mandatory = $true)]
        [string] $inputDirectory,       #eg  :  c:\xr50\report
    [Parameter(Mandatory = $true)]
        [string] $fileExtension         #eg. : .edi
)

$inputDirectory = $inputDirectory.trim('"')

#init data wrapper - required by zabbix json schema
$dataWrapper = New-Object psobject

$fileCount = (Get-ChildItem $inputDirectory -File | Where-Object {$_.Extension -in "$fileExtension"}).Count

$fileCountObject = New-Object psobject -Property @{
    "{#FILECOUNT}"  = $fileCount
}

#adds extension count to dataWrapper
$dataWrapper | Add-Member -NotePropertyName data -NotePropertyValue $fileCountObject

#init jsonObject, save dataWrapper object in json format
$jsonObject = ConvertTo-Json -InputObject $dataWrapper

Write-Host $jsonObject