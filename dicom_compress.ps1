#requires -version 7
<#
.SYNOPSIS
    The scripts intended use is to backup dicom data.
.DESCRIPTION
    The script cycles through dicom folder structures and compresses the study-folders it finds.
    After compressing the study-folder, the script does create a entry in database containing image information (in this version it will save the date in a hierarchy of csv files.).
    The script can automatically delete source-study-directories, when the compression is finished.
.PARAMETER dicomInput
    The input dicom directory, which will be used as the starting point / source for the compression and repo tasks.
.PARAMETER entryPoint
    At wich layer of the dicom folder, the data processing should happen. eg. 202111 for all studies beginning from November 2021
.PARAMETER blackList
    A list defining file extensions that should be skipped and not be compressed.
.PARAMETER dicomOutput
    The output dicom directory, the destination where the compressed folders will be transferred.
.PARAMETER repoDatabase
    The destination of the Repo Database. Where the created Database is stored, or will be stored.
.PARAMETER deleteSource
    Switch, if source directories should be deleted or not.
.PARAMETER logLocation
    Where the log file(s) is/are stored.
.PARAMETER tempFolder
    Where the compressed files are created and temporarily stored.
.INPUTS
    The dicomInput Folder
.OUTPUTS
    A log file, the repoDB and the DICOM Destination.
.NOTES
    Version:        4.0
    Author:         Dominik Beyerle, Benedikt Wurz
    Creation Date:  23.03.2022
    Purpose/Change: Rewrite of latest script version.
.EXAMPLE
<Example goes here. Repeat this attribute for more than one example>
#>

param
(
    [Parameter(Mandatory = $true)]
    [Alias('dicomIn')]
    [string] $dicomInput,

    [Parameter(Mandatory = $true)]
    [Alias('thrds')]
    [int] $threadCount,

    #[Parameter(Mandatory = $false)]
    #[Alias('from')]
    #[string] $entryPoint,

    [Parameter(Mandatory = $false)]
    [Alias('blkLst')]
    [string] $blackList,

    [Parameter(Mandatory = $false)]
    [Alias('delLst')]
    [string] $deletionList,

    [Parameter(Mandatory = $true)]
    [Alias('dicomOut')]
    [AllowEmptyString()]
    [string] $dicomOutput,

    [Parameter(Mandatory = $true)]
    [Alias('repoDB')]
    [string] $repoDatabase,

    [Parameter(Mandatory = $false)]
    [Alias('delSrc')]
    [Switch] $deleteSource,

    [Parameter(Mandatory = $false)]
    [Alias('log')]
    [string] $logLocation,

    [Parameter(Mandatory = $true)]
    [Alias('tmp')]
    [string]$tempFolder,

    [Parameter(Mandatory = $false)]
    [Alias('sevr')]
    [string]$outputLevel = 5
)

#---------------------------------------------------------[Imports and additional Resources]---------------------------------------

#Dicom-Module is used to extract information from files in dicom-file-format, eg. ima files
Import-Module Dicom

#---------------------------------------------------------[Declaration and Initialisation]-----------------------------------------
#[Script and Log - General]

#Script Name
$sScriptName = $MyInvocation.MyCommand.Name

#Script Version
$sScriptVersion = "4.0"

$firstRun = $true

#Execution Date
$sScriptExecutionDate = Get-Date -Format "dd-MM-yyyy-HH-m"

#Log File Info
#$sLogPath = $logLocation
#$sLogName = ("$sScriptName"+"$sScriptVersion"+"$sScriptExecutionDate"+".log")
#$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#controls in which severity messages should be printed in terminal (1-5) from most important to least important.
$sOutputLevel = 3

#[Globals for Script Execution and Functions]

#Trim all Path Variables
$dicomInput         = $dicomInput.trim('"')
$blackList          = $blackList.trim('"')
$deletionList       = $deletionList.trim('"')
$dicomOutput        = $dicomOutput.trim('"')
$repoDatabase       = $repoDatabase.trim('"')
$logLocation        = $logLocation.trim('"')

#containing directory info for each study folder to compress.
$fromTo             = [System.Collections.Concurrent.ConcurrentDictionary[[System.IO.DirectoryInfo],[System.IO.DirectoryInfo]]]::new()
$markedForDeletion  = [System.Collections.Concurrent.ConcurrentBag[System.IO.DirectoryInfo]]::new()

$imageFileFormats = @("*.ima", "*.dcm")

$blackListed
$deletePatternList

