import pytest
from unittest.mock import MagicMock
from botbuilder.integration.aiohttp import CloudAdapter, ConfigurationBotFrameworkAuthentication
from botbuilder.core import TurnContext
from azure.keyvault.secrets import SecretClient
from azure.ai.projects.operations import AgentsOperations

from config import DefaultConfig
from bots import AssistantBot
from app import create_app


config = DefaultConfig()
adapter = CloudAdapter(ConfigurationBotFrameworkAuthentication(config))
bot = MagicMock(spec=AssistantBot)
agents_client = MagicMock(spec=AgentsOperations)
secrets_client = MagicMock(spec=SecretClient)
@pytest.fixture()
async def client(aiohttp_client):
    bot.reset_mock()
    return await aiohttp_client(create_app(adapter, bot, agents_client, secrets_client))

async def test_welcome_message(client):
    bot.configure_mock(**{"on_turn.return_value": "Mock Response"})
    resp = await client.post('/api/messages', json={'type': 'conversationUpdate', 'membersAdded': [{'id': '8c4406d0-9306-11ef-a822-c7d38543b543', 'name': 'Bot'}, {'id': '7c3792c0-c8a3-4df1-9ee8-f5c8b99b53f3', 'name': 'User'}], 'membersRemoved': [], 'channelId': 'emulator', 'conversation': {'id': 'bcabaf70-9311-11ef-a822-c7d38543b543|livechat'}, 'id': 'bcbf3770-9311-11ef-b0e8-69aa58527b92', 'localTimestamp': '2024-10-25T17:43:06-03:00', 'recipient': {'id': '8c4406d0-9306-11ef-a822-c7d38543b543', 'name': 'Bot', 'role': 'bot'}, 'timestamp': '2024-10-25T20:43:06.214Z', 'from': {'id': '7c3792c0-c8a3-4df1-9ee8-f5c8b99b53f3', 'name': 'User', 'role': 'user'}, 'locale': 'en-US', 'serviceUrl': 'http://localhost:55301'})
    assert resp.status == 200

async def test_invalid_content(client):
    resp = await client.post('/api/messages', headers={"Content-Type": "text/plain"}, data="Hello, World!")
    assert resp.status == 415

async def test_adapter_on_error(client):
    mockContext = MagicMock(spec=TurnContext)
    await adapter.on_turn_error(mockContext, Exception("Test Exception"))
    mockContext.send_activity.assert_called_with("Test Exception")