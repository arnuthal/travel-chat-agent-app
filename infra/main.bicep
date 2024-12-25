targetScope = 'subscription'

// Common configurations
@description('Name of the environment')
param environmentName string
@description('Principal ID to grant access to the AI services. Leave empty to skip')
param myPrincipalId string = ''
@description('Current principal type being used')
@allowed(['User', 'ServicePrincipal'])
param myPrincipalType string
@description('IP addresses to grant access to the AI services. Leave empty to skip')
param allowedIpAddresses string = ''
var allowedIpAddressesArray = !empty(allowedIpAddresses) ? split(allowedIpAddresses, ',') : []
@description('Resource group name for the AI services. Defauts to rg-<environmentName>')
param resourceGroupName string = ''
@description('Resource group name for the DNS configurations. Defaults to rg-dns')
param dnsResourceGroupName string = ''
@description('Tags for all AI resources created. JSON object')
param tags object = {}

// Network configurations
@description('Allow or deny public network access to the AI services (recommended: Disabled)')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string
@description('Authentication type to use (recommended: identity)')
@allowed(['identity', 'accessKey'])
param authMode string = 'identity'
@description('Address prefixes for the spoke vNet')
param vnetAddressPrefixes array = ['10.0.0.0/16']
@description('Address prefix for the private endpoint subnet')
param privateEndpointSubnetAddressPrefix string = '10.0.0.0/24'
@description('Address prefix for the application subnet')
param appSubnetAddressPrefix string = '10.0.1.0/24'

// AI Services configurations
@description('Name of the AI Services account. Automatically generated if left blank')
param aiServicesName string = ''
@description('Name of the AI Hub resource. Automatically generated if left blank')
param aiHubName string = ''
@description('Name of the Storage Account. Automatically generated if left blank')
param storageName string = ''
@description('Name of the Key Vault. Automatically generated if left blank')
param keyVaultName string = ''
@description('Name of the Bing account. Automatically generated if left blank')
param bingName string = ''
@description('Name of the Bot Service. Automatically generated if left blank')
param botName string = ''

// Other configurations
@description('Name of the Bot Service. Automatically generated if left blank')
param msiName string = ''
@description('Name of the Cosmos DB Account. Automatically generated if left blank')
param cosmosName string = ''
@description('Name of the App Service Plan. Automatically generated if left blank')
param appPlanName string = ''
@description('Name of the App Services Instance. Automatically generated if left blank')
param appName string = ''
@description('Whether to enable authentication (requires Entra App Developer role)')
param enableAuthentication bool = false
@description('Whether to deploy an AI Hub')
param deployAIHub bool = true
@description('Whether to deploy a sample AI Project')
param deployAIProject bool = true

@description('Gen AI model name and version to deploy')
@allowed(['gpt-4;1106-Preview', 'gpt-4;0125-Preview', 'gpt-4o;2024-05-13', 'gpt-4o-mini;2024-07-18'])
param model string
@description('Tokens per minute capacity for the model. Units of 1000 (capacity = 10 means 10,000 tokens per minute)')
param modelCapacity int


// Location and overrides
@description('Location to deploy AI Services')
param aiServicesLocation string = deployment().location
@description('Location to deploy Cosmos DB')
param cosmosLocation string = deployment().location
@description('Location to deploy App Service')
param appServiceLocation string = deployment().location
@description('Location to deploy Bot Service')
param botServiceLocation string = 'global'
@description('Location to deploy Storage account')
param storageLocation string = deployment().location
@description('Location to deploy Key Vault')
param keyVaultLocation string = deployment().location
@description('Location to deploy Managed Identity')
param msiLocation string = deployment().location
@description('Location to deploy virtual network resources')
param vnetLocation string = deployment().location
@description('Location to deploy private DNS zones')
param dnsLocation string = deployment().location

var modelName = split(model, ';')[0]
var modelVersion = split(model, ';')[1]

var abbrs = loadJsonContent('abbreviations.json')
var uniqueSuffix = substring(uniqueString(subscription().id, environmentName), 1, 3)
var location = deployment().location