enum FolderStructureLevel
{
    YearMonth   = 0
    Day         = 1
    Patient     = 2
    Study       = 3
    Series      = 4
    Images      = 5
}

enum Marker
{
    Delete   = 0
    Extract  = 1
    Compress = 2
}

#[Regex - Folder Matching]
$regexYearMonth = "^[1-2][0-9][0-9][0-9][0-1][0-9]$"
#$regexDay       = "^[0-3][0-9]$"
$regexPatient   = "^[a-zA-Z]+_[a-zA-Z]+_[a-zA-Z]_[1-2][1-9][1-9][1-9][0-1][0-9][0-3][0-9]$"


#used for dertimining when to archive a study, eg. if minimum age is 365 days the study won't be archived if it's not older than 365 days.
$minimumAge = new-timespan -Days 10

$dicomFields = $("SeriesDescription", "SeriesDate", "Modality", "StudyDate", "StudyTime", "Manufacturer", "InstitutionName", "PatientID", "PatientName",
                "PatientBirthDate", "BodyPartExamined", "StudyID", "StudyInstanceUID", "AccessionNumber", "FileSizeKB")

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function PrintHeader
{
    $width = 45

    $fullString = (("#" * $width) + "$sScriptName - $sScriptVersion" + ("#" * $width)).ToUpper()

    Write-Host $("#" * $fullString.Length) -ForegroundColor Cyan
    Write-Host $fullString -ForegroundColor Cyan
    Write-Host $("#" * $fullString.Length) -ForegroundColor Cyan
}

function PPrint
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('txt')]
        [string] $text,
        [Parameter(Mandatory = $true)]
        [Alias('s')]
        [int] $severity
    )
    if($true -eq $true) #todo ($outputLevel -gt $severity)
    {
        $currentTimeAndDate = Get-Date -Format "dd-MM-yyyy-HH-m-ss"
        $colorToUse

        switch ($severity)
        {
            1 { $colorToUse = "Magenta" }
            2 { $colorToUse = "DarkMagenta" }
            3 { $colorToUse = "Green" }
            4 { $colorToUse = "Yellow" }
            5 { $colorToUse = "Red" }
            Default { $colorToUse = "White" }
        }
        Write-Host ("[{0}]: {1, -25}" -f $currentTimeAndDate, $text) -ForegroundColor $colorToUse
    }
}

function ToRelativeInputPath
{
    param
    {
        [Parameter(Mandatory = $true)]
        [string] $path,
        [Parameter(Mandatory = $true)]
        [string] $dcmIn
    }

    return $path.Replace($dcmIn, "")
}

function DetermineFolderType
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('spec')]
        [System.IO.FileSystemInfo] $toSpecify,
        [Parameter(Mandatory = $true)]
        [String] $dcmIn
    )

    $pathRelative = $toSpecify.FullName.Replace($dcmIn, "")
    $pathArray = $pathRelative.Split("\")

    $count = $pathArray.Length - 1

    switch ($count)
    {
        1 {return [FolderStructureLevel]::YearMonth}
        2 {return [FolderStructureLevel]::Day}
        3 {return [FolderStructureLevel]::Patient}
        4 {return [FolderStructureLevel]::Study}
        5 {return [FolderStructureLevel]::Series}
        6 {return [FolderStructureLevel]::Images}
        Default {Write-Host "Nothing found...."}
    }
}

function IsFolder
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('spec')]
        [System.IO.FileSystemInfo] $toSpecify
    )

    if(Test-Path -Path $toSpecify.FullName -PathType Container)
    {
        return $true
    }
    else
    {
        return $false
    }
}

#Takes File System Info and checks if name matches any of determined file extensions.
function IsImage
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('spec')]
        [System.IO.FileSystemInfo] $toSpecify
    )

    $isIMA = $toSpecify.Name.EndsWith(".ima");
    $isDCM = $toSpecify.Name.EndsWith(".dcm");

    return ($isIMA -or $isDCM)
}

