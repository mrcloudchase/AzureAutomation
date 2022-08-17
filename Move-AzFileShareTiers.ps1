<#
.DESCRIPTION
A PowerShell script that copies and moves files between Azure file shares/tiers on a custom-defined number of seconds and schedule.
This script leverages azcopy to copy files from one Azure file share to another Azure file share.
Copying of files will be based on the last access time SMB metadata
Only the files NOT accessed for custom-defined number of seconds will be copied to the destination file share, and then deleted from the source file share.
This AzCopy operation is running in an ACI (Container Instance) using Service Principal in Azure AD.

.NOTES
Filename : Move-AzFileShareTier.ps1
Author   : Chase Dovey (Sr. Cloud Architect)
Version  : 0.0.1
Date     : 2022-08-15
Pre-reqs : Storage Account requires public access on network firewall settings, Role Assignment of Storage Key Operator on subscription, and Role assignement of Contributor on Storage Account.
Notes    : Could attempt to provide connectivity to Azure Storage Account from Automation Account using Private Endpoint or Hybrid Runbook Worker.
Warning  : This script will overwrite files in the destination file share if they already exist in the destination file share prior to the copy.

.LINK
#>

Param (
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
    [String] $sourceAzureSubscriptionId,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
    [String] $sourceStorageAccountRG,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
    [String] $targetStorageAccountRG,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
    [String] $sourceStorageAccountName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
    [String] $targetStorageAccountName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
    [String] $sourceStorageFileShareName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
    [String] $targetStorageFileShareName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
    [Int] $numberOfSeconds
)

# Prevents the inheritance of an AzContext in the runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with the system-assigned managed identity that represents the Automation Account
Connect-AzAccount -Identity

# Set the Azure Subscription context using Subsciption ID
Set-AzContext -SubscriptionId "$sourceAzureSubscriptionId"

#! Start - Source Storage Account
# Get the primary Source Storage Account Key
$sourceStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $sourceStorageAccountRG -Name $sourceStorageAccountName).Value[0]

# Create new Azure Storage Context
$sourceContext = New-AzStorageContext -StorageAccountKey $sourceStorageAccountKey -StorageAccountName $sourceStorageAccountName

# Generate source file share SAS URI Token with read, delete, and list permission w/ an expiration of 1 day
$sourceShareSASURI = New-AzStorageAccountSASToken -Context $sourceContext `
    -Service File -ResourceType Service,Container,Object -ExpiryTime(get-date).AddDays(1) -Permission "rdl"
$sourceShareSASURI = $sourceShareSASURI.Split('?')[-1]

# List Directories and Files on the source file share - defaults to public endpoint if not private endpoint in place
$URI = "https://$sourceStorageAccountName.file.core.windows.net/$($sourceStorageFileShareName)?comp=list&restype=directory&include=timestamps&$($sourceShareSASURI)"
$response = Invoke-RestMethod $URI -Method 'GET'

# Fix XML Response body
$fixedXML = $response.Replace('ï»¿<?xml version="1.0" encoding="utf-8"?>','<?xml version=''1.0'' encoding=''UTF-8''?>')
$doc = New-Object xml
$doc = [xml]$fixedXML
if($doc.FirstChild.NodeType -eq 'XmlDeclaration') {
    $doc.FirstChild.Encoding = $null
}

#! Start - Target Storage Account
# Get Target Storage Account Key
$targetStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $targetStorageAccountRG -Name $targetStorageAccountName).Value[0]

# Create new Target Azure Storage Context
$destinationContext = New-AzStorageContext -StorageAccountKey $targetStorageAccountKey -StorageAccountName $targetStorageAccountName

# Generate target SAS URI with read, write, delete, create, and list permission
$targetShareSASURI = New-AzStorageShareSASToken -Context $destinationContext `
    -ExpiryTime(get-date).AddDays(1) -ShareName $targetStorageFileShareName -Permission "rwdcl"

# Construct old date based on the current date/time minus the custom-defined number of seconds
$old = ((Get-Date).ToUniversalTime()).AddSeconds(-$numberOfSeconds)
$oldDate = $old.ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")

