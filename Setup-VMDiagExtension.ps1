<#
.SYNOPSIS

Install and Configure Diagnostics Settings on Azure Linux/Windows Virtual Machines

.DESCRIPTION

This script takes a flag and parameter pair to find the virtual machine resource.
The script has the scopes of subscription, resource group, or specific resource.
If necessary the script loops through each scope to find the resource.
Then the script installs the diagnostic agent on the virtual machine.
At the same time as installing the agent for the first time, the script will also
configure the agent based on the provided public/private settings specified inline, or
in the JSON config file that is requested in the script. This script will send all logs
to the specified storage account. Update the storage account in the global variables section.

.PARAMETER -s <subscriptionId> | -g <resourceGroupName> | -r <resourceName> -g <resourceGroupName>

Specifies scope of the resource(s) to be targeted at either the subscription, resource group, or specific resource.

.INPUTS

None. You cannot pipe objects to this script.

.OUTPUTS

The output from this script will provide a status of the operation.

.EXAMPLE

Subscription Example:
```
PS> .\Setup-VMDiagExtension.ps1 -s "00000000-0000-0000-0000-000000000000"
```

Resource Group Example:
```
PS> .\Setup-VMDiagExtension.ps1 -g "rg1"
```

Resource Example:
```
PS> .\Setup-VMDiagExtension.ps1 -r "vm1" -g "rg1"
```

.NOTES
Currently this script doesn't have logic for working around unsupported OS/distros
This script does account for storage account being in a different region than the VM
For now only run this script on supported VM OS/distros - https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/diagnostics-linux?tabs=azcli#supported-linux-distributions
For now only run this script with a storage account in the same region as the VM
Update the storage account in the global variables section
#>

# SCRIPT STEPS
# 1. Get necesary properties and assign them to variables
# 2. Get the VM
# 3. Give the VM a system assigned identity
# 4. Get the extension configuration file with public and private settings
# 5. Substitute the values in the extension configuration file with the values from the variables
# 6. Add the extension to the VM
# 7. Get the VM again and check if the extension is there
# 8. If the extension is there, get the extension settings and write them to a file
# 9. Write the file to the output directory
# 10. Write-Host the file name to the screen

# GLOBAL VARIBLES

## Set the storage account name and storage account resource group
$storageAccountName = "savistam3rgdiag"
$storageAccountResourceGroup = "savista-m3-rg"
$ProgressPreference = 'SilentlyContinue'

# Collection user parameters
$scopeParam = $args[0]
$scopeResource = $args[1]


# Functions
function Get-TimeStamp {
    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
    
}

# Set counter to 0
$counter = 0

