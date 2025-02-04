targetScope = 'subscription'

// Main parameters
@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources (filtered on available regions for Azure Open AI Service).')
@allowed(['westeurope','southcentralus','australiaeast', 'canadaeast', 'eastus', 'eastus2', 'francecentral', 'japaneast', 'northcentralus', 'swedencentral', 'switzerlandnorth', 'uksouth'])
param location string

@description('Use Redis Cache for Azure API Management.')
param useRedisCacheForAPIM bool = false

@description('Add Azure Open AI Service to secondary region for load balancing.')
@allowed(['','westeurope','southcentralus','australiaeast', 'canadaeast', 'eastus', 'eastus2', 'francecentral', 'japaneast', 'northcentralus', 'swedencentral', 'switzerlandnorth', 'uksouth'])
param secondaryOpenAILocation string = ''

@description('Azure API Management SKU.')
//@allowed(['StandardV2', 'Developer', 'Premium'])
param apimSku string = 'Developer'

//Leave blank to use default naming conventions
param resourceGroupName string = ''
param openAiServiceName string = ''
param apimIdentityName string = ''
param proxyIdentityName string = ''
param deploymentScriptIdentityName string = ''
param apimServiceName string = ''
param logAnalyticsName string = ''
param dataCollectionEndpointName string = ''
param dataCollectionRuleName string = ''
param applicationInsightsDashboardName string = ''
param applicationInsightsName string = ''
param proxyAppName string = ''
param vnetName string = ''
param apimSubnetName string = ''
param apimNsgName string = ''
param acaSubnetName string = ''
param acaNsgName string = ''
param privateEndpointSubnetName string = ''
param privateEndpointNsgName string = ''
param redisCacheServiceName string = ''
param containerRegistryName string = ''
param containerAppsEnvironmentName string = ''
param appConfigurationName string = ''
param myIpAddress string = ''

//Determine the version of the chat model to deploy
param arrayVersion0301Locations array = [
  'westeurope'
  'southcentralus'
]
param gptModelVersion string = ((contains(arrayVersion0301Locations, location)) ? '0301' : '0613')
param gptModelVersionSecondary string = ((contains(arrayVersion0301Locations, secondaryOpenAILocation)) ? '0301' : '0613')

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var openAiSkuName = 'S0'
var gptDeploymentName = 'gpt-35-turbo'
var gptModelName = 'gpt-35-turbo'
var embeddingDeploymentName = 'text-embedding-ada-002'
var embeddingModelName = 'text-embedding-ada-002'
var embeddingModelVersion = '2'
var embeddingModelVersionSecondary = '2'
var tags = { 'azd-env-name': environmentName }

var openAiPrivateDnsZoneName = 'privatelink.openai.azure.com'
var monitorPrivateDnsZoneName = 'privatelink.monitor.azure.com'
var redisCachePrivateDnsZoneName = 'privatelink.redis.cache.windows.net'
var appConfigPrivateDnsZoneName = 'privatelink.azconfig.io'
var containerRegistryPrivateDnsZoneName = 'privatelink.azurecr.io'

var privateDnsZoneNames = [
  openAiPrivateDnsZoneName
  monitorPrivateDnsZoneName
  redisCachePrivateDnsZoneName
  containerRegistryPrivateDnsZoneName
  appConfigPrivateDnsZoneName
]



// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module dnsDeployment './modules/networking/dns.bicep' = [for privateDnsZoneName in privateDnsZoneNames: {
  name: 'dns-deployment-${privateDnsZoneName}'
  scope: resourceGroup
  params: {
    name: privateDnsZoneName
  }
}]

module managedIdentityApim './modules/security/managed-identity.bicep' = {
  name: 'managed-identity-apim'
  scope: resourceGroup
  params: {
    name: !empty(apimIdentityName) ? apimIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}-apim'
    location: location
    tags: tags
  }
}

module managedIdentityProxy './modules/security/managed-identity.bicep' = {
  name: 'managed-identity-chargeback'
  scope: resourceGroup
  params: {
    name: !empty(proxyIdentityName) ? proxyIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}-proxy'
    location: location
    tags: tags
  }
}

module managedIdentityDeploymentScript './modules/security/managed-identity.bicep' = {
  name: 'managed-identity-deployment-script'
  scope: resourceGroup
  params: {
    name: !empty(deploymentScriptIdentityName) ? deploymentScriptIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}-deploymentscript'
    location: location
    tags: tags
  }
}

module redisCache './modules/cache/redis.bicep' = if(useRedisCacheForAPIM){
  name: 'redis-cache'
  scope: resourceGroup
  params: {
    name: !empty(redisCacheServiceName) ? redisCacheServiceName : '${abbrs.cacheRedis}${resourceToken}'
    location: location
    tags: tags
    sku: 'Basic'
    capacity: 1
    redisCachePrivateEndpointName: '${abbrs.cacheRedis}${abbrs.privateEndpoints}${resourceToken}'
    vNetName: vnet.outputs.vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    redisCacheDnsZoneName: redisCachePrivateDnsZoneName
    apimServiceName: apim.outputs.apimName
  }
}

