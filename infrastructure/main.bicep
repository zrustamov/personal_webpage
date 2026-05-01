// ----------------------------------------------------------------------------
// Personal webpage — Azure infrastructure (subscription-scoped entry point)
//
// Provisions, per environment:
//   - Resource group
//   - Storage Account (static-website hosting)
//   - Log Analytics workspace
//   - Application Insights
//   - Storage diagnostic settings → Log Analytics
//
// Deploy:
//   az deployment sub create \
//     --location swedencentral \
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

@description('Azure region for all resources. Constrained by the subscription policy.')
param location string = 'swedencentral'

@description('Short project slug used in resource names.')
param projectName string = 'zrweb'

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
    tags: commonTags
  }
}

output resourceGroupName string = rg.name
output storageAccountName string = workload.outputs.storageAccountName
output staticWebsiteHost string = workload.outputs.staticWebsiteHost
output appInsightsName string = workload.outputs.appInsightsName
output appInsightsConnectionString string = workload.outputs.appInsightsConnectionString
output logAnalyticsResourceId string = workload.outputs.logAnalyticsResourceId
