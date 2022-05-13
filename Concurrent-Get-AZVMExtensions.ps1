# Retrieve all the VM Extensions enabled for all VMs in a subscription for the current context

# Set Variable for all the VMs
$vmCollection = Get-AzVM

# Loop through the VMs with Parallel ForEach
$vmCollection | Foreach-Object -ThrottleLimit 3 -Parallel {
    
    # Variables
    $vmId = $_.Id

    # Output to the screen
    # Write-Host "Getting Extension for VM: $vmName"

    Get-AzVMExtension -ResourceId $vmId | Select-Object -Property VMName, Name, Id, TypeHandlerVersion, ProvisioningState, PublicSettings, ProtectedSettings

} | ConvertTo-Csv | Out-File vmExtensionsList.csv -Append # Write the output to a file
