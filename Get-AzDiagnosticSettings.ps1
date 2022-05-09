<#
.SYNOPSIS
    Get all Azure Diagnostics settings for Azure Resources
.DESCRIPTION
    Script cycles through all Subscriptions available to account, and checks every resource for Diagnostic Settings configuration.
    All configuration details are stored in an array ($DiagResults) as well as exported to a CSV in the current running directory.
.NOTES
#>

# SCRIPT - START
# Install and login with Connect-AzAccount and skip when using Azure Cloud Shell
If ($null -eq (Get-Command -Name Get-CloudDrive -ErrorAction SilentlyContinue)) {
    If ($null -eq (Get-Module Az -ListAvailable -ErrorAction SilentlyContinue)){
        Write-Host "Installing Az module from default repository"
        Install-Module -Name Az -AllowClobber
    }
    Write-Host "Importing Az"
    Import-Module -Name Az
    Write-Host "Connecting to Az"
    Connect-AzAccount
}

# Get all Azure Subscriptions
$Subs = Get-AzSubscription

# Set array
$DiagResults = @()

# Loop through all Azure Subscriptions
foreach ($Sub in $Subs) {
    # Set Subscription for current loop
    Set-AzContext $Sub.id | Out-Null
    $subName = $Sub.Name
    Write-Host "Processing Subscription:" $($Sub).name
    
    # Get all Azure resources for current subscription
    $Resources = Get-AZResource
    
    # Get all Azure resources which have Diagnostic settings enabled and configured
    foreach ($res in $Resources) {
        # Set resource ID for current loop
        $resId = $res.ResourceId
        # Write-Host "Processing Resource:" $resId
        
        # Set dianostic settings for current resource
        $DiagSettings = Get-AzDiagnosticSetting -ResourceId $resId -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $null }
        # Write-Host "Diagnostic Settings:" $DiagSettings
        # Loop through all diagnostic settings for current resource
        foreach ($diag in $DiagSettings) {
            # Write-Host "Processing Diagnostic Setting:" $diag
            # If diagnostic settings are destined for storage account
            If ($diag.StorageAccountId) {
                [string]$StorageAccountId= $diag.StorageAccountId
                [string]$storageAccountName = $StorageAccountId.Split('/')[-1]
            }
            
            # If diagnostic settings are destined for Event Hub
            If ($diag.EventHubAuthorizationRuleId) {
                [string]$EventHubId = $diag.EventHubAuthorizationRuleId
                [string]$EventHubName = $EventHubId.Split('/')[-3]
            }
            
            # If diagnostic settings are destined for Log Analytics workspace
            If ($diag.WorkspaceId) {
                [string]$WorkspaceId = $diag.WorkspaceId
                [string]$WorkspaceName = $WorkspaceId.Split('/')[-1]
            }
            
            # Store all results for resource in an Object
            $item = [PSCustomObject]@{
                ResourceName = $res.Name
                DiagnosticSettingsName = $diag.Name
                StorageAccountName =  $StorageAccountName
                EventHubName =  $EventHubName
                WorkspaceName =  $WorkspaceName
                
                # Extracting properties into string format.
                Metrics = ($diag.Metrics | ConvertTo-Json -Compress | Out-String).Trim()
                Logs =  ($diag.Logs | ConvertTo-Json -Compress | Out-String).Trim()
                Subscription = $Sub.Name
                ResourceId = $resId
                DiagnosticSettingsId = $diag.Id
                StorageAccountId =  $StorageAccountId
                EventHubId =  $EventHubId
                WorkspaceId = $WorkspaceId
            }
            # Write-Host $item
            # Add PS Object to array
            $DiagResults += $item
        }
    }
    $DiagResults | Export-Csv -Force -Path ".\$subName-DiagnosticSettings-$(get-date -f yyyy-MM-dd-HHmm).csv"
    
}
# Save Diagnostic settings to CSV as tabular data
# $DiagResults | Export-Csv -Force -Path ".\AzureResourceDiagnosticSettings-$(get-date -f yyyy-MM-dd-HHmm).csv"
# Write-Host 'The array $DiagResults can be used to further refine results within session.'
# Write-Host 'eg. $DiagResults | Where-Object {$_.WorkspaceName -like "<workspace_name_string>"}'
