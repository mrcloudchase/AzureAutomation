[CmdletBinding(SupportsShouldProcess = $true)]
param
    (
        [Parameter(Mandatory = $true)][string]$stgAcctName,
        [Parameter(Mandatory = $true)][string]$stgRgName,
        [Parameter(Mandatory = $true)][string]$tenantId
    )

Install-Module az -Force
Connect-AzAccount -TenantId $tenantId

$stgAcctKey = (Get-AzStorageAccountKey -ResourceGroupName $stgRgName -Name $stgAcctName).Value[0]
$context = New-AzStorageContext -StorageAccountName $stgAcctName -StorageAccountKey $stgAcctKey
$shares = Get-AzStorageShare -Context $context | Where-Object IsSnapshot -NE $true
function doWork()
{
$fileinfor =@{ShareCount=0;AzureFilesTotalUsage=0}

foreach($share in $shares) {
$shareName = $share.Name
$shareBytes = (Get-AzRmStorageShare -ResourceGroupName $stgRgName -StorageAccountName $stgAcctName -ShareName $shareName -GetShareUsage).ShareUsageBytes
Write-Output "Share Name: $shareName"
Write-Output "Share Usage: $shareBytes"
Write-Output ""
$fileinfor["ShareCount"]++
$fileinfor["AzureFilesTotalUsage"]=$fileinfor["AzureFilesTotalUsage"]+$shareBytes
$fInfo = $fileinfor
Write-Output $fInfo
}
$gTotal = $fInfo["AzureFilesTotalUsage"]
Write-Output "Grand Total: $gTotal"
}

doWork($stgAcctName,$stgRgName) 