function WriteRepoFile
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('ftit')]
        [Array] $imageFiles,
        [Parameter(Mandatory = $true)]
        [String] $dcmIn,
        [Parameter(Mandatory = $true)]
        [String] $repoDB,
        [Parameter(Mandatory = $true)]
        [String] $temp,
        [Parameter(Mandatory = $true)]
        [Array] $dicomF
    )

    $studyFolder = GetParent $imageFiles[0]
    $studyName = $studyFolder.Name
    $relativePath = $studyFolder.Parent.FullName.Replace($dcmIn, "")

    $csvFileName = "$studyName.csv"
    $destinationDirectory = Join-Path $repoDB -ChildPath $relativePath
    $destinationFile = Join-Path $destinationDirectory -ChildPath $csvFileName

    New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null

    $repoFileAlreadyExists = Test-Path $destinationFile

    if($repoFileAlreadyExists)
    {
        return $false
    }
    else
    {
        $value = ""
        foreach($image in $imageFiles)
        {
            $value += ((GetDicomValues -dicomFilePath $image -dicomF $dicomF) + "`n")
        }
        [System.IO.FileInfo](New-Item -Path $destinationDirectory -Name $csvFileName -ItemType "file" -Value ((GetDicomFieldNames) + "`n" + $value))
        return $true
    }
}

function ClearTempFolder
{
    foreach($file in Get-ChildItem "$tempFolder/repo")
    {
        if((IsFileAlreadyInUse $file) -eq $false)
        {
            Remove-Item $file.FullName
        }
    }
}

function CreateStructureInTempFolder
{
    $repoAtTempExists = Test-Path "$tempFolder\repo"

    if(!$repoAtTempExists)
    {
        New-Item -Path "$tempFolder" -Name "repo" -ItemType Directory | Out-Null
    }
}

function GetParent
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('io')]
        [System.IO.FileSystemInfo] $ioName
    )

    $item = Get-Item -Path $ioName.FullName

    if(IsFolder $ioName)
    {
        return $item.Parent
    }
    else
    {
        return $item.Directory.Parent
    }
}

#Takes File System Info and checks if folder is a patient-folder by matching a regex pattern and checking if parent is day folder.

function GetExlusionList
{
    $list

    foreach($rex in $blackListed)
    {
        $list += "$rex,"
    }

    if($list.Length > 0)
    {
        return $list.Substring(0, $list.Length-1)
    }
    else
    {
        return ""
    }
}


#returns an array of file extensions which are defined in the blacklist file
function ReadBlackList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('blkLst')]
        [string] $blkList
    )

    $extensionArray = @()

    foreach($line in Get-Content $blkList)
    {
        $extensionArray += "$line";
    }

    return $extensionArray;
}

function ReadDeletionList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string] $delList
    )

    $dels = @()

    foreach($line in Get-Content $delList)
    {
        $dels += $line
    }

    return $dels
}

#reads given dicom file per path and returns a string containg its field names for use in csv creation
function GetDicomFieldNames
{
    $returnValue = ""

    foreach($field in $dicomFields)
    {
        $returnvalue += "$field;"
    }

    return $returnValue.Substring(0,$returnValue.Length-1)
}

#reads given dicom file per path and returns a string containing its values for use in csv creation
function GetDicomValues
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('dcmFile')]
        [string] $dicomFilePath,
        [Parameter(Mandatory = $true)]
        [Array] $dicomF
    )

    $dicomFile      = Import-Dicom -Filename $dicomFilePath
    $dicomObject    = Read-Dicom -DicomFile $dicomFile

    $returnValue = ""



    foreach($field in ($dicomF | Select-Object -First ($dicomF.Length -1)))
    {
        $value = $dicomObject.$field

        if($value -eq $null)
        {
            $returnValue += "empty;"
        }
        else
        {
            $returnValue += ($value.ToString() + ";")
        }
    }

    $returnValue += (Get-Item $dicomFilePath).length/1KB

    return $returnValue
}

