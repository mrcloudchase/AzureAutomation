# Retrieve all the VM Extensions enabled for all VMs in a subscription for the current context


[CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory = $true)][string]$stgAcctName,
        [Parameter(mandatory = $true)][string]$stgAcctRG
    )

# Get VM Collection
$vmCollection = Get-AzVM

# Loop through the VMs with Parallel ForEach
$vmCollection | Foreach-Object -ThrottleLimit 2 -Parallel {
    
    # VM Variables
    $vm = $_
    $vmName = $_.Name
    $vmResourceGroup = $_.ResourceGroupName
    $vmId = $_.Id
    $vmLocation = $_.Location
    $vmOSType = $_.StorageProfile.OsDisk.OsType

    # Set VM Operational Status
    $vmPowerState = (Get-AzVM -Status -Name $_.Name).PowerState

    $vmReady = 'VM Running'
    # Check if not running, if not, skip
    if ($vmPowerState -ne $vmReady) {
        break
    }

    # Storage Account Variables
    $storageAccountName = $using:stgAcctName
    $storageAccountResourceGroup = $using:stgAcctRG
    $ProgressPreference = 'SilentlyContinue'

    # Check if the vm is Windows or Linux
    if ($vmOsType -eq "Windows") {
                
        # VM to be updated
        Write-Host "Processing on Windows VM: $vmName"

        # Enable system-assigned identity on an existing VM
        Update-AzVM -ResourceGroupName $vmResourceGroup -VM $vm -IdentityType SystemAssigned -NoWait

        # Get the config file
        Invoke-WebRequest https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/wad-settings.json -OutFile $vmName-wad-settings.json

        # Generate a SAS token for the agent to use to authenticate with the storage account
        $sasToken = New-AzStorageAccountSASToken -Service Blob, Table -ResourceType Service, Container, Object -Permission "racwdlup" -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context -ExpiryTime $([System.DateTime]::Now.AddYears(10))

        # Get the diagnostics settings
        $publicSettings = (Invoke-WebRequest https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/wad-settings.json).Content
        $publicSettings = $publicSettings.Replace('mystorageaccountname', $storageAccountName)
        $publicSettings = $publicSettings.Replace('vmID', $vmId)
        $publicSettings = $publicSettings.Replace('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', $sasToken)
        
        # Write the settings to a file
        $publicSettings > $vmName-wad-settings.json

        ## Add the extension to the VM
        Set-AzVMDiagnosticsExtension -ResourceGroupName $vmResourceGroup -VMName $vmName -DiagnosticsConfigurationPath ./$vmName-wad-settings.json -NoWait
    }
    elseif ($vmOsType -eq "Linux") {
        
        # Write the vm name to the screen
        Write-Host "Processing on Linux VM: $vmName"

        # Enable system-assigned identity on an existing VM
        Update-AzVM -ResourceGroupName $vmResourceGroup -VM $vm -IdentityType SystemAssigned -NoWait

        # Get the public settings template from GitHub and update the templated values for the storage account and resource ID
        $publicSettings = (Invoke-WebRequest -Uri https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/lad-settings.json).Content
        $publicSettings = $publicSettings.Replace('mystorageaccountname', $storageAccountName)
        $publicSettings = $publicSettings.Replace('vmID', $vmId)

        # Generate a SAS token for the agent to use to authenticate with the storage account
        $sasToken = New-AzStorageAccountSASToken -Service Blob, Table -ResourceType Service, Container, Object -Permission "racwdlup" -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context -ExpiryTime $([System.DateTime]::Now.AddYears(10))

        # Build the protected settings (storage account SAS token)
        $protectedSettings = "{'storageAccountName': '$storageAccountName', 'storageAccountSasToken': '$sasToken'}"

        # Finally, install the extension with the settings you built
        Set-AzVMExtension -ResourceGroupName $vmResourceGroup -VMName $vmName -Location $vmLocation -ExtensionType LinuxDiagnostic -Publisher Microsoft.Azure.Diagnostics -Name LinuxDiagnostic -SettingString $publicSettings -ProtectedSettingString $protectedSettings -TypeHandlerVersion 4.0 -NoWait
    } 
    else {
        break
    }
}
