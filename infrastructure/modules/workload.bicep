// ----------------------------------------------------------------------------
// Workload module — runs at resource-group scope.
//
// Provisions, per environment:
//   - Log Analytics workspace
//   - Application Insights (workspace-based)
//   - Storage Account (the actual hosting layer; static-website mode is
//     enabled by the CD workflow as a one-shot data-plane call)
//   - Diagnostic settings on the storage account → Log Analytics
// ----------------------------------------------------------------------------

@description('Logical environment name.')
param environmentName string

@description('Project slug used in resource names.')
param projectName string

@description('Azure region for all resources.')
param location string

@description('Tags applied to all resources.')
param tags object

// Storage account names: 3-24 chars, lowercase + digits only.
// "st<project><env>" → e.g. stzrwebstaging / stzrwebproduction.
var storageAccountName = toLower('st${projectName}${environmentName}')
var laName = 'log-${projectName}-${environmentName}'
var aiName = 'appi-${projectName}-${environmentName}'

// --------------------------------------------------------------------------
// Observability — Log Analytics + Application Insights
// --------------------------------------------------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: laName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: environmentName == 'production' ? 90 : 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// --------------------------------------------------------------------------
// Hosting — Storage Account
// --------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    // LRS in non-prod, ZRS in prod for higher durability.
    name: environmentName == 'production' ? 'Standard_ZRS' : 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Static-website mode itself (and the $web container) is enabled as a
// one-shot data-plane call by the CD workflow:
//   az storage blob service-properties update --static-website ...

// --------------------------------------------------------------------------
// Diagnostic settings — storage HTTP logs → Log Analytics, so the
// post-deploy health workflow can query the 4xx/5xx rate.
// --------------------------------------------------------------------------

resource blobDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: blobService
  name: 'blob-to-loganalytics'
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      { category: 'StorageRead',   enabled: true }
      { category: 'StorageWrite',  enabled: true }
      { category: 'StorageDelete', enabled: true }
    ]
    metrics: [
      { category: 'Transaction', enabled: true }
    ]
  }
}

// --------------------------------------------------------------------------
// Outputs — consumed by the deployment workflows.
// --------------------------------------------------------------------------

output storageAccountName string = storageAccount.name
output staticWebsiteHost string = replace(replace(storageAccount.properties.primaryEndpoints.web, 'https://', ''), '/', '')
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalytics.properties.customerId
output logAnalyticsResourceId string = logAnalytics.id