function Compress
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias('studyDir')]
        [System.IO.FileSystemInfo] $studyDirectory,
        [Parameter(Mandatory = $true)]
        [String] $dcmIn,
        [Parameter(Mandatory = $true)]
        [String] $dcmOut,
        [Parameter(Mandatory = $true)]
        [Array] $blackList,
        [Parameter(Mandatory = $true)]
        [string] $repoDatabase,
        [Parameter(Mandatory = $false)]
        [bool] $delSource
    )

    $studyName = $studyDirectory.Name
    #Write-Host "$studyName"
    #gets the current relative path up to patient level
    $currentRelativePath = (GetParent $studyDirectory).FullName.Replace($dcmIn, "")
    #joins path of destination path, with relative path
    $destPath = Join-Path $dcmOut -ChildPath $currentRelativePath
    #joins path with archive-name
    $destArchive = Join-Path $destPath -ChildPath "$studyName.zip"

    #tests if given file is a directory
    $isDir = $studyDirectory.PSIsContainer -eq $true
    #tests if the dir isn't already a zip file
    $dirNotZip = "$studyDirectory".EndsWith('.zip') -ne $true
    #tests if the study is not already in compressed form at destination repo
    $notAlreadyAtRepoComp = ((Test-Path -Path $destPath -PathType Leaf) -eq $false)
    #tests if the study is not already at destination repo
    $notAlreadyAtRepo = ((Test-Path -Path $destPath) -eq $false)
    #tests if csv file is already created, when yes do not compress
    $pathToCSV = Join-Path $repoDatabase -ChildPath $currentRelativePath -AdditionalChildPath "$studyName.csv"
    $CSVRepoEntryExists = ((Test-Path -Path "$pathToCSV"))

    if($CSVRepoEntryExists)
    {
        PPrint "Study: $studyName.csv is already at repo db... skipping compression." -s 3
        return $null
    }

    if(!$notAlreadyAtRepoComp)
    {
        PPrint "Study: $sutdyName is already compressed at repo... skipping compression." -s 3
        return $null
    }

    if(!$notAlreadyAtRepo)
    {
        PPrint "Study: $studyName is already stored at repo... skipping compression." -s 3
        return $null
    }

    if(!($dirNotZip -and $isDir))
    {
        return $null
    }

    #create directory
    New-Item -Path $destPath -ItemType Directory | Out-Null
    #get all direcotries and files of study directory, exclude blacklisted file extensions -> Compress Archive with 0 Compression
    #Compress-Archive $studyDirectory.FullName -DestinationPath $destArchive -CompressionLevel "NoCompression" -Force
    Compress-Archive $studyDirectory.FullName -DestinationPath $temp -CompressionLevel "NoCompression" -Force

    $fromToTup = [System.Tuple]::Create("$temp\$studyname.zip","$destPath")

    return $fromToTup
}

function IsOnDeletionList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo] $file,
        [Parameter(Mandatory = $true)]
        [array] $delList
    )

    foreach($pattern in $delList)
    {
        if($file.Name -like $pattern)
        {
            return $true
        }
    }

    return $false
}

function GetYearMonthDirectories
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $dicomDir
    )

    $yearMonthList = (Get-ChildItem -Path $dicomDir.FullName -Directory) | Where-Object {$_.Name -Match $regexYearMonth}

    return $yearMonthList
}

function GetDayDirectories
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $yearMonthDir
    )

    $dayList = Get-ChildItem -Path $yearMonthDir.FullName -Directory

    return $dayList

}

function GetPatientDirectories
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $dayDir
    )

    $patientList = Get-ChildItem -Path $dayDir.FullName -Directory #| Where-Object {$_.Name -Match $regexPatient}

    return $patientList
}

function GetStudyDirectories
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $patientDir
    )

    $studyList = Get-ChildItem -Path $patientDir.FullName -Directory

    return $studyList
}

function GetSeriesDirectories
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $studyDir
    )

    $seriesList = Get-ChildItem -Path $studyDir.FullName -Directory

    return $seriesList
}

function GetImages
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $seriesDir
    )

    $imageList = Get-ChildItem -Path ($seriesDir.FullName + "\*") -File -Include $imageFileFormats

    return $imageList
}



function WriteRepoFilesForPatient
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $patient
    )

    foreach($study in (GetStudyDirectories $patient))
    {
        $toWrite = @()
        foreach($series in (GetSeriesDirectories $study))
        {
            $imageList = GetImages $series
            if($imageList.Count -gt 0)
            {
                $indexToChoose = ([math]::floor((($imageList.Count) / 2)) -1)
                $targetImage = $imageList[$indexToChoose]
                $toWrite += $imageList[(($imageList.Count -1) / 2)]
            }
        }

        if($toWrite.Count -gt 0)
        {
            $writtenRepoFile = WriteRepoFile $toWrite $dicomInput $repoDatabase $tempFolder $dicomFields

            if($writtenRepoFile)
            {
                PPrint "Written Repo File for Study $study." -severity 3
            }
            else
            {
                PPrint "Didnt write Repo File for Study $study, because it already exists." -severity 3
            }
        }
    }
}

function WriteRepoFilesForPatientList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Array] $patientList
    )

    foreach($patient in $patientList)
    {
        PPrint ("[x] Processing Repo File Creation for Patient:" + $patient.Name) -severity 4
        WriteRepoFilesForPatient $patient
    }
}