var names = {
  resourceGroup: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  dnsResourceGroup: !empty(dnsResourceGroupName) ? dnsResourceGroupName : '${abbrs.resourcesResourceGroups}dns'
  msi: !empty(msiName) ? msiName : '${abbrs.managedIdentityUserAssignedIdentities}${environmentName}-${uniqueSuffix}'
  cosmos: !empty(cosmosName) ? cosmosName : '${abbrs.documentDBDatabaseAccounts}${environmentName}-${uniqueSuffix}'
  appPlan: !empty(appPlanName) ? appPlanName : '${abbrs.webSitesAppServiceEnvironment}${environmentName}-${uniqueSuffix}'
  app: !empty(appName) ? appName : '${abbrs.webSitesAppService}${environmentName}-${uniqueSuffix}'
  bot: !empty(botName) ? botName : '${abbrs.cognitiveServicesBot}${environmentName}-${uniqueSuffix}'
  vnet: '${abbrs.networkVirtualNetworks}${environmentName}-${uniqueSuffix}'
  privateLinkSubnet: '${abbrs.networkVirtualNetworksSubnets}${environmentName}-pl-${uniqueSuffix}'
  appSubnet: '${abbrs.networkVirtualNetworksSubnets}${environmentName}-app-${uniqueSuffix}'
  aiServices: !empty(aiServicesName) ? aiServicesName : '${abbrs.cognitiveServicesAccounts}${environmentName}-${uniqueSuffix}'
  aiHub: !empty(aiHubName) ? aiHubName : '${abbrs.cognitiveServicesAccounts}hub-${environmentName}-${uniqueSuffix}'
  storage: !empty(storageName) ? storageName : replace(replace('${abbrs.storageStorageAccounts}${environmentName}${uniqueSuffix}', '-', ''), '_', '')
  keyVault: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${environmentName}-${uniqueSuffix}'
  bing: !empty(bingName) ? bingName : '${abbrs.cognitiveServicesBing}${environmentName}-${uniqueSuffix}'
}

// Private Network Resources
var dnsZones = [
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.vaultcore.azure.net'
  'privatelink.search.azure.com'
  'privatelink.documents.azure.com'
  'privatelink.api.azureml.ms'
  'privatelink.notebooks.azure.net'
  'privatelink.azurewebsites.net'
]

var dnsZoneIds = publicNetworkAccess == 'Disabled' ? m_dns.outputs.dnsZoneIds : dnsZones
var privateEndpointSubnetId = publicNetworkAccess == 'Disabled' ? m_network.outputs.privateEndpointSubnetId : ''

// Deploy two resource groups
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: names.resourceGroup
  location: location
  tags: union(tags, { 'azd-env-name': environmentName })
}

resource dnsResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = if (publicNetworkAccess == 'Disabled') {
  name: names.dnsResourceGroup
  location: empty(dnsLocation) ? location : dnsLocation
  tags: tags
}

// Network module - deploys Vnet
module m_network 'modules/aistudio/network.bicep' = if (publicNetworkAccess == 'Disabled') {
  name: 'deploy_vnet'
  scope: resourceGroup
  params: {
    location: empty(vnetLocation) ? location : vnetLocation 
    vnetName: names.vnet
    vnetAddressPrefixes: vnetAddressPrefixes
    privateEndpointSubnetName: names.privateLinkSubnet
    privateEndpointSubnetAddressPrefix: privateEndpointSubnetAddressPrefix
    appSubnetName: names.appSubnet
    appSubnetAddressPrefix: appSubnetAddressPrefix
  }
}

// DNS module - deploys private DNS zones and links them to the Vnet
module m_dns 'modules/aistudio/dns.bicep' = if (publicNetworkAccess == 'Disabled') {
  name: 'deploy_dns'
  scope: dnsResourceGroup
  params: {
    vnetId: publicNetworkAccess == 'Disabled' ? m_network.outputs.vnetId : ''
    vnetName: publicNetworkAccess == 'Disabled' ? m_network.outputs.vnetName : ''
    dnsZones: dnsZones
  }
}

module m_msi 'modules/msi.bicep' = {
  name: 'deploy_msi'
  scope: resourceGroup
  params: {
    location: empty(msiLocation) ? location : msiLocation
    msiName: names.msi
    tags: tags
  }
}

// AI Services module
module m_aiservices 'modules/aistudio/aiservices.bicep' = {
  name: 'deploy_aiservices'
  scope: resourceGroup
  params: {
    location: empty(aiServicesLocation) ? location : aiServicesLocation
    vnetLocation: empty(vnetLocation) ? location : vnetLocation 
    aiServicesName: names.aiServices
    publicNetworkAccess: publicNetworkAccess
    privateEndpointSubnetId: privateEndpointSubnetId
    openAIPrivateDnsZoneId: dnsZoneIds[0]
    cognitiveServicesPrivateDnsZoneId: dnsZoneIds[1]
    authMode: authMode
    grantAccessTo: authMode == 'identity'
      ? [
          {
            id: myPrincipalId
            type: myPrincipalType
          }
          {
            id: m_msi.outputs.msiPrincipalID
            type: 'ServicePrincipal'
          }
        ]
      : []
    allowedIpAddresses: allowedIpAddressesArray
    tags: tags
  }
}

