import pytest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch


class _FakeChatSessionQuery:
    def __init__(self, sessions):
        self._sessions = sessions

    def sort(self, *args, **kwargs):
        return self

    async def to_list(self):
        return self._sessions


class _FakeChatflowQuery:
    def __init__(self, chatflows):
        self._chatflows = chatflows

    async def to_list(self):
        return self._chatflows


@pytest.mark.asyncio
async def test_admin_get_user_sessions_returns_chatflow_name_when_available():
    from app.api.admin import admin_get_user_sessions

    session = SimpleNamespace(
        session_id="session-1",
        user_id="user-1",
        chatflow_id="flow-1",
        topic="Need help with algebra",
        is_active=True,
        created_at=None,
        last_activity_at=None,
    )
    chatflow = SimpleNamespace(flowise_id="flow-1", name="Algebra 101")

    mock_session_model = SimpleNamespace(
        user_id="user_id",
        created_at=1,
        find=lambda *args, **kwargs: _FakeChatSessionQuery([session]),
    )
    mock_message_model = SimpleNamespace(
        session_id="session_id",
        find=lambda *args, **kwargs: SimpleNamespace(count=AsyncMock(return_value=3)),
    )

    with patch("app.models.chat_session.ChatSession", mock_session_model), \
         patch("app.models.chat_message.ChatMessage", mock_message_model), \
         patch("app.api.admin.Chatflow.find", return_value=_FakeChatflowQuery([chatflow])):
        result = await admin_get_user_sessions("user-1", current_user={"role": "admin"})

    assert len(result) == 1
    assert result[0]["chatflow_id"] == "flow-1"
    assert result[0]["chatflow_name"] == "Algebra 101"
    assert result[0]["message_count"] == 3


@pytest.mark.asyncio
async def test_admin_get_user_sessions_returns_null_chatflow_name_when_missing():
    from app.api.admin import admin_get_user_sessions

    session = SimpleNamespace(
        session_id="session-2",
        user_id="user-2",
        chatflow_id="missing-flow",
        topic=None,
        is_active=True,
        created_at=None,
        last_activity_at=None,
    )

    mock_session_model = SimpleNamespace(
        user_id="user_id",
        created_at=1,
        find=lambda *args, **kwargs: _FakeChatSessionQuery([session]),
    )
    mock_message_model = SimpleNamespace(
        session_id="session_id",
        find=lambda *args, **kwargs: SimpleNamespace(count=AsyncMock(return_value=0)),
    )

    with patch("app.models.chat_session.ChatSession", mock_session_model), \
         patch("app.models.chat_message.ChatMessage", mock_message_model), \
         patch("app.api.admin.Chatflow.find", return_value=_FakeChatflowQuery([])):
        result = await admin_get_user_sessions("user-2", current_user={"role": "admin"})

    assert len(result) == 1
    assert result[0]["chatflow_id"] == "missing-flow"
    assert result[0]["chatflow_name"] is None