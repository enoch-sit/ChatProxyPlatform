from fastapi import APIRouter, HTTPException, Depends, Query
from typing import List, Dict, Optional, Any
from app.auth.middleware import require_admin_role, require_elevated_role
from app.models.chatflow import Chatflow
from app.services.chatflow_service import ChatflowService
from app.services.flowise_service import FlowiseService
from app.core.logging import logger
from app.config import settings
from app.database import get_database
from app.models.file_upload import FileUpload as FileUploadModel
from pydantic import BaseModel
import httpx
import traceback
from datetime import datetime

# Import all request/response schemas from the new central location
from app.schemas import (
    ChatflowSyncResult, ChatflowStats, ChatflowResponse, UserAssignmentResponse,
    BulkUserAssignmentResponse, ChatflowUserResponse, AddUsersByEmailRequest, AddUsersByIdentifierRequest,
    UserAuditResult, UserCleanupRequest, UserCleanupResult, SyncUserByEmailRequest,
    SyncUserResponse, AddUserToChatflowRequest
)

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])


class UpdateFlowiseApiKeyRequest(BaseModel):
    api_key: str


class TestFlowiseApiKeyRequest(BaseModel):
    api_key: Optional[str] = None


class FlowiseApiKeyStatusResponse(BaseModel):
    configured: bool
    source: str
    masked_key: Optional[str] = None


class FlowiseApiKeyTestResponse(BaseModel):
    valid: bool
    status_code: Optional[int] = None
    message: str


