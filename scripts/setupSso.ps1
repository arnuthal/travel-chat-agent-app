Write-Host "Loading azd .env file from current environment..."

$envValues = azd env get-values
$envValues.Split("`n") | ForEach-Object {
    $key, $value = $_.Split('=')
    $value = $value.Trim('"')
    Set-Variable -Name $key -Value $value -Scope Global
}

if ($ENABLE_AUTH -ne "true") {
    return
}

# If App Registration was not created, create it
if ($CLIENT_ID -eq $null) {
    Write-Host "Creating app registration..."
    $APP = (az ad app create --display-name $BACKEND_APP_NAME --web-redirect-uris "https://$BACKEND_APP_NAME.azurewebsites.net/.auth/login/aad/callback" "https://token.botframework.com/.auth/web/redirect" --enable-id-token-issuance --required-resource-accesses '[{
        \"resourceAppId\": \"00000003-0000-0000-c000-000000000000\",
        \"resourceAccess\": [
            {
                \"id\": \"37f7f235-527c-4136-accd-4a02d197296e\",
                \"type\": \"Scope\"
            }
        ]
    }]' | ConvertFrom-Json)
    $APP_ID = $APP.id
    $CLIENT_ID = $APP.appId
}

# If a federated identity doesn't exist, create it

$uuid_no_hyphens = $AZURE_TENANT_ID -replace "-", ""
$uuid_reordered = $uuid_no_hyphens.Substring(6, 2) + $uuid_no_hyphens.Substring(4, 2) + $uuid_no_hyphens.Substring(2, 2) + $uuid_no_hyphens.Substring(0, 2) +
                  $uuid_no_hyphens.Substring(10, 2) + $uuid_no_hyphens.Substring(8, 2) +
                  $uuid_no_hyphens.Substring(14, 2) + $uuid_no_hyphens.Substring(12, 2) +
                  $uuid_no_hyphens.Substring(16, 16)
$uuid_binary = [System.Convert]::FromHexString($uuid_reordered)
$B64_AZURE_TENANT_ID = [Convert]::ToBase64String($uuid_binary) -replace '\+', '-' -replace '/', '_' -replace '=', ''

$FED_ID = (az ad app federated-credential list --id $CLIENT_ID | ConvertFrom-Json)[0].id
Write-Host "Federated identity: $FED_ID"
echo "{
        `"audiences`": [`"api://AzureADTokenExchange`"],
        `"description`": `"`",
        `"issuer`": `"https://login.microsoftonline.com/$AZURE_TENANT_ID/v2.0`",
        `"name`": `"default`",
        `"subject`": `"/eid1/c/pub/t/$B64_AZURE_TENANT_ID/a/9ExAW52n_ky4ZiS_jhpJIQ/$MSI_PRINCIPAL_ID`"
    }" | Out-File tmp.json
if ($FED_ID -eq $null) {
    Write-Host "Creating federated identity..."
    az ad app federated-credential create --id $CLIENT_ID --parameters tmp.json | Out-Null
} else {
    Write-Host "Federated identity already exists. Skipping..."
}
rm tmp.json

# Set up authorization for the app
az webapp auth config-version upgrade -g $AZURE_RESOURCE_GROUP_NAME -n $BACKEND_APP_NAME
az webapp auth update -g $AZURE_RESOURCE_GROUP_NAME -n $BACKEND_APP_NAME --enabled $true --action RedirectToLoginPage --redirect-provider azureactivedirectory --excluded-paths "[/api/messages]"
az webapp auth microsoft update -g $AZURE_RESOURCE_GROUP_NAME -n $BACKEND_APP_NAME --allowed-token-audiences "https://$BACKEND_APP_NAME.azurewebsites.net/.auth/login/aad/callback" --client-id $CLIENT_ID --issuer "https://sts.windows.net/$AZURE_TENANT_ID/"