param bingName string
param keyVaultName string
param tags object = {}
// param privateEndpointSubnetId string
// param publicNetworkAccess string
// param bingPrivateDnsZoneId string
// param grantAccessTo array
// param allowedIpAddresses array = []
// param authMode string

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  
  resource secret 'secrets' = {
    name: 'BING-API-KEY'
    properties: {
      value: bing.listKeys().key1
    }
  }
}
resource bing 'Microsoft.Bing/accounts@2020-06-10' = {
  name: bingName
  location: 'global'
  tags: tags
  sku: {
    name: 'S1'
  }
  kind: 'Bing.Search.v7'
}

output bingID string = bing.id
output bingName string = bing.name
output bingApiEndpoint string = bing.properties.endpoint
