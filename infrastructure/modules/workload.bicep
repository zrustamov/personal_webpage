// ----------------------------------------------------------------------------
// Workload module — runs at resource-group scope.
//
// Provisions:
//   - Log Analytics workspace
//   - Application Insights (workspace-based)
//   - Azure Static Web App
//   - Optional custom domain binding
// ----------------------------------------------------------------------------

@description('Logical environment name.')
param environmentName string

@description('Project slug used in resource names.')
param projectName string

@description('Azure region for all resources.')
param location string

@description('Static Web App SKU.')
param swaSku string

@description('Optional custom domain. Empty string skips the binding.')
param customDomain string

@description('Tags applied to all resources.')
param tags object

var swaName = 'swa-${projectName}-${environmentName}'
var laName = 'log-${projectName}-${environmentName}'
var aiName = 'appi-${projectName}-${environmentName}'

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

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: swaName
  location: location
  tags: tags
  sku: {
    name: swaSku
    tier: swaSku
  }
  properties: {
    // The repository fields are intentionally omitted — deployment is driven
    // by GitHub Actions using the deployment token, not by SWA's built-in
    // repo integration.
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    provider: 'GitHub'
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

resource swaAppInsightsBinding 'Microsoft.Web/staticSites/config@2023-12-01' = {
  name: 'appsettings'
  parent: staticWebApp
  properties: {
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.properties.ConnectionString
  }
}

resource swaCustomDomain 'Microsoft.Web/staticSites/customDomains@2023-12-01' = if (!empty(customDomain)) {
  name: customDomain
  parent: staticWebApp
  properties: {
    validationMethod: 'cname-delegation'
  }
}

output staticWebAppName string = staticWebApp.name
output staticWebAppDefaultHostname string = staticWebApp.properties.defaultHostname
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalytics.id