function ClearMarkerCollections
{
    $markedForDeletion.Clear()
}

function CleanUpStudyDir
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Array] $studyDir,
        [Parameter(Mandatory = $true)]
        [Array] $deletePatternList
    )

    $filesToDelete = (Get-ChildItem -Path ($studyDir.FullName + "\*") -Include $deletePatternList -Recurse -File)

    foreach($file in $filesToDelete)
    {
        if(Test-Path $file.FullName)
        {
            Remove-Item -Force $file
            $fName = $file.Name
            PPrint "Removed Garbage: $fName." -severity 5
        }
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

PrintHeader

CreateStructureInTempFolder

$blackListed            = ReadBlackList $blackList
$deletePatternList      = ReadDeletionList $deletionList
$lostAndFoundPatients   = @()

#Define Functions as String
$pprintDef                  = ${function:PPrint}.ToString()
$compressDef                = ${function:Compress}.ToString()
$getParentDef               = ${function:GetParent}.ToString()
$toRelativeInputPathDef     = ${function:ToRelativeInputPath}.ToString()
$isFolderDef                = ${function:IsFolder}.ToString()
$getExclusionDef            = ${function:GetExlusionList}.ToString()

$getStudyDirectoriesDef     = ${function:GetStudyDirectories}.ToString()
$getSeriesDirectoriesDef    = ${function:GetSeriesDirectories}.ToString()
$cleanUpStudyDirDef         = ${function:CleanUpStudyDir}.ToString()

foreach($yearMonth in (GetYearMonthDirectories $dicomInput))
{
    foreach($day in (GetDayDirectories $yearMonth))
    {
        PPrint ("[x] Current Path: " + $day.FullName.Replace($dicomInput, "")) -severity 1

        $patientDirectories = GetPatientDirectories -dayDir $day

        $patientDirectories | ForEach-Object -ThrottleLimit $threadCount -Parallel{

            ${function:Compress}                = $using:compressDef
            ${function:ToRelativeInputPath}     = $using:toRelativeInputPathDef
            ${function:GetParent}               = $using:getParentDef
            ${function:PPrint}                  = $using:pprintDef
            ${function:IsFolder}                = $using:isFolderDef
            ${function:GetExlusionList}         = $using:getExclusionDef
            ${function:GetStudyDirectories}     = $using:getStudyDirectoriesDef
            ${function:GetSeriesDirectories}    = $using:getSeriesDirectoriesDef
            ${function:CleanUpStudyDir}         = $using:cleanUpStudyDirDef

            foreach($study in GetStudyDirectories -patientDir $_)
            {
                #Step 2: Deletion (Delete Files that shouldn't be included in archives + cleanup.).
                PPrint ("[x] Cleaning up directory (" + $study.Name + ") pre-compression...") -severity 4
                CleanUpStudyDir $study ($using:deletePatternList)

                #Step 3: Compression of studies.
                PPrint ("[x] Deciding if study: " + $study.Name + " will be compressed.") -severity 4
                $fromToTup = Compress $study ($using:dicomInput) ($using:dicomOutput) ($using:blackListed) ($using:repoDatabase) -delSource ($using:deleteSource)

                if($fromToTup -ne $null)
                {
                    ($using:fromTo).TryAdd($fromToTup.Item1, $fromToTup.Item2)
                }

                if((($using:deleteSource) -eq $true) -and ($fromToTup -ne $null))
                {
                    ($using:markedForDeletion).Add($study)
                }
            }
        }

        #Step 4: Move Compressed Archives to Destination

        foreach($toCopy in $fromTo.GetEnumerator.GetEnumerator())
        {
            Move-Item -Path $toCopy.Key.FullName -Destination $toCopy.Value.FullName
            PPrint ("Moved Directory: " + $toCopy.Key.Name + " from Temp Folder to Destination.")
        }

        #Step 5: Metadata Extraction - Repo File Creation.
        WriteRepoFilesForPatientList $patientDirectories

        if($deleteSource)
        {
            foreach($sourceFolder in $markedForDeletion)
            {
                if(Test-Path $sourceFolder.FullName)
                {
                    Remove-Item -Recurse -Force -Path $sourceFolder.FullName
                    PPrint "Deleted $sourceFolder, because *Delete Source* Switch is enabled." -severity 5
                }
            }
        }

        ClearMarkerCollections

        #Garbage collection
        [System.gc]::Collect()
    }
}

#Log-Finish -LogPath $sLogFile