module vnet './modules/networking/vnet.bicep' = {
  name: 'vnet'
  scope: resourceGroup
  dependsOn: [
    dnsDeployment
  ]
  params: {
    name: !empty(vnetName) ? vnetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    apimSubnetName: !empty(apimSubnetName) ? apimSubnetName : '${abbrs.networkVirtualNetworksSubnets}${abbrs.apiManagementService}${resourceToken}'
    apimNsgName: !empty(apimNsgName) ? apimNsgName : '${abbrs.networkNetworkSecurityGroups}${abbrs.apiManagementService}${resourceToken}'
    acaSubnetName: !empty(acaSubnetName) ? acaSubnetName : '${abbrs.networkVirtualNetworksSubnets}${abbrs.appContainerApps}${resourceToken}'
    acaNsgName: !empty(acaNsgName) ? acaNsgName : '${abbrs.networkNetworkSecurityGroups}${abbrs.appContainerApps}${resourceToken}'
    privateEndpointSubnetName: !empty(privateEndpointSubnetName) ? privateEndpointSubnetName : '${abbrs.networkVirtualNetworksSubnets}${abbrs.privateEndpoints}${resourceToken}'
    privateEndpointNsgName: !empty(privateEndpointNsgName) ? privateEndpointNsgName : '${abbrs.networkNetworkSecurityGroups}${abbrs.privateEndpoints}${resourceToken}'
    location: location
    tags: tags
    privateDnsZoneNames: privateDnsZoneNames
    apimSku: apimSku
  }
}

module monitoring './modules/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    dataCollectionEndpointName: !empty(dataCollectionEndpointName) ? dataCollectionEndpointName : '${abbrs.dataCollectionEndpoints}${resourceToken}'
    dataCollectionRuleName: !empty(dataCollectionRuleName) ? dataCollectionRuleName : '${abbrs.dataCollectionRules}${resourceToken}'
    vNetName: vnet.outputs.vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    applicationInsightsDnsZoneName: monitorPrivateDnsZoneName
    applicationInsightsPrivateEndpointName: '${abbrs.insightsComponents}${abbrs.privateEndpoints}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
    chargeBackManagedIdentityName: managedIdentityProxy.outputs.managedIdentityName
    
  }
}


var apimService = !empty(apimServiceName) ? apimServiceName : '${abbrs.apiManagementService}${resourceToken}'
module apimPip 'modules/networking/publicip.bicep' = {
  name: 'apim-pip'
  scope: resourceGroup
  params: {
    name: '${apimService}-pip'
    location: location
    tags: tags
    fqdn:'${apimService}.${location}.cloudapp.azure.com'
  }
}

module apim './modules/apim/apim.bicep' = {
  name: 'apim'
  scope: resourceGroup
  params: {
    name: apimService
    location: location
    tags: tags
    sku: apimSku
    virtualNetworkType: 'External'
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    apimManagedIdentityName: managedIdentityApim.outputs.managedIdentityName
    apimSubnetId: vnet.outputs.apimSubnetId
  }
}

module openAi './modules/ai/cognitiveservices.bicep' = {
  name: 'openai'
  scope: resourceGroup
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : '${abbrs.cognitiveServicesAccounts}${resourceToken}-${location}'
    location: location
    tags: tags
    chargeBackManagedIdentityName: managedIdentityProxy.outputs.managedIdentityName
    deploymentScriptIdentityName: managedIdentityDeploymentScript.outputs.managedIdentityName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    sku: {
      name: openAiSkuName
    }
    deployments: [
      {
        name: gptDeploymentName
        model: {
          format: 'OpenAI'
          name: gptModelName
          version: gptModelVersion
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: embeddingDeploymentName
        model: {
          format: 'OpenAI'
          name: embeddingModelName
          version: embeddingModelVersion
        }
      }
    ]
    openAiPrivateEndpointName: '${abbrs.cognitiveServicesAccounts}${abbrs.privateEndpoints}${resourceToken}-${location}'
    vNetName: vnet.outputs.vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    openAiDnsZoneName: openAiPrivateDnsZoneName
  }
}

module openAiSecondary './modules/ai/cognitiveservices.bicep' = if (secondaryOpenAILocation != '') {
  name: 'openai-secondary'
  scope: resourceGroup
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : '${abbrs.cognitiveServicesAccounts}${resourceToken}-${secondaryOpenAILocation}'
    location: secondaryOpenAILocation
    privateEndpointLocation: location
    tags: tags
    chargeBackManagedIdentityName: managedIdentityProxy.outputs.managedIdentityName
    deploymentScriptIdentityName: managedIdentityDeploymentScript.outputs.managedIdentityName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    sku: {
      name: openAiSkuName
    }
    deployments: [
      {
        name: gptDeploymentName
        model: {
          format: 'OpenAI'
          name: gptModelName
          version: gptModelVersionSecondary
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: embeddingDeploymentName
        model: {
          format: 'OpenAI'
          name: embeddingModelName
          version: embeddingModelVersionSecondary
        }
      }

    ]
    openAiPrivateEndpointName: '${abbrs.cognitiveServicesAccounts}${abbrs.privateEndpoints}${resourceToken}-${secondaryOpenAILocation}'
    vNetName: vnet.outputs.vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    openAiDnsZoneName: openAiPrivateDnsZoneName
  }
}