# Switch/Case between different scopes based on $scopeParam
$scope = $scopeParam
switch ($scope) {
    "-s" {

        # Write out scope selected to file
        Write-Output "Subscription scope selected - SUB: $scopeResource - $(Get-TimeStamp)" | Out-File scriptlog.txt -Append

        # Set subscription context
        Set-AzContext -Subscription $scopeResource
        
        # Get all Azure VMs in the subscription
        $vms = Get-AzVM

        # Loop through each vm in vms
        foreach ($vm in $vms) {
    
            # Set VM Variables
            $vmResourceGroup = $vm.ResourceGroupName
            $vmName = $vm.Name
            $vmLocation = $vm.Location
            $vmId = $vm.Id

            # Check if the vm is Windows or Linux
            if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") {

                # Write the vm name to the screen
                Write-Host "Processing on Windows VM: $vmName"

                # Enable system-assigned identity on an existing VM
                Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vm -IdentityType SystemAssigned -NoWait

                ## Get the config file
                Invoke-WebRequest https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/wad-settings.json -OutFile azure-wad-settings.json

                ## Generate a SAS token for the agent to use to authenticate with the storage account
                $sasToken = New-AzStorageAccountSASToken -Service Blob, Table -ResourceType Service, Container, Object -Permission "racwdlup" -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context -ExpiryTime $([System.DateTime]::Now.AddYears(10))

                ## Get config file content and replace mystorageaccount with $storageAccountName and output the file to a new file
                $configFile = Get-Content azure-wad-settings.json
                $configFile = $configFile.Replace('mystorageaccount', $storageAccountName)
                ## Get config file content and replace storage account key
                $configFile = $configFile.Replace('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', $sasToken)
                ## Get config file content and replace resource ID for VM
                $configFile = $configFile.Replace('vmID', $vmId)

                ## Write the content back to the file
                $configFile > azure-wad-settings.json

                ## Add the extension to the VM
                Set-AzVMDiagnosticsExtension -ResourceGroupName $vmResourceGroupName -VMName $vmName -DiagnosticsConfigurationPath ./azure-wad-settings.json -NoWait
            } elseif ($vm.StorageProfile.OsDisk.OsType -eq "Linux") {
                
                # Write the vm name to the screen
                Write-Host "Processing on Linux VM: $vmName"

                # Enable system-assigned identity on an existing VM
                Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vm -IdentityType SystemAssigned -NoWait

                # Get the public settings template from GitHub and update the templated values for the storage account and resource ID
                $publicSettings = (Invoke-WebRequest -Uri https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/lad-settings.json).Content
                $publicSettings = $publicSettings.Replace('mystorageaccount', $storageAccountName)
                $publicSettings = $publicSettings.Replace('vmID', $vmId)

                # If you have your own customized public settings, you can inline those rather than using the preceding template: $publicSettings = '{"ladCfg":  { ... },}'

                # Generate a SAS token for the agent to use to authenticate with the storage account
                $sasToken = New-AzStorageAccountSASToken -Service Blob, Table -ResourceType Service, Container, Object -Permission "racwdlup" -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context -ExpiryTime $([System.DateTime]::Now.AddYears(10))

                # Build the protected settings (storage account SAS token)
                $protectedSettings = "{'storageAccountName': '$storageAccountName', 'storageAccountSasToken': '$sasToken'}"

                # Finally, install the extension with the settings you built
                Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vmName -Location $vmLocation -ExtensionType LinuxDiagnostic -Publisher Microsoft.Azure.Diagnostics -Name LinuxDiagnostic -SettingString $publicSettings -ProtectedSettingString $protectedSettings -TypeHandlerVersion 4.0 -NoWait
            } 

            # Print out timestamp and iteration to file
            Write-Output "Iteration: $counter - $(Get-TimeStamp)" | Out-File scriptlog.txt -Append
            
            # Increment counter
            $counter++
        }

        break
    }
    "-g" {

        # Write out scope selected to file
        Write-Output "Resource group scope selected - RG: $scopeResource - $(Get-TimeStamp)" | Out-File scriptlog.txt -Append

        # Get all the VMs in the resource group
        $vms = Get-AzVM -ResourceGroupName $scopeResource
        
        # Loop through each vm in vms
        foreach ($vm in $vms) {

            # Set VM Variables
            $vmResourceGroup = $vm.ResourceGroupName
            $vmName = $vm.Name
            $vmLocation = $vm.Location
            $vmId = $vm.Id

            # Check if the vm is Windows or Linux
            if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") {
                
                # Start installing the extension
                Write-Host "Processing on Windows VM: $vmName"

                # Enable system-assigned identity on an existing VM
                Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vm -IdentityType SystemAssigned -NoWait

                ## Get the config file
                Invoke-WebRequest https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/wad-settings.json -OutFile azure-wad-settings.json

                ## Generate a SAS token for the agent to use to authenticate with the storage account
                $sasToken = New-AzStorageAccountSASToken -Service Blob, Table -ResourceType Service, Container, Object -Permission "racwdlup" -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context -ExpiryTime $([System.DateTime]::Now.AddYears(10))

                ## Get config file content and replace mystorageaccount with $storageAccountName and output the file to a new file
                $configFile = Get-Content azure-wad-settings.json
                $configFile = $configFile.Replace('mystorageaccount', $storageAccountName)
                ## Get config file content and replace storage account key
                $configFile = $configFile.Replace('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', $sasToken)
                ## Get config file content and replace resource ID for VM
                $configFile = $configFile.Replace('vmID', $vmId)

                ## Write the content back to the file
                $configFile > azure-wad-settings.json

                ## Add the extension to the VM
                Set-AzVMDiagnosticsExtension -ResourceGroupName $vmResourceGroup -VMName $vmName -DiagnosticsConfigurationPath ./azure-wad-settings.json -NoWait
            } elseif ($vm.StorageProfile.OsDisk.OsType -eq "Linux") {
                
                # Write the vm name to the screen
                Write-Host "Processing on Linux VM: $vmName"

                # Enable system-assigned identity on an existing VM
                Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vm -IdentityType SystemAssigned -NoWait

                # Get the public settings template from GitHub and update the templated values for the storage account and resource ID
                $publicSettings = (Invoke-WebRequest -Uri https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/lad-settings.json).Content
                $publicSettings = $publicSettings.Replace('mystorageaccount', $storageAccountName)
                $publicSettings = $publicSettings.Replace('vmID', $vmId)

                # If you have your own customized public settings, you can inline those rather than using the preceding template: $publicSettings = '{"ladCfg":  { ... },}'

                # Generate a SAS token for the agent to use to authenticate with the storage account
                $sasToken = New-AzStorageAccountSASToken -Service Blob, Table -ResourceType Service, Container, Object -Permission "racwdlup" -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context -ExpiryTime $([System.DateTime]::Now.AddYears(10))

                # Build the protected settings (storage account SAS token)
                $protectedSettings = "{'storageAccountName': '$storageAccountName', 'storageAccountSasToken': '$sasToken'}"

                # Finally, install the extension with the settings you built
                Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vmName -Location $vmLocation -ExtensionType LinuxDiagnostic -Publisher Microsoft.Azure.Diagnostics -Name LinuxDiagnostic -SettingString $publicSettings -ProtectedSettingString $protectedSettings -TypeHandlerVersion 4.0 -NoWait
            } 
            
            # Print out VM, timestamp, and iteration to file
            Write-Output "VM: $vmName - Iteration: $counter - $(Get-TimeStamp)" | Out-File scriptlog.txt -Append

            # Increment counter
            $counter++
        }
        
        break
    }
    "-r" {
        
        # Install and Configure Steps go here
        Write-Host "Resource scope selected"
        
        # Check if resource group is provided in args[3]
        if ($args[3] -eq $null) {
            
            # Write-Host "Resource group not provided"
            Write-Host "No resource group name provided"
            break
        
        }
        else {
            
            # Set the resource group variable
            $rg = $args[3]
            # Set the vm object variables
            $vm = Get-AzVM -ResourceGroupName $rg -Name $scopeResource
            $vmName = $vm.Name
            $vmResourceGroup = $vm.ResourceGroupName
            $vmLocation = $vm.Location
            $vmId = $vm.Id
            
            # Check if the vm is Windows or Linux
            if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") {
                
                # Start installing the extension
                Write-Host "Processing on Windows VM $vmName"

                # Enable system-assigned identity on an existing VM
                Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vm -IdentityType SystemAssigned -NoWait
                
                ## Get the config file
                Invoke-WebRequest https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/wad-settings.json -OutFile azure-wad-settings.json

                ## Generate a SAS token for the agent to use to authenticate with the storage account
                $sasToken = New-AzStorageAccountSASToken -Service Blob, Table -ResourceType Service, Container, Object -Permission "racwdlup" -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context -ExpiryTime $([System.DateTime]::Now.AddYears(10))

                ## Get config file content and replace mystorageaccount with $storageAccountName and output the file to a new file
                $configFile = Get-Content azure-wad-settings.json
                $configFile = $configFile.Replace('mystorageaccount', $storageAccountName)
                ## Get config file content and replace storage account key
                $configFile = $configFile.Replace('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', $sasToken)
                ## Get config file content and replace resource ID for VM
                $configFile = $configFile.Replace('vmID', $vmId)

                ## Write the content back to the file
                $configFile > azure-wad-settings.json

                ## Add the extension to the VM
                Set-AzVMDiagnosticsExtension -ResourceGroupName $rg -VMName $vmName -DiagnosticsConfigurationPath ./azure-wad-settings.json -NoWait
            } elseif ($vm.StorageProfile.OsDisk.OsType -eq "Linux") {
                
                # Write the vm name to the screen
                Write-Host "Processing on Linux VM: $vmName"

                # Enable system-assigned identity on an existing VM
                Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vm -IdentityType SystemAssigned -NoWait

                # Get the public settings template from GitHub and update the templated values for the storage account and resource ID
                $publicSettings = (Invoke-WebRequest -Uri https://raw.githubusercontent.com/mrcloudchase/AzureAutomation/main/lad-settings.json).Content
                $publicSettings = $publicSettings.Replace('mystorageaccount', $storageAccountName)
                $publicSettings = $publicSettings.Replace('vmID', $vmId)

                # If you have your own customized public settings, you can inline those rather than using the preceding template: $publicSettings = '{"ladCfg":  { ... },}'

                # Generate a SAS token for the agent to use to authenticate with the storage account
                $sasToken = New-AzStorageAccountSASToken -Service Blob, Table -ResourceType Service, Container, Object -Permission "racwdlup" -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context -ExpiryTime $([System.DateTime]::Now.AddYears(10))

                # Build the protected settings (storage account SAS token)
                $protectedSettings = "{'storageAccountName': '$storageAccountName', 'storageAccountSasToken': '$sasToken'}"

                # Finally, install the extension with the settings you built
                Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vmName -Location $vmLocation -ExtensionType LinuxDiagnostic -Publisher Microsoft.Azure.Diagnostics -Name LinuxDiagnostic -SettingString $publicSettings -ProtectedSettingString $protectedSettings -TypeHandlerVersion 4.0 -NoWait
            }

            break
        }

        break
    }
    default {
        Write-Host "Invalid scope. Valid scopes are: Subscription, Resource Group, Resource"
        # Write out the help
        Write-Host "Usage: Setup-VMDiagExtension.ps1 [ -s | -g | -r -g ] [ -s <subscriptionId> | -g <resourceGroupName> | -r <resourceId>  -g <resourceGroupName> ]"
        exit 1
    }
}
