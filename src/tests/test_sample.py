import pytest
from unittest.mock import MagicMock
from botbuilder.integration.aiohttp import CloudAdapter, ConfigurationBotFrameworkAuthentication
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
    secrets_client = MagicMock(spec=SecretClient)
    return await aiohttp_client(create_app(adapter, bot, agents_client, secrets_client))

async def test_homepage_has_reference(client):
    resp = await client.get('/')
    assert resp.status == 200
    text = await resp.text()
    assert 'https://github.com/microsoft/BotFramework-WebChat' in text