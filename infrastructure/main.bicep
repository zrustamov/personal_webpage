// ----------------------------------------------------------------------------
// Personal webpage — Azure infrastructure
//
// Provisions an Azure Static Web App per environment, a Log Analytics
// workspace, and an Application Insights resource wired to the SWA for
// post-deploy monitoring.
//
// Deploy:
//   az deployment sub create \
//     --location westeurope \
//     --template-file infrastructure/main.bicep \
//     --parameters infrastructure/parameters/staging.bicepparam
// ----------------------------------------------------------------------------

targetScope = 'subscription'

@description('Logical environment name. Used in resource names and tags.')
@allowed([
  'staging'
  'production'
])
param environmentName string

@description('Azure region for all resources.')
param location string = 'westeurope'

@description('Short project slug used in resource names.')
param projectName string = 'zrweb'

@description('Static Web App SKU. Standard is required for staging slots and custom auth.')
@allowed([
  'Free'
  'Standard'
])
param swaSku string = 'Standard'

@description('Optional custom domain (e.g. zaidrustamov.com). Leave empty to skip binding.')
param customDomain string = ''

var resourceGroupName = 'rg-${projectName}-${environmentName}'

var commonTags = {
  project: projectName
  environment: environmentName
  managedBy: 'bicep'
  owner: 'zrustamov'
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

module workload './modules/workload.bicep' = {
  name: 'workload-${environmentName}'
  scope: rg
  params: {
    environmentName: environmentName
    projectName: projectName
    location: location
    swaSku: swaSku
    customDomain: customDomain
    tags: commonTags
  }
}

output resourceGroupName string = rg.name
output staticWebAppName string = workload.outputs.staticWebAppName
output staticWebAppDefaultHostname string = workload.outputs.staticWebAppDefaultHostname
output appInsightsConnectionString string = workload.outputs.appInsightsConnectionString
