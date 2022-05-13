<#
.SYNOPSIS

Get the list of all the installed Extensions on a VM and their status/properties.

.DESCRIPTION

This script takes a flag and parameter pair to find the virtual machine resource.
The script works on the subscription scope.

.PARAMETER -s <subscriptionId> 

Specifies Subscription scope.

.INPUTS

None. You cannot pipe objects to this script.

.OUTPUTS

The output from this script will provide a status of the operation and return the necessary information.

.EXAMPLE

Subscription Example:
```
PS> .\Get-InstalledVMExtensions.ps1 -s "00000000-0000-0000-0000-000000000000"
```

.NOTES
#>

# GLOBAL VARIBLES
$subID = (Get-AzContext).Subscription.Id
$extInfo = @()
# Functions

# Create a timestamp
function Get-TimeStamp {
    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
    
}


# SCRIPT START

# Write out scope selected to file
Write-Output "SUBSCRIPTION SELECTED: $subID - $(Get-TimeStamp)"

# Get all Azure VMs in the subscription
$resourceGroups = (Get-AzVM).ResourceGroupName

# Iterate through each resource group
foreach ($rg in $resourceGroups) {
    
    # Get all VMs in the resource group
    $vms = Get-AzVM -ResourceGroupName $rg

    # Iterate through each VM
    foreach ($vm in $vms) {
        
        # Get the VM name
        $vmName = $vm.Name

        # Get the all the Extension information for the VM
        $vmExtensions = Get-AzVMExtension -ResourceGroupName $rg -VMName $vmName
        
        # If the VM has extensions installed
        if ($vmExtensions) {

            # Iterate through each extension installed on the VM
            foreach ($ext in $vmExtensions) {

                # Create a new object to store the VM extension information
                $vmExtObject = [PSCustomObject]@{
                    Name      = $ext.VMName
                    Id        = $ext.Id
                    Version   = $ext.TypeHandlerVersion
                    Timestamp = Get-TimeStamp
                }

                # Add extension object to collection
                $extInfo += $vmExtObject

            }
        }
    }   
}

# Write out extension information saved in array
Write-Output $extInfo | ConvertTo-Csv | Out-File "testoutput.txt" -Append
