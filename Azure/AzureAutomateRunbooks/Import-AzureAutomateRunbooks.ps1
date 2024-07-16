Param
(
    [Parameter(Mandatory = $True)]
    [String] $ProductNodeId,

    [Parameter(Mandatory = $True)]
    [String] $SourceName = "Import-AzureAutomateRunbooks",
    [Parameter(Mandatory = $True)]
    [String] $AzureLink,

    [Parameter(Mandatory = $True)]
    [String] $AccountName,
    [Parameter(Mandatory = $True)]
    [String] $TokenName,
    [Parameter(Mandatory = $True)]
    [ValidateSet('Production', "Quality", "Demo")]
    [String] $EnvironmentType,
    [Parameter(Mandatory = $True)]
    [ValidateSet('EU', 'AU', 'UK', 'US', 'CH')]
    [String] $EnvironmentRegion,

    [Parameter(Mandatory = $False)]
    [String[]] $AutomationAccountAllowList = @(),
    [Parameter(Mandatory = $False)]
    [String[]] $AutomationAccountDenyList = @()
)

$ErrorActionPreference = "Stop"

Function Get-SourceIdFromResourceId
{
    Param
    (
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [String] $ResourceId
    )

    Begin
    {
        $IdRegex = "^\/subscriptions\/([A-Za-z\d]{8}-[A-Za-z\d]{4}-[A-Za-z\d]{4}-[A-Za-z\d]{4}-[A-Za-z\d]{12})\/resourceGroups\/([^\/]*)\/providers\/Microsoft\.Automation\/automationAccounts\/([^\/]*)\/runbooks\/(.*$)"
    }

    Process
    {
        If ($ResourceId -notmatch $IdRegex)
        {
            Return $Null
        }

        $SourceID = "$($Matches[1])/$($Matches[2])/$($Matches[3])/$($Matches[4])"
        $Hasher = [System.Security.Cryptography.HashAlgorithm]::Create('sha256')
        $Hash = $Hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SourceID))
        $SourceIDHash = [System.BitConverter]::ToString($hash).Replace('-', '')
        Return $SourceIDHash
    }
}

$Credential = Get-AutomationPSCredential -Name $TokenName

Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity -WarningAction Ignore | Out-Null

Import-Module Sdk4me.PowerShell
New-4meConnection -Credential $Credential -AccountName $AccountName -EnvironmentType $EnvironmentType -EnvironmentRegion $EnvironmentRegion | Out-Null

$ConfigurationItemProductFilter = New-4meConfigurationItemQueryFilter -Property Product -Operator Equals -TextValues $ProductNodeId
$ConfigurationItemQuery = New-4meConfigurationItemQuery -Properties ID, Name, Label, Source, SourceID, Remarks, Status -ConfigurationItemFilters $ConfigurationItemProductFilter
$ExistingConfigurationItems = Invoke-4meConfigurationItemQuery -Query $ConfigurationItemQuery

$ValidSourceIds = @()
$Subscriptions = Get-AzContext -ListAvailable
Write-Output "Processing $($Subscriptions.Count) subscriptions"
ForEach ($subscription in $Subscriptions)
{
    Write-Output "Checking for Runbooks in $($subscription.Subscription.Name) ($($subscription.Subscription.Id))"
    $AzureContext = Set-AzContext -Subscription $($subscription.Subscription.Id)
    
    $runbooks = Get-AzResource -ResourceType "Microsoft.Automation/automationAccounts/runbooks"

    ForEach ($runbook in $runbooks)
    {
        $automationAccount = $runbooks[0].Name.Split('/')[0]
        If ($AutomationAccountAllowList.Count -gt 0 -and $automationAccount -notin $AutomationAccountAllowList)
        {
            Write-Output "$($automationAccount) is not in allowlist ($([String]::Join(', ', $AutomationAccountAllowList))"
            Continue
        }
        ElseIf ($AutomationAccountDenyList.Count -gt 0 -and $automationAccount -in $AutomationAccountDenyList)
        {
            Write-Output "$($automationAccount) is in denylist ($([String]::Join(', ', $AutomationAccountDenyList))"
            Continue
        }

        $sourceId = Get-SourceIdFromResourceId -ResourceId $($runbook.ResourceId)
        If ($Null -eq $sourceId)
        {
            Write-Error "Failed to generate SourceId from $($runbook.ResourceId)"
        }

        [Sdk4me.GraphQL.ConfigurationItem] $existingConfigurationItem = $ExistingConfigurationItems | Where-Object { $_.Label -eq $($runbook.Name) } | Select-Object -First 1
        If ($Null -eq $existingConfigurationItem)
        {
            $link = "$($AzureLink)/$($runbook.ResourceId)"
            $newConfigurationItem = New-4meConfigurationItem -Label $($runbook.Name) -Status InProduction -Remarks $link -Source $SourceName -SourceID $sourceId -ProductId $($ProductNodeId) -Properties ID, Name, Label, Source, SourceID, Remarks, Status
            $ExistingConfigurationItems += $newConfigurationItem
            Write-Output "Created new CI for $($runbook.Name) with NodeId $($newConfigurationItem.ID)"
        }
        ElseIf ($existingConfigurationItem.SourceID -ne $sourceId -or $existingConfigurationItem.Source -ne $SourceName)
        {
            Write-Warning "Found CI with label $($runbook.Name) but different SourceID ($sourceId vs $($existingConfigurationItem.SourceID)) or Source ($($SourceName) vs $($existingConfigurationItem.Source))"
            Continue
        }

        $ValidSourceIds += $sourceId
    }
}

$DeletedConfigurationItems = $ExistingConfigurationItems | Where-Object { $_.Source -eq $SourceName -and $_.SourceID -notin $ValidSourceIds }
ForEach ($configurationItem in $DeletedConfigurationItems)
{
    If ($configurationItem.Status -ne 'Removed')
    {
        Write-Output "Setting CI for $($configurationItem.Label) with NodeId $($configurationItem.ID) to Status=Removed"
        Set-4meConfigurationItem -ID $($configurationItem.ID) -Status Removed -Properties ID | Out-Null
    }
}