// Storage and Key Vault
module m_storage 'modules/aistudio/storage.bicep' = {
  name: 'deploy_storage'
  scope: resourceGroup
  params: {
    location: empty(storageLocation) ? location : storageLocation
    vnetLocation: empty(vnetLocation) ? location : vnetLocation 
    storageName: names.storage
    publicNetworkAccess: publicNetworkAccess
    authMode: authMode
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneId: dnsZoneIds[2]
    grantAccessTo: authMode == 'identity'
      ? [
          {
            id: myPrincipalId
            type: myPrincipalType
          }
          {
            id: m_msi.outputs.msiPrincipalID
            type: 'ServicePrincipal'
          }
        ]
      : []
    tags: tags
  }
}

module m_keyVault 'modules/aistudio/keyVault.bicep' = {
  name: 'deploy_keyVault'
  scope: resourceGroup
  params: {
    location: empty(keyVaultLocation) ? location : keyVaultLocation
    vnetLocation: empty(vnetLocation) ? location : vnetLocation  
    keyVaultName: names.keyVault
    publicNetworkAccess: publicNetworkAccess
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneId: dnsZoneIds[3]
    allowedIpAddresses: allowedIpAddressesArray
    grantAccessTo: [
        {
          id: myPrincipalId
          type: myPrincipalType
        }
        {
          id: m_msi.outputs.msiPrincipalID
          type: 'ServicePrincipal'
        }
      ]
    tags: tags
  }
}

// AI Hub module - deploys AI Hub and Project
module m_aihub 'modules/aistudio/aihub.bicep' = if (deployAIHub) {
  name: 'deploy_ai'
  scope: resourceGroup
  params: {
    location: empty(aiServicesLocation) ? location : aiServicesLocation
    vnetLocation: empty(vnetLocation) ? location : vnetLocation  
    aiHubName: names.aiHub
    aiProjectName: 'cog-ai-prj-${environmentName}-${uniqueSuffix}'
    aiServicesName: m_aiservices.outputs.aiServicesName
    keyVaultName: m_keyVault.outputs.keyVaultName
    storageName: names.storage
    publicNetworkAccess: publicNetworkAccess
    systemDatastoresAuthMode: authMode
    privateEndpointSubnetId: privateEndpointSubnetId
    apiPrivateDnsZoneId: dnsZoneIds[6]
    notebookPrivateDnsZoneId: dnsZoneIds[7]
    deployAIProject: deployAIProject
    allowedIpAddresses: allowedIpAddressesArray
    grantAccessTo: authMode == 'identity'
      ? [
          {
            id: myPrincipalId
            type: myPrincipalType
          }
          {
            id: m_msi.outputs.msiPrincipalID
            type: 'ServicePrincipal'
          }
        ]
      : []
    tags: tags
  }
}

// Bing module
module m_bing 'modules/bing.bicep' = {
  name: 'deploy_bing'
  scope: resourceGroup
  params: {
    bingName: names.bing
    keyVaultName: m_keyVault.outputs.keyVaultName
    tags: tags
  }
}

module m_cosmos 'modules/cosmos.bicep' = {
  name: 'deploy_cosmos'
  scope: resourceGroup
  params: {
    location: empty(cosmosLocation) ? location : cosmosLocation
    vnetLocation: empty(vnetLocation) ? location : vnetLocation  
    cosmosName: names.cosmos
    keyVaultName: m_keyVault.outputs.keyVaultName
    publicNetworkAccess: publicNetworkAccess
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneId: dnsZoneIds[5]
    allowedIpAddresses: allowedIpAddressesArray
    authMode: authMode
    grantAccessTo: authMode == 'identity'
      ? [
          {
            id: myPrincipalId
            type: myPrincipalType
          }
          {
            id: m_msi.outputs.msiPrincipalID
            type: 'ServicePrincipal'
          }
        ]
      : []
    tags: tags
  }
}

module m_gpt 'modules/gptDeployment.bicep' = {
  name: 'deploygpt'
  scope: resourceGroup
  params: {
    aiServicesName: m_aiservices.outputs.aiServicesName
    modelName: modelName
    modelVersion: modelVersion
    modelCapacity: modelCapacity
  }
}

