# Import-AzureAutomateRunbooks.ps1
Imports Azure Automation Runbooks as Configuration Items in 4me.

## Requirements
1. A Product with rule set `logical_asset_without_financial_data`
2. 4me Credentials with Scopes:
    - CI: Read, Create, Update
    - Product: Read
    - ProductCategory: Read

## Parameters

### ProductNodeId
**Required**
(NodeId)[https://www.4me.com/blog/copy-nodeid-to-clipboard-action/] of the Product.

### SourceName
**Required**<br>
SourceName used as "Source" in 4me for the Import. See (Source and Source ID)[https://developer.4me.com/v1/general/source/].
> [!IMPORTANT]
> Do not change this after CIs have already been imported. This is used for finding and updating existing CIs.

### AzureLink
**Required**<br>
Start of the Azure Links to create a FQDN for the resource. E.g. https://portal.azure.com/#@contoso.onmicrosoft.com/resource.

### AccountName
**Required**<br>
Account Name of the 4me Account to import to (left part of the .4me.com url).

### CredentialName
**Required**<br>
Name of the Azure Automate Credential Name to use for the 4me Import.

### EnvironmentType
**Required**<br>
Environment Type of the 4me Instance.

### EnvironmentRegion
**Required**<br>
Environment Region of the 4me Instance.

### AutomationAccountAllowList
Array of automation accounts where runbooks should be imported from. If set, only if the AutomationAccount is specified the Runbooks are imported.

### AutomationAccountDenyList
Array of automation accounts where runbooks should not be imported from. If set, only if the AutomationAccount is not part of the array are the Runbooks imported.
