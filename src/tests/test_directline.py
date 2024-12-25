import os
import pytest
from unittest.mock import MagicMock
from botbuilder.integration.aiohttp import CloudAdapter, ConfigurationBotFrameworkAuthentication
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.ai.projects.operations import AgentsOperations

from config import DefaultConfig
from bots import AssistantBot
from app import create_app


@pytest.fixture()
async def client(aiohttp_client):
    config = DefaultConfig()
    adapter = CloudAdapter(ConfigurationBotFrameworkAuthentication(config))
    bot = MagicMock(spec=AssistantBot)
    agents_client = MagicMock(spec=AgentsOperations)
    credential = DefaultAzureCredential(managed_identity_client_id=os.getenv("MicrosoftAppId"))
    secret_client = SecretClient(vault_url=os.getenv("AZURE_KEY_VAULT_ENDPOINT"), credential=credential)
    return await aiohttp_client(create_app(adapter, bot, agents_client, secret_client))

async def test_directline_token(client):
    resp = await client.get('/api/directline/token')
    assert resp.status == 200
    data = await resp.json()
    assert 'conversationId' in data
    assert 'token' in data
    assert data['token'].startswith('eyJ')