module m_app 'modules/appservice.bicep' = {
  name: 'deploy_app'
  scope: resourceGroup
  params: {
    location: empty(appServiceLocation) ? location : appServiceLocation
    vnetLocation: empty(vnetLocation) ? location : vnetLocation  
    appServicePlanName: names.appPlan
    appServiceName: names.app
    tags: tags
    publicNetworkAccess: publicNetworkAccess
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneId: dnsZoneIds[8]
    authMode: authMode
    appSubnetId: publicNetworkAccess == 'Disabled' ? m_network.outputs.appSubnetId : ''
    allowedIpAddresses: allowedIpAddressesArray
    msiID: m_msi.outputs.msiID
    msiClientID: m_msi.outputs.msiClientID
    cosmosName: m_cosmos.outputs.cosmosName
    deploymentName: m_gpt.outputs.modelName
    aiServicesName: m_aiservices.outputs.aiServicesName
    bingName: m_bing.outputs.bingName
    aiHubName: m_aihub.outputs.aiHubName
    aiProjectName: m_aihub.outputs.aiProjectName
    keyVaultName: m_keyVault.outputs.keyVaultName
  }
}

module m_bot 'modules/botservice.bicep' = {
  name: 'deploy_bot'
  scope: resourceGroup
  params: {
    location: empty(botServiceLocation) ? location : botServiceLocation
    botServiceName: names.bot
    keyVaultName: m_keyVault.outputs.keyVaultName
    tags: tags
    endpoint: 'https://${m_app.outputs.backendHostName}/api/messages'
    msiClientID: m_msi.outputs.msiClientID
    msiID: m_msi.outputs.msiID
    publicNetworkAccess: publicNetworkAccess
  }
}

output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP_ID string = resourceGroup.id
output AZURE_RESOURCE_GROUP_NAME string = resourceGroup.name
output AI_SERVICES_ENDPOINT string = m_aiservices.outputs.aiServicesEndpoint
output BACKEND_APP_NAME string = m_app.outputs.backendAppName
output BACKEND_APP_HOSTNAME string = m_app.outputs.backendHostName
output MSI_PRINCIPAL_ID string = m_msi.outputs.msiPrincipalID
output ENABLE_AUTH bool = enableAuthentication
output AUTH_MODE string = authMode

output AZURE_COSMOSDB_ENDPOINT string = m_cosmos.outputs.cosmosEndpoint
output AZURE_KEY_VAULT_ENDPOINT string = m_keyVault.outputs.keyVaultEndpoint
output AZURE_OPENAI_API_ENDPOINT string = m_aiservices.outputs.aiServicesEndpoint
output AZURE_OPENAI_API_VERSION string = '2024-07-01-preview'
output AZURE_OPENAI_ASSISTANT_NAME string = 'azure-agents-python'
output AZURE_OPENAI_DEPLOYMENT_NAME string = m_gpt.outputs.modelName
output AZURE_OPENAI_STREAMING bool = false
output AZURE_AI_PROJECT_CONNECTION_STRING string = m_aihub.outputs.aiProjectConnectionString
output AZURE_BING_CONNECTION_ID string = m_bing.outputs.bingName
output LLM_INSTRUCTIONS string = 'Welcome to the Travel Agent Sample! You can use this chat to: <br>&ensp;- Get recommendations of places to visit and things to do;<br>&ensp;- Upload your travel bookings and generate an itinerary;<br>&ensp;- Upload pictures of signs, menus and more to get information about them;<br>&ensp;- Ask for help with budgeting a trip;<br>&ensp;- And more!<br> To upload files, use the attachment button on the left, attach a file and hit enter to upload. You will get confirmation when the file is ready to use. You will also be prompted whether you\'d like to add it to Code Interpreter or File Search. Use Code Interpreter for mathematical operations, and File Search to use the file contents as context for your question. You may skip this step for images.'
output LLM_WELCOME_MESSAGE string = 'You are a helpful travel agent who can assist with many travel-related inquiries, including:\n- Reading travel documents and putting together itineraries\n- Viewing and interpreting pictures that may be in different languages\n- Locating landmarks and suggesting places to visit\n- Budgeting and graphing cost information\n- Looking up information on the web for up to date information\nYou should do your best to respond to travel-related questions, but politely decline to help with unrelated questions.\nAny time the information you want to provide requires up-to-date sources - for example, hotels, restaurants and more - you should use the Bing Search tool and provide sources.'
output MAX_TURNS int = 20
