param location string
param botServiceName string
param keyVaultName string
param endpoint string
param msiID string
param msiClientID string
param sku string = 'F0'
param kind string = 'azurebot'
param tags object = {}
param publicNetworkAccess string


resource botservice 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botServiceName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  kind: kind
  properties: {
    displayName: botServiceName
    endpoint: endpoint
    msaAppMSIResourceId: msiID
    msaAppId: msiClientID
    msaAppType: 'UserAssignedMSI'
    msaAppTenantId: tenant().tenantId
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }

  resource directline 'channels' = {
    name: 'DirectLineChannel'
    properties: {
      channelName: 'DirectLineChannel'
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  
  resource secret 'secrets' = {
    name: 'AZURE-DIRECT-LINE-SECRET'
    properties: {
      value: botservice::directline.listChannelWithKeys().setting.sites[0].key
    }
  }
}

output name string = botservice.name