# The container image (peterdavehello/azcopy:latest) is publicly available on Docker Hub and has the latest AzCopy version installed
# You could also create your own private container image and use it instead
# When you create a new container instance, the default compute resources are set to 1vCPU and 1.5GB RAM
# For larger file shares (e.g. 1-3 TB) try starting with 2vCPU and 4GB memory
# You may need to adjust the CPU and memory based on the size and churn of your file share
# The container will be created in the $location variable based on the source storage account location. Adjust if needed.
$location = (Get-AzResourceGroup -Name $sourceStorageAccountRG).location

# Container Group Name
$containerGroupName = $sourceStorageFileShareName + "-azcopy-job"

# Set the AZCOPY_BUFFER_GB value at 2 GB which would prevent the container from crashing.
$envVars = New-AzContainerInstanceEnvironmentVariableObject -Name "AZCOPY_BUFFER_GB" -Value "2"

# # Set variables for progress tracking
# $TotalItems=$doc.EnumerationResults.entries.file.Count
# $CurrentItem = 0
# $PercentComplete = 0

# Function to Write Output of $doc XML object to console for debugging XML response body
function WriteXmlToScreen ([xml]$xml)
{
    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
    $XmlWriter.Formatting = "indented";
    $xml.WriteTo($XmlWriter);
    $XmlWriter.Flush();
    $StringWriter.Flush();
    Write-Output $StringWriter.ToString();
}
$xml = $doc
WriteXmlToScreen $xml

# Iterate through the list of files and directories
foreach ($file in $doc.EnumerationResults.entries.file) {

    # # Write progress to the console
    # Write-Progress -Activity "Moving Files..." -Status "$PercentComplete% Complete:" -PercentComplete $PercentComplete
    # $CurrentItem++
    # $PercentComplete = [int](($CurrentItem / $TotalItems) * 100)
    
    # Write output to the console
    $fileName = $file.Name
    Write-Output "Processing file: $fileName"

    # If the file LastAccessTime is less than or equal to the number of seconds, then move it to the destination file share
    if ($file.properties.LastAccessTime -le $oldDate) {
    
    # Set the source file path
    $sourceFile = "https://$sourceStorageAccountName.file.core.windows.net/$sourceStorageFileShareName/$($file.name)?$($sourceShareSASURI)"
    # Set the destination file path
    $targetFile = "https://$targetStorageAccountName.file.core.windows.net/$targetStorageFileShareName/$($file.name)$($targetShareSASURI)"
    
    # Command to copy the file to the target file share and preserve smb metadata
    $command1 = "azcopy","copy",$sourceFile,$targetFile,"--preserve-smb-info","--preserve-smb-permissions"
    # Command to remove the file from the source file share
    $command2 = "azcopy","remove",$sourceFile

    # Create Azure Container Instance Object to run $command1
    $container = New-AzContainerInstanceObject `
        -Name $containerGroupName `
        -Image "peterdavehello/azcopy:latest" `
        -RequestCpu 2 -RequestMemoryInGb 4 `
        -Command $command1 -EnvironmentVariable $envVars

    # Create Azure Container Group and copy the file to the target file share
    $containerGroup = New-AzContainerGroup -ResourceGroupName $sourceStorageAccountRG -Name $containerGroupName `
        -Container $container -OsType Linux -Location $location -RestartPolicy never

    # Recreate Azure Container Instance Object to run $command2
    $container = New-AzContainerInstanceObject `
        -Name $containerGroupName `
        -Image "peterdavehello/azcopy:latest" `
        -RequestCpu 2 -RequestMemoryInGb 4 `
        -Command $command2 -EnvironmentVariable $envVars

    # Recreate the same Azure Container Group and remove the file from the source file share
    $containerGroup = New-AzContainerGroup -ResourceGroupName $sourceStorageAccountRG -Name $containerGroupName `
        -Container $container -OsType Linux -Location $location -RestartPolicy never
    }
}

Write-Output ("")
