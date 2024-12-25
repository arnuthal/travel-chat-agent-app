import os
import re
import pytest
from dotenv import load_dotenv
from unittest.mock import MagicMock
from botbuilder.core import ConversationState, UserState, MemoryStorage, TurnContext
from botbuilder.schema import Attachment as BotAttachment, ChannelAccount
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.ai.projects import AIProjectClient
from openai import AzureOpenAI

from bots import AssistantBot
from services.bing import BingClient
from services.graph import GraphClient
from dialogs import LoginDialog
from data_models import Attachment
from utils import create_or_update_agent

current_directory = os.path.dirname(__file__)
credential = DefaultAzureCredential(managed_identity_client_id=os.getenv("MicrosoftAppId"))
load_dotenv()

@pytest.fixture()
async def turn_context(loop):
    return MagicMock(spec=TurnContext)

@pytest.fixture()
async def aoai_client(loop):
    aoai_client = AzureOpenAI(
        api_version=os.getenv("AZURE_OPENAI_API_VERSION"),
        azure_endpoint=os.getenv("AZURE_OPENAI_API_ENDPOINT"),
        api_key=os.getenv("AZURE_OPENAI_API_KEY"),
        azure_ad_token_provider=get_bearer_token_provider(
            credential, 
            "https://cognitiveservices.azure.com/.default"
        )
    )
    # aoai_client = MagicMock(spec=AzureOpenAI)
    return aoai_client

project_client = AIProjectClient.from_connection_string(
    credential=credential,
    conn_str=os.getenv("AZURE_AI_PROJECT_CONNECTION_STRING")
)
agents_client = project_client.agents
agent_id = create_or_update_agent(agents_client, os.getenv("AZURE_OPENAI_AGENT_NAME"))

@pytest.fixture()
async def bot(aoai_client, turn_context):
    _bot = AssistantBot(
        conversation_state=ConversationState(MemoryStorage()),
        user_state=UserState(MemoryStorage()),
        aoai_client=aoai_client,
        agents_client=agents_client,
        agent_id=agent_id,
        bing_client=BingClient(os.getenv("AZURE_BING_API_KEY")),
        graph_client=GraphClient(),
        dialog=LoginDialog()
    )
    conversation_data = await _bot.conversation_data_accessor.get(turn_context)
    conversation_data.thread_id = None
    return _bot

async def test_welcome_message(bot, turn_context):
    await bot.on_members_added_activity([ChannelAccount(id='user1')], turn_context)
    turn_context.send_activity.assert_called_with(os.getenv("LLM_WELCOME_MESSAGE"))

async def test_text_message(bot, turn_context):
    turn_context.activity.text = "This is a test. Please respond with \"Test succeeded\""
    await bot.on_message_activity(turn_context)
    assert "Test succeeded" in turn_context.send_activity.mock_calls[0][1][0].text

async def test_teams_message(bot, turn_context):
    # Teams messages contain HTML attachments of the same message, which should be ignored
    turn_context.activity.text = "This is a test. Please respond with \"Test succeeded\""
    turn_context.activity.attachments = [BotAttachment(content_type="text/html", content="<span>This is a test. Please respond with \"Test succeeded\"</span>", content_url=None)]
    await bot.on_message_activity(turn_context)
    assert "Test succeeded" in turn_context.send_activity.mock_calls[0][1][0].text

async def test_streaming_response(bot, turn_context):
    turn_context.activity.text = "Please write a paragraph on AI"
    turn_context.activity.channel_id = "directline"
    await bot.on_message_activity(turn_context)

    assert len(turn_context.send_activity.mock_calls) > 1
    # Each new message should contain the previous
    for i in range(1, len(turn_context.send_activity.mock_calls)):
        assert len(turn_context.send_activity.mock_calls[i][1][0].text) > len(turn_context.send_activity.mock_calls[i-1][1][0].text)
        assert  turn_context.send_activity.mock_calls[i-1][1][0].text == "Typing..." or \
                turn_context.send_activity.mock_calls[i][1][0].text.startswith(turn_context.send_activity.mock_calls[i-1][1][0].text)

async def test_updating_response(bot, turn_context):
    turn_context.activity.text = "Please write a paragraph on AI"
    turn_context.activity.channel_id = "msteams"
    await bot.on_message_activity(turn_context)

    assert len(turn_context.update_activity.mock_calls) > 1
    # Each new message should contain the previous
    for i in range(1, len(turn_context.update_activity.mock_calls)):
        assert len(turn_context.update_activity.mock_calls[i][1][0].text) > len(turn_context.update_activity.mock_calls[i-1][1][0].text)
        assert  turn_context.update_activity.mock_calls[i-1][1][0].text == "Typing..." or \
                turn_context.update_activity.mock_calls[i][1][0].text.startswith(turn_context.update_activity.mock_calls[i-1][1][0].text)

