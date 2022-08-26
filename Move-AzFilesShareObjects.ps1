[CmdletBinding(SupportsShouldProcess = $true)]
Param (
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String] $sourceAzureSubscriptionId,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String] $sourceStorageAccountName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String] $targetStorageAccountName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String] $sourceStorageFileShareName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String] $targetStorageFileShareName,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][Int] $numberOfSeconds
)

#! Functions
# Function to list sub-directories to recursively get all files and directories
function list_subdir([Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageFileDirectory]$dirs) {
    
    # Store directory path in a variable
    $path = $dirs.ShareDirectoryClient.Path
    # Store share name in a variable
    $shareName = $dirs.ShareDirectoryClient.ShareName
    # Get all files/sub-directories in the directory and store as an array in a variable
    $filesAndDirs = Get-AzStorageFile -ShareName "$shareName" -Path "$path" -Context $sourceContext | Get-AzStorageFile
    
    # Iterate through all files/sub-directories in the $fileAndDirs variable with array data type
    foreach ($f in $filesAndDirs) {

        # If the $f is a file, then compare filedate to olddate and operate on old files, Else if $f is a directory, then recursively call the list_subdir function
        if ($f.gettype().name -eq "AzureStorageFile") {

            # Get the file SMB property of LastWriteTime and store in a variable
            $fileDate = $($f.FileProperties.SmbProperties.FileLastWrittenOn.DateTime).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")

            # If the $fileDate is <= (older than/or as old as) $oldDate, then do this...
            if ($fileDate -le $oldDate) {

                #Get the file path and save to variable"
                $filePath = $($f.ShareFileClient.Path)
                $shareName = $($f.ShareFileClient.ShareName)
                $storageAccountName = $($f.ShareFileClient.AccountName)

                # Run copy operation here to work on files that meet criteria
                # Set the source file path
                $sourceFile = "https://$StorageAccountName.file.core.windows.net/$shareName/$($filePath)$($sourceShareSASURI)"
                # Set the destination file path
                $targetFile = "https://$targetStorageAccountName.file.core.windows.net/$targetStorageFileShareName/$($filePath)$($targetShareSASURI)"
                
                # Write-Output "Source File: $sourceFile"
                # Write-Output "Target File: $targetFile"
                Write-Output "File Path: $filePath"
                Write-Output "Source File: $sourceFile"
                Write-Output "Target File: $targetFile"
                Write-Output ""
                # Command to copy the file to the target file share and preserve smb metadata
                $command1 = "azcopy","copy",$sourceFile,$targetFile,"--preserve-smb-info","--preserve-smb-permissions","--recursive"
                # Command to remove the file from the source file share
                $command2 = "azcopy","remove",$sourceFile

                # Create Azure Container Instance Object to run $command1
                $container = New-AzContainerInstanceObject `
                    -Name $containerGroupName1 `
                    -Image "peterdavehello/azcopy:latest" `
                    -RequestCpu 2 -RequestMemoryInGb 4 `
                    -Command $command1 -EnvironmentVariable $envVars

                # Create Azure Container Group and copy the file to the target file share
                $containerGroup1 = New-AzContainerGroup -ResourceGroupName $sourceStorageAccountRG -Name $containerGroupName1 `
                    -Container $container -OsType Linux -Location $location -RestartPolicy never

                # Recreate Azure Container Instance Object to run $command2
                $container = New-AzContainerInstanceObject `
                    -Name $containerGroupName2 `
                    -Image "peterdavehello/azcopy:latest" `
                    -RequestCpu 2 -RequestMemoryInGb 4 `
                    -Command $command2 -EnvironmentVariable $envVars

                # Recreate the same Azure Container Group and remove the file from the source file share
                $containerGroup2 = New-AzContainerGroup -ResourceGroupName $sourceStorageAccountRG -Name $containerGroupName2 `
                    -Container $container -OsType Linux -Location $location -RestartPolicy never

            }else{
                Write-Output "No Old Files :)"
            }

        }
        elseif ($f.gettype().name -eq "AzureStorageFileDirectory") {
            
            # Call the list_subdir function to recursively get all files and directories in the directory
            list_subdir($f)

        }

    }

}

#! VARIABLE DECLARATIONS
#! Setup identity context for the subscription
# Prevent the inheritance of an AzContext from the current process
Disable-AzContextAutosave -Scope Process
# Connect to Azure with the system-assigned managed identity that represents the Automation Account
Connect-AzAccount -Identity
# Set the Azure Subscription context using Azure Subsciption ID
Set-AzContext -SubscriptionId "$sourceAzureSubscriptionId"

# Get Storage Account Resource Group
$sourceStorageAccountRG = (Get-AzResource -Name "$sourceStorageAccountName").ResourceGroupName
$targetStorageAccountRG = (Get-AzResource -Name "$targetStorageAccountName").ResourceGroupName
Write-Output $targetStorageAccountRG
#! Setup context for the source storage account and generate a SAS token for the source storage account
# Get the primary Azure Storage Account Key from the source storage account

$sourceStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $sourceStorageAccountRG -Name $sourceStorageAccountName).Value[0]
# Create a new Azure Storage Context for the source storage account, which is required for Az.Storage Cmdlets
$sourceContext = New-AzStorageContext -StorageAccountName $sourceStorageAccountName -StorageAccountKey $sourceStorageAccountKey
# Get all Azure Files shares using the Storage Context and save as an array in a variable
$shares = Get-AzStorageShare -Context $sourceContext | Where-Object { $_.Name -ne $targetStorageFileShareName }
# Generate source file share SAS URI Token with read, delete, and list permission w/ an expiration of 1 day
$sourceShareSASURI = New-AzStorageAccountSASToken -Context $sourceContext `
    -Service File -ResourceType Service, Container, Object -ExpiryTime(get-date).AddDays(1) -Permission "rdl"
# $sourceShareSASURI = $sourceShareSASURI.Split('?')[-1]

#! Setup context for the target storage account and generate a SAS token for the target storage account
# Get the primary Azure Storage Account Key from the target storage account
$targetStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $targetStorageAccountRG -Name $targetStorageAccountName).Value[0]
# Create a new Azure Storage Context for target storage account, which is required for Az.Storage Cmdlets
$destinationContext = New-AzStorageContext -StorageAccountKey $targetStorageAccountKey -StorageAccountName $targetStorageAccountName
# Generate target SAS URI with read, write, delete, create, and list permission w/ an expiration of 1 day
$targetShareSASURI = New-AzStorageShareSASToken -Context $destinationContext `
    -ExpiryTime(get-date).AddDays(1) -ShareName $targetStorageFileShareName -Permission "rwdcl"
Write-Output $sourceShareSASURI
Write-Output $targetShareSASURI
#! Azure Container Instance Variables
# Set the location using the source storage account RG location
$location = (Get-AzResourceGroup -Name $sourceStorageAccountRG).location
# Container Group Name
$containerGroupName1 = $sourceStorageFileShareName + "-azcopy"
$containerGroupName2 = $sourceStorageFileShareName + "-azcopyrm"
# Set the AZCOPY_BUFFER_GB value at 2 GB which would prevent the container from crashing.
$envVars = New-AzContainerInstanceEnvironmentVariableObject -Name "AZCOPY_BUFFER_GB" -Value "2"


#! Setup Lifecycle Management Operation Date
# Get current time, subtract $numberOfSeconds from current time and save as a variable as string in ISO 8601 format
$oldDate = ((Get-Date).ToUniversalTime()).AddSeconds(-$numberOfSeconds).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")

# Iterate through all Azure Files shares in the $shares variable with array data type
foreach ($share in $shares) {
    $shareName = $($share.Name)
    
    # Get all the files and directories in a file share and save as an array in a variable 
    $filesAndDirs = Get-AzStorageFile -ShareName $shareName -Context $sourceContext

    # Iterate through all files and directories in the $filesAndDirs variable with array data type
    foreach ($f in $filesAndDirs) {
        
        # If the $f is a file, then compare filedate to olddate and operate on old files, Else if $f is a directory, then recursively call the list_subdir function
        if ($f.GetType().Name -eq "AzureStorageFile") {
            
            # Get the file SMB property of LastWriteTime and store in a variable
            $fileDate = $($f.FileProperties.SmbProperties.FileLastWrittenOn.DateTime).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
            
            if ($fileDate -le $oldDate) {
                
                #Get the file path and save to variable"
                $filePath = $($f.ShareFileClient.Path)
                $shareName = $($f.ShareFileClient.ShareName)
                $storageAccountName = $($f.ShareFileClient.AccountName)

                # Run copy operation here to work on files that meet criteria
                # Set the source file path
                $sourceFile = "https://$StorageAccountName.file.core.windows.net/$shareName/$($filePath)$($sourceShareSASURI)"
                # Set the destination file path
                $targetFile = "https://$targetStorageAccountName.file.core.windows.net/$targetStorageFileShareName/$($filePath)$($targetShareSASURI)"
                
                # Write-Output "Source File: $sourceFile"
                # Write-Output "Target File: $targetFile"
                # Write-Output $targetStorageFileShareName
                Write-Output "File Path: $filePath"
                Write-Output "Source File: $sourceFile"
                Write-Output "Target File: $targetFile"
                Write-Output ""
                # Command to copy the file to the target file share and preserve smb metadata
                $command1 = "azcopy","copy",$sourceFile,$targetFile,"--preserve-smb-info","--preserve-smb-permissions"
                # Command to remove the file from the source file share
                $command2 = "azcopy","remove",$sourceFile

                # Create Azure Container Instance Object to run $command1
                $container = New-AzContainerInstanceObject `
                    -Name $containerGroupName1 `
                    -Image "peterdavehello/azcopy:latest" `
                    -RequestCpu 2 -RequestMemoryInGb 4 `
                    -Command $command1 -EnvironmentVariable $envVars

                # Create Azure Container Group and copy the file to the target file share
                $containerGroup1 = New-AzContainerGroup -ResourceGroupName $sourceStorageAccountRG -Name $containerGroupName1 `
                    -Container $container -OsType Linux -Location $location -RestartPolicy never

                # Recreate Azure Container Instance Object to run $command2
                $container = New-AzContainerInstanceObject `
                    -Name $containerGroupName2 `
                    -Image "peterdavehello/azcopy:latest" `
                    -RequestCpu 2 -RequestMemoryInGb 4 `
                    -Command $command2 -EnvironmentVariable $envVars

                # Recreate the same Azure Container Group and remove the file from the source file share
                $containerGroup2 = New-AzContainerGroup -ResourceGroupName $sourceStorageAccountRG -Name $containerGroupName2 `
                    -Container $container -OsType Linux -Location $location -RestartPolicy never

            }else{
                Write-Output "No Old Files :)"
            }

        }
        elseif ($f.GetType().Name -eq "AzureStorageFileDirectory") {
            
            # Call the list_subdir function to recursively get all files and directories in the directory
            list_subdir($f)
            
        }

        # Create new line spacing in output
        Write-Output ""

    }

}
