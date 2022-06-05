#Small script for sending dicom data over dcmtk send


param(
    $inputDicomFolder,
    $server
)

New-Item -ItemType File -Name "dicom_send.log" -Path .

Write-Host "Starting Copying DICOM Files"
$startDate = Get-Date
$endDate

Write-Host $startDate
Write-Output "Start Time: $startTime" >> ".\dicom_send.log"

.\dcmsend.exe -v +sd -aec TESTDICOM $server 4000 --recurse $inputDicomFolder

$endDate = Get-Date
Write-Host "Finished Copying DICOM Files"
Write-Host $endDate
Write-Output "End Time: $endDate" >> ".\dicom_send.log"