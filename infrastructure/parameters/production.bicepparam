using '../main.bicep'

param environmentName = 'production'
param location = 'westeurope'
param projectName = 'zrweb'
param swaSku = 'Standard'
// Set this once a custom domain is owned and DNS is delegated.
param customDomain = ''
