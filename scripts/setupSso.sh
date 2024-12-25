echo "Loading azd .env file from current environment..."

while IFS='=' read -r key value; do
    value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    export "$key=$value"
done <<EOF
$(azd env get-values)
EOF

if [ "$ENABLE_AUTH" != "true" ]; then
    exit 0
fi

# If App Registration was not created, create it
if [ -z "$CLIENT_ID" ]; then
    echo "Creating app registration..."
    APP=$(az ad app create \
        --display-name $BACKEND_APP_NAME \
        --web-redirect-uris https://$BACKEND_APP_NAME.azurewebsites.net/.auth/login/aad/callback https://token.botframework.com/.auth/web/redirect \
        --enable-id-token-issuance \
        --required-resource-accesses '[{
            "resourceAppId": "00000003-0000-0000-c000-000000000000",
            "resourceAccess": [
                {
                    "id": "37f7f235-527c-4136-accd-4a02d197296e",
                    "type": "Scope"
                }
           ]
        }]' \
    )
    APP_ID=$(echo $APP | jq -r .id)
    CLIENT_ID=$(echo $APP | jq -r .appId)
fi

# If a federated identity doesn't exist, create it
B64_AZURE_TENANT_ID=$(echo $AZURE_TENANT_ID | sed 's/^\(..\)\(..\)\(..\)\(..\)-\(..\)\(..\)-\(..\)\(..\)-\(..\)\(..\)-\(..\)\(.*\)$/\4\3\2\1\6\5\8\7\9\10\11\12/' | xxd -r -p | base64 | sed 's/=*$//')
FED_ID=$(az ad app federated-credential list --id $CLIENT_ID | jq -r ".[0].id")
echo "Federated identity: $FED_ID"
if [ "$FED_ID" = "null" ]; then
    echo "Creating federated identity..."
    az ad app federated-credential create --id $CLIENT_ID --parameters '{
        "audiences": [
            "api://AzureADTokenExchange"
        ],
        "description": "",
        "issuer": "https://login.microsoftonline.com/'$AZURE_TENANT_ID'/v2.0",
        "name": "default",
        "subject": "/eid1/c/pub/t/'$B64_AZURE_TENANT_ID'/a/9ExAW52n_ky4ZiS_jhpJIQ/'$MSI_PRINCIPAL_ID'"
    }'
else
    echo "Federated identity already exists. Skipping..."
fi

# Set up authorization for the app
az webapp auth config-version upgrade -g $AZURE_RESOURCE_GROUP_NAME -n $BACKEND_APP_NAME || true
az webapp auth update -g $AZURE_RESOURCE_GROUP_NAME -n $BACKEND_APP_NAME --enabled true \
    --action RedirectToLoginPage  --redirect-provider azureactivedirectory --excluded-paths "[/api/messages]"
az webapp auth microsoft update -g $AZURE_RESOURCE_GROUP_NAME -n $BACKEND_APP_NAME \
    --allowed-token-audiences https://$BACKEND_APP_NAME.azurewebsites.net/.auth/login/aad/callback \
    --client-id $CLIENT_ID \
    --issuer https://sts.windows.net/$AZURE_TENANT_ID/