async def test_image_response(bot, turn_context):
    turn_context.activity.text = "Please plot numbers 1-10"
    await bot.on_message_activity(turn_context)
    # Should contain an image markdown link in any position
    assert re.search(r"!\[.*\]\(.*\)", turn_context.send_activity.mock_calls[0][1][0].text)

async def test_clear_message(bot, turn_context, aoai_client):
    conversation_data = await bot.conversation_data_accessor.get(turn_context)
    conversation_data.history = ["message_1", "message_2"]
    turn_context.activity.text = "clear"
    await bot.on_message_activity(turn_context)
    # Should clear the thread id and history from the conversation state
    assert conversation_data.thread_id is None
    assert len(conversation_data.history) == 0
    
async def test_file_upload(bot, turn_context, aoai_client):
    attachment = MagicMock(spec=BotAttachment)
    attachment.name = "file_name.txt"
    attachment.content_type = "file_type"
    attachment.content_url = "file_url"
    attachment.content = None
    turn_context.activity.attachments = [attachment]
    await bot.on_message_activity(turn_context)

async def test_teams_upload(bot, turn_context, aoai_client):
    attachment = MagicMock(spec=BotAttachment)
    attachment.name = "file_name.txt"
    attachment.content_type = "file_type"
    attachment.content_url = "file_url"
    attachment.content = {
        "downloadUrl": f"file://{current_directory}/../../data/ContosoBenefits.pdf",
    }
    turn_context.activity.attachments = [attachment]
    await bot.on_message_activity(turn_context)

async def test_tool_selection(bot, turn_context, aoai_client):
    conversation_data = await bot.conversation_data_accessor.get(turn_context)
    conversation_data.attachments = [Attachment(name="file_name.txt", content_type="file_type", url=f"file://{current_directory}/../../data/ContosoBenefits.pdf")]
    turn_context.activity.text = ":Code Interpreter"
    await bot.on_message_activity(turn_context)
    
async def test_image_query(bot, turn_context, aoai_client):
    attachment = BotAttachment(
        name="fork.jpg",
        content_type="image/jpeg",
        content_url=f"file://{current_directory}/../../data/fork.jpeg"
    )
    turn_context.activity.attachments = [attachment]
    await bot.on_message_activity(turn_context)
    assert "File uploaded: fork.jpg" in turn_context.send_activity.mock_calls[0][1][0].text
    assert "Add to a tool?" in turn_context.send_activity.mock_calls[1][1][0].text
    conversation_data = await bot.conversation_data_accessor.get(turn_context)
    conversation_data.attachments = [Attachment(name="fork.jpg", content_type="image/jpeg", url=f"file://{current_directory}/../../data/fork.jpg")]
    turn_context.activity.attachments = []
    turn_context.activity.text = "What's in this image?"
    await bot.on_message_activity(turn_context)
    assert "fork" in turn_context.send_activity.mock_calls[2][1][0].text

async def test_file_search(bot, turn_context, aoai_client):
    attachment = BotAttachment(
        name="ContosoBenefits.pdf",
        content_type="image/jpeg",
        content_url=f"file://{current_directory}/../../data/ContosoBenefits.pdf"
    )
    turn_context.activity.attachments = [attachment]
    await bot.on_message_activity(turn_context)
    assert "File uploaded: ContosoBenefits.pdf" in turn_context.send_activity.mock_calls[0][1][0].text
    assert "Add to a tool?" in turn_context.send_activity.mock_calls[1][1][0].text
    conversation_data = await bot.conversation_data_accessor.get(turn_context)
    conversation_data.attachments = [Attachment(name="ContosoBenefits.pdf", content_type="application/pdf", url=f"file://{current_directory}/../../data/ContosoBenefits.pdf")]
    turn_context.activity.attachments = []
    turn_context.activity.text = ":File Search"
    await bot.on_message_activity(turn_context)
    assert "added to File Search" in turn_context.send_activity.mock_calls[2][1][0].text
    turn_context.activity.text = "What is my dental care coverage limit?"
    await bot.on_message_activity(turn_context)
    assert "1000" or "1,000" in turn_context.send_activity.mock_calls[3][1][0].text
