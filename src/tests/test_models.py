import pytest
from unittest.mock import MagicMock
from botbuilder.core import TurnContext
from data_models import ConversationData

@pytest.fixture()
def turn_context():
    return MagicMock(spec=TurnContext)

def test_add_conversation_turn(turn_context):
    conversation_data = ConversationData([], max_turns=6)
    conversation_data.add_turn("user", "This is a test.")
    conversation_data.add_turn("assistant", "This is a response.")
    assert len(conversation_data.history) == 2
    conversation_data.add_turn("user", "This is a test.")
    conversation_data.add_turn("assistant", "This is a response.")
    assert len(conversation_data.history) == 4
    conversation_data.add_turn("user", "This is a test.")
    conversation_data.add_turn("assistant", "This is a response.")
    assert len(conversation_data.history) == 6
    # Caps out at max context length
    conversation_data.add_turn("user", "This is a test.")
    assert len(conversation_data.history) == 6
    conversation_data.add_turn("assistant", "This is a response.")
    assert len(conversation_data.history) == 6