def _mask_secret(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    if len(value) <= 8:
        return "*" * len(value)
    return f"{value[:4]}{'*' * (len(value) - 8)}{value[-4:]}"


async def _get_effective_flowise_api_key() -> tuple[Optional[str], str]:
    db = await get_database()
    if db is not None:
        doc = await db["runtime_settings"].find_one({"_id": "flowise_proxy"})
        runtime_key = (doc or {}).get("flowise_api_key")
        if runtime_key:
            return runtime_key, "runtime"
    if settings.FLOWISE_API_KEY:
        return settings.FLOWISE_API_KEY, "env"
    return None, "unset"

# This dependency injection function remains unchanged as it's a solid pattern.
async def get_chatflow_service() -> ChatflowService:
    from app.database import database, connect_to_mongo
    from app.services.external_auth_service import ExternalAuthService
    
    if database.database is None:
        logger.warning("Database not connected in admin endpoint, attempting to connect...")
        try:
            await connect_to_mongo()
        except Exception as e:
            logger.error(f"Failed to connect to database: {e}")
            raise HTTPException(status_code=500, detail="Failed to connect to database")
    
    if database.database is None:
        raise HTTPException(status_code=500, detail="Database not connected")
    
    flowise_service = FlowiseService()
    external_auth_service = ExternalAuthService()
    # Pass all required services to the ChatflowService constructor
    return ChatflowService(db=database.database, flowise_service=flowise_service, external_auth_service=external_auth_service)


@router.get("/settings/flowise-api-key", response_model=FlowiseApiKeyStatusResponse)
async def get_flowise_api_key_status(current_user: Dict = Depends(require_admin_role)):
    """Return Flowise API key status and source without exposing the raw secret."""
    api_key, source = await _get_effective_flowise_api_key()
    return FlowiseApiKeyStatusResponse(
        configured=bool(api_key),
        source=source,
        masked_key=_mask_secret(api_key),
    )


@router.post("/settings/flowise-api-key")
async def update_flowise_api_key(
    request: UpdateFlowiseApiKeyRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Update Flowise API key at runtime (persisted in Mongo runtime settings)."""
    new_key = request.api_key.strip()
    if not new_key:
        raise HTTPException(status_code=400, detail="api_key must not be empty")

    db = await get_database()
    if db is None:
        raise HTTPException(status_code=500, detail="Database not connected")

    await db["runtime_settings"].update_one(
        {"_id": "flowise_proxy"},
        {
            "$set": {
                "flowise_api_key": new_key,
                "updated_by": current_user.get("email", "unknown"),
                "updated_at": datetime.utcnow(),
            }
        },
        upsert=True,
    )

    logger.info(f"Flowise API key updated by admin {current_user.get('email', 'unknown')}")
    return {"message": "Flowise API key updated successfully", "source": "runtime"}


@router.post("/settings/flowise-api-key/test", response_model=FlowiseApiKeyTestResponse)
async def test_flowise_api_key(
    request: TestFlowiseApiKeyRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Validate provided (or effective) Flowise API key against Flowise chatflows endpoint."""
    key_to_test = request.api_key.strip() if request.api_key else None
    if not key_to_test:
        key_to_test, _ = await _get_effective_flowise_api_key()
    if not key_to_test:
        raise HTTPException(status_code=400, detail="No Flowise API key configured")

    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {key_to_test}"}
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{settings.FLOWISE_API_URL}/api/v1/chatflows",
                headers=headers,
                timeout=10,
            )

        if response.status_code == 200:
            return FlowiseApiKeyTestResponse(valid=True, status_code=200, message="Flowise API key is valid")

        return FlowiseApiKeyTestResponse(
            valid=False,
            status_code=response.status_code,
            message=f"Flowise returned status {response.status_code}",
        )
    except Exception as e:
        logger.warning(f"Flowise API key test failed for admin {current_user.get('email', 'unknown')}: {e}")
        return FlowiseApiKeyTestResponse(valid=False, status_code=None, message=f"Flowise connectivity error: {e}")

# =================================================================================
# Endpoints Restored and Refactored
# =================================================================================

@router.post("/chatflows/sync", response_model=ChatflowSyncResult)
async def sync_chatflows_from_flowise(
    chatflow_service: ChatflowService = Depends(get_chatflow_service),
    current_user: Dict = Depends(require_elevated_role)
):
    """
    Synchronize chatflows from Flowise API to local database.
    This endpoint is tested by test_sync_chatflows.
    The logic is delegated to the service layer, preserving the API contract.
    """
    logger.info(f"Admin {current_user['email']} initiated chatflow sync")
    try:
        return await chatflow_service.sync_chatflows_from_flowise()
    except Exception as e:
        logger.error(f"Chatflow sync failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Chatflow synchronization failed.")

@router.get("/chatflows", response_model=List[Chatflow])
async def list_all_chatflows(
    include_deleted: bool = False,
    chatflow_service: ChatflowService = Depends(get_chatflow_service),
    current_user: Dict = Depends(require_elevated_role)
):
    """
    List all chatflows. Tested by test_list_chatflows.
    Delegates directly to the service layer.
    """
    try:
        return await chatflow_service.list_chatflows(include_deleted=include_deleted)
    except Exception as e:
        logger.error(f"Failed to list chatflows: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to retrieve chatflows.")

@router.get("/chatflows/stats")
async def get_chatflow_stats(
    chatflow_service: ChatflowService = Depends(get_chatflow_service),
    current_user: Dict = Depends(require_elevated_role)
):
    """
    Get chatflow statistics. Tested by test_chatflow_stats.
    Delegates directly to the service layer.
    """
    try:
        return await chatflow_service.get_chatflow_stats()
    except Exception as e:
        logger.error(f"Failed to get chatflow stats: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to retrieve chatflow statistics.")

@router.post("/chatflows/add-users-by-email", response_model=BulkUserAssignmentResponse)
async def add_users_to_chatflow_by_email(
    request: AddUsersByEmailRequest,
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Add multiple users to a chatflow by email. Tested by test_bulk_add_users_to_chatflow.
    The request body uses a schema from schemas.py. The logic is in the service.
    """
    try:
        return await chatflow_service.add_users_to_chatflow_by_email(
            emails=request.emails,
            flowise_id=request.chatflow_id,
            admin_user=current_user
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in bulk add users by email for chatflow {request.chatflow_id}: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.get("/chatflows/audit-users", response_model=UserAuditResult)
async def audit_user_chatflow_assignments(
    chatflow_id: Optional[str] = Query(None, description="Limit audit to a specific chatflow ID"),
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Audit user assignments. Tested by quickUserAudit.py.
    Delegates to the service layer.
    """
    try:
        admin_token = current_user.get("access_token")
        return await chatflow_service.audit_user_assignments(admin_token, chatflow_id)
    except Exception as e:
        logger.error(f"Error during user audit: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Audit failed: {str(e)}")

@router.post("/chatflows/cleanup-users", response_model=UserCleanupResult)
async def cleanup_user_chatflow_assignments(
    request: UserCleanupRequest,
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Cleanup user assignments. Tested by quickUserAudit.py.
    Request/response models are from schemas.py. Logic is in the service.
    """
    try:
        admin_token = current_user.get("access_token")
        return await chatflow_service.cleanup_user_assignments(
            admin_token=admin_token,
            action=request.action,
            dry_run=request.dry_run,
            chatflow_ids=request.chatflow_ids
        )
    except Exception as e:
        logger.error(f"Error during user cleanup: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Cleanup failed: {str(e)}")

@router.get("/chatflows/{flowise_id}", response_model=Chatflow)
async def get_chatflow_by_id(
    flowise_id: str,
    chatflow_service: ChatflowService = Depends(get_chatflow_service),
    current_user: Dict = Depends(require_elevated_role)
):
    """
    Get a specific chatflow. Tested by test_get_specific_chatflow.
    Delegates to the service layer.
    """
    try:
        chatflow = await chatflow_service.get_chatflow_by_flowise_id(flowise_id)
        if not chatflow:
            raise HTTPException(status_code=404, detail="Chatflow not found")
        return chatflow
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get chatflow {flowise_id}: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to retrieve chatflow.")

@router.get("/chatflows/{flowise_id}/users", response_model=List[ChatflowUserResponse])
async def list_chatflow_users(
    flowise_id: str,
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    List users for a chatflow. Tested by test_list_chatflow_users.
    Delegates to the service layer.
    """
    try:
        return await chatflow_service.list_users_for_chatflow(flowise_id)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error listing users for chatflow {flowise_id}: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.post("/chatflows/{flowise_id}/users", response_model=UserAssignmentResponse)
async def add_user_to_chatflow(
    flowise_id: str,
    request: AddUserToChatflowRequest,
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Assigns a user to a specific chatflow, granting them access.
    The user must already exist in the local database (synced from external auth).
    """
    try:
        # Corrected to call the right service method with the correct parameters
        result = await chatflow_service.add_user_to_chatflow_by_email(
            flowise_id=flowise_id,
            email=request.email,
            admin_user=current_user
        )
        # Ensure the chatflow is deployed and active after assignment
        await Chatflow.find_one(Chatflow.flowise_id == flowise_id).update(
            {"$set": {"sync_status": "active", "deployed": True}}
        )
        return result
    except HTTPException:
        # Re-raise HTTPExceptions from the service layer directly
        raise
    except Exception as e:
        # Handle potential duplicate key errors from the database
        if "duplicate key" in str(e).lower():
            raise HTTPException(status_code=409, detail=f"User with email '{request.email}' is already assigned to this chatflow.")
        logger.error(f"Error adding user {request.email} to chatflow {flowise_id}: {e}")
        raise HTTPException(status_code=500, detail="An unexpected error occurred.")


@router.delete("/chatflows/{flowise_id}/users", status_code=200)
async def remove_user_from_chatflow(
    flowise_id: str,
    email: str,
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Remove a user from a chatflow. Tested by test_remove_user_from_chatflow.
    Delegates to the service layer.
    """
    try:
        return await chatflow_service.remove_user_from_chatflow_by_email(
            email=email,
            flowise_id=flowise_id,
            admin_user=current_user
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error removing user with email {email} from chatflow {flowise_id}: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.post("/users/sync-by-email", response_model=SyncUserResponse)
async def sync_user_from_external_by_email(
    request: SyncUserByEmailRequest,
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Synchronize a user from external auth. Tested by test_sync_users_by_email.
    Delegates to the service layer.
    """
    admin_token = current_user.get("access_token")
    if not admin_token:
        raise HTTPException(status_code=500, detail="Admin context is missing required token.")
    
    try:
        return await chatflow_service.sync_user_by_email(request.email, admin_token)
    except Exception as e:
        logger.error(f"Error during user sync for email {request.email}: {str(e)}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"An unexpected error occurred: {str(e)}")

@router.post("/chatflows/{flowise_id}/users/bulk-add", response_model=BulkUserAssignmentResponse)
async def bulk_add_users_to_chatflow(
    flowise_id: str,
    request: AddUsersByIdentifierRequest,
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Bulk add users to a chatflow by username or email (Admin only).
    """
    try:
        return await chatflow_service.add_users_to_chatflow_by_identifier(
            identifiers=request.resolved_identifiers(),
            flowise_id=flowise_id,
            admin_user=current_user
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in bulk add users to chatflow {flowise_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@router.post("/chatflows/{flowise_id}/users/bulk-remove", response_model=BulkUserAssignmentResponse)
async def bulk_remove_users_from_chatflow(
    flowise_id: str,
    request: AddUsersByIdentifierRequest,
    current_user: Dict = Depends(require_elevated_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Bulk remove users from a chatflow by username or email.
    """
    try:
        return await chatflow_service.remove_users_from_chatflow_by_identifier(
            identifiers=request.resolved_identifiers(),
            flowise_id=flowise_id,
            admin_user=current_user
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in bulk remove users from chatflow {flowise_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


# =================================================================================
# Helper: forward a request to auth-service or accounting-service
# =================================================================================

AUTH_URL = settings.EXTERNAL_AUTH_URL.rstrip("/")
ACCOUNTING_URL = settings.ACCOUNTING_SERVICE_URL.rstrip("/")
PROXY_TIMEOUT = 15


def _admin_headers(current_user: Dict) -> Dict[str, str]:
    """Build Authorization header using the admin's token from the validated JWT context."""
    token = current_user.get("access_token", "")
    return {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Authorization": f"Bearer {token}",
    }


async def _proxy(method: str, url: str, headers: Dict, body: Any = None) -> Any:
    """Generic httpx proxy helper. Raises HTTPException on non-2xx."""
    try:
        async with httpx.AsyncClient(timeout=PROXY_TIMEOUT) as client:
            resp = await client.request(method, url, headers=headers, json=body)
        if resp.status_code >= 400:
            try:
                detail = resp.json()
            except Exception:
                detail = resp.text
            raise HTTPException(status_code=resp.status_code, detail=detail)
        return resp.json()
    except HTTPException:
        raise
    except httpx.ConnectError:
        raise HTTPException(status_code=503, detail="Upstream service unavailable")
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Upstream service timed out")
    except Exception as e:
        logger.error(f"Proxy error: {e}")
        raise HTTPException(status_code=500, detail=f"Proxy error: {str(e)}")


# =================================================================================
# Request body schemas for user/credit management
# =================================================================================

class CreateUserRequest(BaseModel):
    username: str
    email: str
    password: str
    role: Optional[str] = "user"
    skipVerification: Optional[bool] = True


class BatchCreateUsersRequest(BaseModel):
    users: List[Dict[str, Any]]
    skipVerification: Optional[bool] = True


class BatchUpdateRolesRequest(BaseModel):
    updates: List[Dict[str, Any]]


class AllocateCreditsRequest(BaseModel):
    userId: str
    credits: int
    expiryDays: Optional[int] = None


class AllocateCreditsBatchItem(BaseModel):
    userId: str
    credits: int
    expiryDays: Optional[int] = None
    notes: Optional[str] = None


class AllocateCreditsBatchRequest(BaseModel):
    allocations: List[AllocateCreditsBatchItem]


class SetCreditsRequest(BaseModel):
    userId: str
    credits: int


class RemoveCreditsRequest(BaseModel):
    userId: str


class AdjustCreditsRequest(BaseModel):
    userId: str
    adjustment: int
    reason: Optional[str] = None


# =================================================================================
# Admin User Management Routes (proxy → auth-service)
# =================================================================================

@router.get("/users")
async def admin_list_users(
    current_user: Dict = Depends(require_elevated_role)
):
    """List all users (proxy → auth-service GET /api/admin/users)."""
    return await _proxy("GET", f"{AUTH_URL}/api/admin/users", _admin_headers(current_user))


@router.get("/users/{user_id}")
async def admin_get_user(
    user_id: str,
    current_user: Dict = Depends(require_elevated_role)
):
    """Get a user by ID (proxy → auth-service GET /api/admin/users/:id)."""
    return await _proxy("GET", f"{AUTH_URL}/api/admin/users/{user_id}", _admin_headers(current_user))


@router.post("/users")
async def admin_create_user(
    request: CreateUserRequest,
    current_user: Dict = Depends(require_elevated_role)
):
    """Create a single user (proxy → auth-service POST /api/admin/users)."""
    return await _proxy("POST", f"{AUTH_URL}/api/admin/users", _admin_headers(current_user), request.dict())


@router.post("/users/batch")
async def admin_create_users_batch(
    request: BatchCreateUsersRequest,
    current_user: Dict = Depends(require_elevated_role)
):
    """Batch create users (proxy → auth-service POST /api/admin/users/batch)."""
    payload = request.dict()
    return await _proxy("POST", f"{AUTH_URL}/api/admin/users/batch", _admin_headers(current_user), payload)


@router.post("/users/{user_id}/verify")
async def admin_verify_user(
    user_id: str,
    current_user: Dict = Depends(require_elevated_role)
):
    """Directly verify a user's email (proxy → auth-service POST /api/admin/users/:id/verify)."""
    return await _proxy("POST", f"{AUTH_URL}/api/admin/users/{user_id}/verify", _admin_headers(current_user))


@router.delete("/users/{user_id}")
async def admin_delete_user(
    user_id: str,
    current_user: Dict = Depends(require_elevated_role)
):
    """Delete a user (proxy → auth-service DELETE /api/admin/users/:id)."""
    return await _proxy("DELETE", f"{AUTH_URL}/api/admin/users/{user_id}", _admin_headers(current_user))


@router.put("/users/{user_id}/role")
async def admin_update_user_role(
    user_id: str,
    body: Dict[str, Any],
    current_user: Dict = Depends(require_admin_role)
):
    """Update user role (proxy → auth-service PUT /api/admin/users/:id/role)."""
    return await _proxy("PUT", f"{AUTH_URL}/api/admin/users/{user_id}/role", _admin_headers(current_user), body)


@router.put("/users/roles/batch")
async def admin_update_user_roles_batch(
    request: BatchUpdateRolesRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Batch update user roles (proxy → auth-service PUT /api/admin/users/roles/batch)."""
    return await _proxy("PUT", f"{AUTH_URL}/api/admin/users/roles/batch", _admin_headers(current_user), request.dict())


# =================================================================================
# Admin Credit Management Routes (proxy → accounting-service)
# =================================================================================

@router.get("/credits")
async def admin_list_all_credits(
    current_user: Dict = Depends(require_elevated_role)
):
    """List all credit allocations (proxy → accounting-service GET /api/credits/allocations/all)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/credits/allocations/all", _admin_headers(current_user))


@router.get("/credits/current-balances")
async def admin_list_current_credit_balances(
    current_user: Dict = Depends(require_elevated_role)
):
    """List current non-expired credit totals by user (proxy → accounting-service GET /api/credits/current-balances)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/credits/current-balances", _admin_headers(current_user))


@router.get("/credits/users-directory")
async def admin_list_users_directory(
    current_user: Dict = Depends(require_elevated_role)
):
    """List ALL user accounts joined with their current credit balance, including
    zero-balance users (proxy → accounting-service GET /api/credits/users-directory)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/credits/users-directory", _admin_headers(current_user))


@router.get("/credits/balance/{user_id}")
async def admin_get_user_credit_balance(
    user_id: str,
    current_user: Dict = Depends(require_elevated_role)
):
    """Get a user's credit balance (proxy → accounting-service GET /api/credits/balance/:userId)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/credits/balance/{user_id}", _admin_headers(current_user))


@router.post("/credits/allocate")
async def admin_allocate_credits(
    request: AllocateCreditsRequest,
    current_user: Dict = Depends(require_elevated_role)
):
    """Allocate credits to a user (proxy → accounting-service POST /api/credits/allocate)."""
    # Use exclude_none=True so that optional fields like expiryDays are omitted when not
    # provided. Sending null would override the TypeScript default (30 days) in the
    # accounting-service, causing credits to expire immediately.
    return await _proxy("POST", f"{ACCOUNTING_URL}/api/credits/allocate", _admin_headers(current_user), request.dict(exclude_none=True))


@router.post("/credits/allocate-batch")
async def admin_allocate_credits_batch(
    request: AllocateCreditsBatchRequest,
    current_user: Dict = Depends(require_elevated_role)
):
    """Batch-allocate credits (proxy → accounting-service POST /api/credits/allocate-batch)."""
    payload = {"allocations": [item.dict(exclude_none=True) for item in request.allocations]}
    return await _proxy("POST", f"{ACCOUNTING_URL}/api/credits/allocate-batch", _admin_headers(current_user), payload)


@router.post("/credits/set")
async def admin_set_credits(
    request: SetCreditsRequest,
    current_user: Dict = Depends(require_elevated_role)
):
    """Set absolute credit balance (proxy → accounting-service POST /api/credits/set)."""
    return await _proxy("POST", f"{ACCOUNTING_URL}/api/credits/set", _admin_headers(current_user), request.dict())


@router.delete("/credits/remove")
async def admin_remove_credits(
    request: RemoveCreditsRequest,
    current_user: Dict = Depends(require_elevated_role)
):
    """Remove all credits from a user (proxy → accounting-service DELETE /api/credits/remove)."""
    return await _proxy("DELETE", f"{ACCOUNTING_URL}/api/credits/remove", _admin_headers(current_user), request.dict())


@router.put("/credits/adjust")
async def admin_adjust_credits(
    request: AdjustCreditsRequest,
    current_user: Dict = Depends(require_elevated_role)
):
    """Adjust credits for a user (proxy → accounting-service PUT /api/credits/adjust)."""
    return await _proxy("PUT", f"{ACCOUNTING_URL}/api/credits/adjust", _admin_headers(current_user), request.dict(exclude_none=True))


# =================================================================================
# Admin Usage / Token Stats Routes (proxy → accounting-service)
# =================================================================================

@router.get("/usage/system-stats")
async def admin_get_system_stats(
    current_user: Dict = Depends(require_elevated_role)
):
    """Get system-wide usage stats (proxy → accounting-service GET /api/usage/system-stats)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/usage/system-stats", _admin_headers(current_user))


@router.get("/usage/stats/{user_id}")
async def admin_get_user_stats(
    user_id: str,
    current_user: Dict = Depends(require_elevated_role)
):
    """Get per-user usage stats (proxy → accounting-service GET /api/usage/stats/:userId)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/usage/stats/{user_id}", _admin_headers(current_user))


# ==================================================================================
# Admin Password Reset (proxied to auth-service)
# ==================================================================================

class ResetPasswordRequest(BaseModel):
    newPassword: str


@router.put("/users/{user_id}/password")
async def admin_reset_user_password(
    user_id: str,
    request: ResetPasswordRequest,
    current_user: Dict = Depends(require_elevated_role)
):
    """Admin/teacher password reset (proxy → auth-service PUT /api/admin/users/:id/password)."""
    return await _proxy("PUT", f"{AUTH_URL}/api/admin/users/{user_id}/password", _admin_headers(current_user), request.dict())


# ==================================================================================
# Admin Chat History Routes (direct access to flowise-proxy MongoDB)
# ==================================================================================

@router.get("/chat/users")
async def admin_list_users_with_sessions(
    current_user: Dict = Depends(require_elevated_role)
):
    """
    List all users that have chat sessions.
    Returns user records from the local User collection enriched with session count.
    """
    from app.models.user import User as LocalUser
    from app.models.chat_session import ChatSession
    try:
        # Get all users from local DB
        users = await LocalUser.find({}).to_list()
        # Get session counts per user
        session_counts: Dict[str, int] = {}
        sessions = await ChatSession.find({}).to_list()
        for s in sessions:
            session_counts[s.user_id] = session_counts.get(s.user_id, 0) + 1

        result = []
        for u in users:
            uid = str(u.external_id)
            result.append({
                "user_id": uid,
                "username": u.username,
                "email": u.email,
                "role": u.role,
                "session_count": session_counts.get(uid, 0),
                "last_active": None,
            })
        # Sort by session count desc
        result.sort(key=lambda x: x["session_count"], reverse=True)
        return result
    except Exception as e:
        logger.error(f"Failed to list users with sessions: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to list users: {str(e)}")


@router.get("/chat/users/{user_id}/sessions")
async def admin_get_user_sessions(
    user_id: str,
    current_user: Dict = Depends(require_elevated_role)
):
    """
    Get all chat sessions for a specific user (admin/teacher access).
    """
    from app.models.chat_session import ChatSession
    from app.models.chat_message import ChatMessage
    try:
        sessions = await ChatSession.find(
            ChatSession.user_id == user_id
        ).sort(-ChatSession.created_at).to_list()

        chatflow_ids = list({s.chatflow_id for s in sessions if s.chatflow_id})
        chatflow_names: Dict[str, str] = {}
        if chatflow_ids:
            chatflows = await Chatflow.find({"flowise_id": {"$in": chatflow_ids}}).to_list()
            chatflow_names = {
                chatflow.flowise_id: chatflow.name
                for chatflow in chatflows
                if chatflow.flowise_id and chatflow.name
            }

        result = []
        for s in sessions:
            msg_count = await ChatMessage.find(
                ChatMessage.session_id == s.session_id
            ).count()
            result.append({
                "session_id": s.session_id,
                "chatflow_id": s.chatflow_id,
                "chatflow_name": chatflow_names.get(s.chatflow_id),
                "topic": s.topic,
                "is_active": s.is_active,
                "created_at": s.created_at.isoformat() if s.created_at else None,
                "last_activity_at": s.last_activity_at.isoformat() if s.last_activity_at else None,
                "message_count": msg_count,
            })
        return result
    except Exception as e:
        logger.error(f"Failed to get sessions for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get sessions: {str(e)}")


@router.get("/chat/users/{user_id}/sessions/{session_id}/history")
async def admin_get_user_session_history(
    user_id: str,
    session_id: str,
    current_user: Dict = Depends(require_elevated_role)
):
    """
    Get ordered chat history for a specific user's session for elevated roles.
    """
    from app.models.chat_message import ChatMessage
    from app.models.chat_session import ChatSession

    try:
        session = await ChatSession.find_one(
            ChatSession.session_id == session_id,
            ChatSession.user_id == user_id,
        )
        if not session:
            raise HTTPException(status_code=404, detail="Chat session not found")

        messages = (
            await ChatMessage.find(ChatMessage.session_id == session_id)
            .sort(ChatMessage.created_at)
            .to_list()
        )

        history_list = []
        for msg in messages:
            message_data = {
                "id": str(msg.id),
                "role": msg.role,
                "content": msg.content,
                "created_at": msg.created_at,
                "session_id": session_id,
                "file_ids": msg.file_ids,
                "has_files": msg.has_files,
                "uploads": [],
            }

            if msg.has_files and msg.file_ids:
                try:
                    file_records = await FileUploadModel.find(
                        {"file_id": {"$in": msg.file_ids}, "user_id": user_id}
                    ).to_list()

                    for file_record in file_records:
                        message_data["uploads"].append({
                            "file_id": file_record.file_id,
                            "name": file_record.original_name,
                            "mime": file_record.mime_type,
                            "size": file_record.file_size,
                            "uploaded_at": file_record.created_at,
                            "is_image": file_record.mime_type.startswith("image/") if file_record.mime_type else False,
                        })
                except Exception as file_error:
                    logger.warning(
                        "Failed to load file metadata for admin history %s/%s: %s",
                        user_id,
                        session_id,
                        file_error,
                    )

            history_list.append(message_data)

        return {"history": history_list, "count": len(history_list)}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get session history for user {user_id}, session {session_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get session history: {str(e)}")