module containerRegistry './modules/host/container-registry.bicep' = {
  name: 'container-registry'
  scope: resourceGroup
  params: {
    name: !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
    chargeBackManagedIdentityName: managedIdentityProxy.outputs.managedIdentityName
    myIpAddress: myIpAddress
    //needed for container app deployment
    adminUserEnabled: true
    publicNetworkAccess: myIpAddress == '' ? 'Disabled': 'Enabled'
    containerRegistryDnsZoneName: containerRegistryPrivateDnsZoneName
    containerRegistryPrivateEndpointName: '${abbrs.containerRegistryRegistries}-${abbrs.privateEndpoints}${resourceToken}'
    vNetName: vnet.outputs.vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    
  }
}

module containerAppsEnvironment './modules/host/container-app-environment.bicep' = {
  name: 'container-apps-environment'
  scope: resourceGroup
  params: {
    name: !empty(containerAppsEnvironmentName) ? containerAppsEnvironmentName : '${abbrs.appManagedEnvironments}${resourceToken}' 
    location: location
    tags: tags
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    vnetName: vnet.outputs.vnetName
    subnetName: vnet.outputs.acaSubnetName
  }
}

module app './modules/host/container-app.bicep' = {
  name: 'container-app'
  scope: resourceGroup
  params: {
    name: !empty(proxyAppName) ? proxyAppName : '${abbrs.appContainerApps}${resourceToken}-proxy'
    location: location
    tags: tags
    identityName: managedIdentityProxy.outputs.managedIdentityName
    //deploy sample image first - we need the endpoint already for APIM
    //real image will be deployed later
    imageName: ''
    apimServiceName: apim.outputs.apimName
    external: true
    env: [
      {
        name: 'APPCONFIG_ENDPOINT'
        value: appconfig.outputs.appConfigEndPoint
      }
      {
        name: 'CLIENT_ID'
        value: managedIdentityProxy.outputs.managedIdentityClientId
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: monitoring.outputs.applicationInsightsConnectionString
      }
    ]
    pullFromPrivateRegistry: true
    azdServiceName: 'proxy'
    containerAppsEnvironmentName: containerAppsEnvironment.outputs.name
    containerRegistryName: containerRegistry.outputs.name
    targetPort: 8080
  }
  dependsOn: [
    containerRegistry
    containerAppsEnvironment
  ]
}


//create the proxyconfig structure for appconfig
//based of the endpoints we've created
var primaryOpenAiEndpoint = {
  address: openAi.outputs.openAIEndpointUriRaw
  priority: 1
  
}
var secondaryOpenAiEndpoint = secondaryOpenAILocation != '' ? {
  address: openAiSecondary.outputs.openAIEndpointUriRaw
  priority: 2
} : {}

var proxyConfig = {
  routes: [
    {
      name: gptDeploymentName
      endpoints:[
        primaryOpenAiEndpoint
        secondaryOpenAiEndpoint
      ]
    }
    {
      name: embeddingDeploymentName
      endpoints:[
        primaryOpenAiEndpoint
        secondaryOpenAiEndpoint
      ]
    }
  ]
}


module appconfig 'modules/appconfig/appconfiguration.bicep' = {
  name: 'appconfig'
  scope: resourceGroup
  params: {
    name: !empty(appConfigurationName) ? appConfigurationName : '${abbrs.appConfigurationConfigurationStores}${resourceToken}'
    AzureMonitorDataCollectionEndPointUrl: monitoring.outputs.dataCollectionEndpointUrl
    AzureMonitorDataCollectionRuleStream: monitoring.outputs.dataCollectionRuleStreamName
    AzureMonitorDataCollectionRuleImmutableId: monitoring.outputs.dataCollectionRuleImmutableId
    location: location
    AzureOpenAIEndpoints: array(openAi.outputs.openAIEndpointUriRaw)
    proxyManagedIdentityName: managedIdentityProxy.outputs.managedIdentityName
    ProxyConfig: proxyConfig
  }
}

output TENTANT_ID string = subscription().tenantId
output DEPLOYMENT_LOCATION string = location
output APIM_NAME string = apim.outputs.apimName
output RESOURCE_TOKEN string = resourceToken
output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_PROXY_MANAGED_IDENTITY_NAME string = managedIdentityProxy.outputs.managedIdentityName
output AZURE_APPCONFIG_ENDPOINT string = appconfig.outputs.appConfigEndPoint
output AZURE_RESOURCE_GROUP string = resourceGroup.name
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
