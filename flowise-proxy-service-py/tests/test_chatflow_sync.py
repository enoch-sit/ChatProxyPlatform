"""
Integration-style tests for chatflow sync logic.

These tests mock the Flowise HTTP call and the Beanie ODM layer so they can
run without a live Flowise or MongoDB instance.  They exercise the three key
fixes:

1. FlowiseAPIError propagation (instead of returning None)
2. Empty-response guard (skip deletion when Flowise returns [])
3. Normal sync (create / update / delete)
"""

import pytest
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
from app.exceptions import FlowiseAPIError
from app.schemas import ChatflowSyncResult


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_flowise_chatflow(fid: str, name: str = "Test CF") -> dict:
    """Produce a minimal Flowise API chatflow dict."""
    return {
        "id": fid,
        "name": name,
        "description": "desc",
        "deployed": True,
        "isPublic": False,
        "category": None,
        "type": "CHATFLOW",
        "apikeyid": None,
        "flowData": "{}",
        "chatbotConfig": "{}",
        "apiConfig": "{}",
        "analytic": "{}",
        "speechToText": "{}",
        "createdDate": "2025-01-01T00:00:00Z",
        "updatedDate": "2025-01-01T00:00:00Z",
    }


def _make_mock_chatflow(flowise_id: str):
    """Create a mock Beanie Chatflow document."""
    cf = MagicMock()
    cf.flowise_id = flowise_id
    cf.update = AsyncMock()
    return cf


class _FakeFindQuery:
    """Minimal stand-in for Beanie FindMany that supports .update()."""

    def __init__(self, docs):
        self._docs = docs

    async def to_list(self):
        return self._docs

    def update(self, *args, **kwargs):
        return _async_noop()


async def _async_noop():
    return None


# ---------------------------------------------------------------------------
# Fixture: ChatflowService with mocks
# ---------------------------------------------------------------------------

@pytest.fixture
def service():
    """Build a ChatflowService with mocked dependencies."""
    from app.services.chatflow_service import ChatflowService

    db = MagicMock()
    flowise_service = MagicMock()
    flowise_service.list_chatflows = AsyncMock()
    external_auth_service = MagicMock()

    svc = ChatflowService(db, flowise_service, external_auth_service)
    return svc


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_sync_returns_error_on_flowise_api_failure(service):
    """When Flowise is unreachable, sync should return an error result
    without crashing or deleting anything."""

    service.flowise_service.list_chatflows.side_effect = FlowiseAPIError("connection refused")

    with patch("app.services.chatflow_service.Chatflow") as MockChatflow:
        # Should never reach Chatflow queries
        result: ChatflowSyncResult = await service.sync_chatflows_from_flowise()

    assert result.errors == 1
    assert result.total_fetched == 0
    assert result.created == 0
    assert result.deleted == 0
    assert any("flowise_api_error" in str(d) for d in result.error_details)


@pytest.mark.asyncio
async def test_sync_empty_response_skips_deletion(service):
    """When Flowise returns [] but local DB has chatflows, nothing should
    be deleted (the empty-response guard)."""

    service.flowise_service.list_chatflows.return_value = []

    existing = [_make_mock_chatflow("flow-1"), _make_mock_chatflow("flow-2")]

    with patch("app.services.chatflow_service.Chatflow") as MockChatflow:
        MockChatflow.find_all.return_value = _FakeFindQuery(existing)
        # find() should NOT be called for deletion
        MockChatflow.find.return_value = _FakeFindQuery([])

        result: ChatflowSyncResult = await service.sync_chatflows_from_flowise()

    assert result.total_fetched == 0
    assert result.deleted == 0
    # Should have a warning in error_details about empty response guard
    assert any("empty_response_guard" in str(d) for d in result.error_details)


@pytest.mark.asyncio
async def test_sync_creates_new_chatflows(service):
    """When Flowise returns a chatflow not in local DB, it should be created."""

    flowise_data = [_make_flowise_chatflow("flow-new")]
    service.flowise_service.list_chatflows.return_value = flowise_data

    with patch("app.services.chatflow_service.Chatflow") as MockChatflow:
        MockChatflow.find_all.return_value = _FakeFindQuery([])  # no existing

        new_instance = AsyncMock()
        new_instance.insert = AsyncMock()
        MockChatflow.return_value = new_instance

        result: ChatflowSyncResult = await service.sync_chatflows_from_flowise()

    assert result.total_fetched == 1
    assert result.created == 1
    assert result.updated == 0
    assert result.deleted == 0
    new_instance.insert.assert_awaited_once()


@pytest.mark.asyncio
async def test_sync_updates_existing_chatflows(service):
    """When Flowise returns a chatflow that already exists locally, it should
    be updated (not duplicated)."""

    flowise_data = [_make_flowise_chatflow("flow-existing", name="Updated Name")]
    service.flowise_service.list_chatflows.return_value = flowise_data

    existing_cf = _make_mock_chatflow("flow-existing")

    with patch("app.services.chatflow_service.Chatflow") as MockChatflow:
        MockChatflow.find_all.return_value = _FakeFindQuery([existing_cf])

        result: ChatflowSyncResult = await service.sync_chatflows_from_flowise()

    assert result.total_fetched == 1
    assert result.updated == 1
    assert result.created == 0
    existing_cf.update.assert_awaited_once()


@pytest.mark.asyncio
async def test_sync_deletes_removed_chatflows(service):
    """When a chatflow exists locally but is not in the Flowise response,
    it should be marked as deleted (and the response is non-empty so the
    guard does not trigger)."""

    # Flowise returns only flow-a
    flowise_data = [_make_flowise_chatflow("flow-a")]
    service.flowise_service.list_chatflows.return_value = flowise_data

    # Local DB has flow-a and flow-b
    existing = [_make_mock_chatflow("flow-a"), _make_mock_chatflow("flow-b")]

    with patch("app.services.chatflow_service.Chatflow") as MockChatflow:
        MockChatflow.find_all.return_value = _FakeFindQuery(existing)

        find_query = AsyncMock()
        find_query.update = AsyncMock()
        MockChatflow.find.return_value = find_query

        result: ChatflowSyncResult = await service.sync_chatflows_from_flowise()

    assert result.deleted == 1
    assert result.updated == 1  # flow-a was updated
    # Verify find() was called to mark flow-b as deleted
    MockChatflow.find.assert_called_once()


@pytest.mark.asyncio
async def test_flowise_api_error_has_status_code():
    """FlowiseAPIError should carry optional status_code."""
    err = FlowiseAPIError("bad gateway", status_code=502)
    assert err.status_code == 502
    assert "bad gateway" in str(err)

    err2 = FlowiseAPIError("timeout")
    assert err2.status_code is None
