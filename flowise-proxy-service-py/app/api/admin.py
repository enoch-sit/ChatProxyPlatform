from fastapi import APIRouter, HTTPException, Depends, Query
from typing import List, Dict, Optional, Any
from app.auth.middleware import require_admin_role
from app.models.chatflow import Chatflow
from app.services.chatflow_service import ChatflowService
from app.services.flowise_service import FlowiseService
from app.core.logging import logger
from app.config import settings
from pydantic import BaseModel
import httpx
import traceback

# Import all request/response schemas from the new central location
from app.schemas import (
    ChatflowSyncResult, ChatflowStats, ChatflowResponse, UserAssignmentResponse,
    BulkUserAssignmentResponse, ChatflowUserResponse, AddUsersByEmailRequest,
    UserAuditResult, UserCleanupRequest, UserCleanupResult, SyncUserByEmailRequest,
    SyncUserResponse, AddUserToChatflowRequest
)

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

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

# =================================================================================
# Endpoints Restored and Refactored
# =================================================================================

@router.post("/chatflows/sync", response_model=ChatflowSyncResult)
async def sync_chatflows_from_flowise(
    chatflow_service: ChatflowService = Depends(get_chatflow_service),
    current_user: Dict = Depends(require_admin_role)
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
    current_user: Dict = Depends(require_admin_role)
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
    current_user: Dict = Depends(require_admin_role)
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
    current_user: Dict = Depends(require_admin_role),
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
    current_user: Dict = Depends(require_admin_role),
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
    current_user: Dict = Depends(require_admin_role),
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
    current_user: Dict = Depends(require_admin_role)
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
    current_user: Dict = Depends(require_admin_role),
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
    current_user: Dict = Depends(require_admin_role),
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
    current_user: Dict = Depends(require_admin_role),
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
    current_user: Dict = Depends(require_admin_role),
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
    request: AddUsersByEmailRequest,
    current_user: Dict = Depends(require_admin_role),
    chatflow_service: ChatflowService = Depends(get_chatflow_service)
):
    """
    Bulk add users to a chatflow by email (Admin only).
    """
    try:
        return await chatflow_service.add_users_to_chatflow_by_email(
            emails=request.emails,
            flowise_id=flowise_id,
            admin_user=current_user
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in bulk add users to chatflow {flowise_id}: {e}")
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
    skipVerification: Optional[bool] = False


class BatchCreateUsersRequest(BaseModel):
    users: List[Dict[str, Any]]
    skipVerification: Optional[bool] = False


class AllocateCreditsRequest(BaseModel):
    userId: str
    credits: int
    expiryDays: Optional[int] = None


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
    current_user: Dict = Depends(require_admin_role)
):
    """List all users (proxy → auth-service GET /api/admin/users)."""
    return await _proxy("GET", f"{AUTH_URL}/api/admin/users", _admin_headers(current_user))


@router.get("/users/{user_id}")
async def admin_get_user(
    user_id: str,
    current_user: Dict = Depends(require_admin_role)
):
    """Get a user by ID (proxy → auth-service GET /api/admin/users/:id)."""
    return await _proxy("GET", f"{AUTH_URL}/api/admin/users/{user_id}", _admin_headers(current_user))


@router.post("/users")
async def admin_create_user(
    request: CreateUserRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Create a single user (proxy → auth-service POST /api/admin/users)."""
    return await _proxy("POST", f"{AUTH_URL}/api/admin/users", _admin_headers(current_user), request.dict())


@router.post("/users/batch")
async def admin_create_users_batch(
    request: BatchCreateUsersRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Batch create users (proxy → auth-service POST /api/admin/users/batch)."""
    return await _proxy("POST", f"{AUTH_URL}/api/admin/users/batch", _admin_headers(current_user), request.dict())


@router.post("/users/{user_id}/verify")
async def admin_verify_user(
    user_id: str,
    current_user: Dict = Depends(require_admin_role)
):
    """Directly verify a user's email (proxy → auth-service POST /api/admin/users/:id/verify)."""
    return await _proxy("POST", f"{AUTH_URL}/api/admin/users/{user_id}/verify", _admin_headers(current_user))


@router.delete("/users/{user_id}")
async def admin_delete_user(
    user_id: str,
    current_user: Dict = Depends(require_admin_role)
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


# =================================================================================
# Admin Credit Management Routes (proxy → accounting-service)
# =================================================================================

@router.get("/credits")
async def admin_list_all_credits(
    current_user: Dict = Depends(require_admin_role)
):
    """List all credit allocations (proxy → accounting-service GET /api/credits/allocations/all)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/credits/allocations/all", _admin_headers(current_user))


@router.get("/credits/balance/{user_id}")
async def admin_get_user_credit_balance(
    user_id: str,
    current_user: Dict = Depends(require_admin_role)
):
    """Get a user's credit balance (proxy → accounting-service GET /api/credits/balance/:userId)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/credits/balance/{user_id}", _admin_headers(current_user))


@router.post("/credits/allocate")
async def admin_allocate_credits(
    request: AllocateCreditsRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Allocate credits to a user (proxy → accounting-service POST /api/credits/allocate)."""
    return await _proxy("POST", f"{ACCOUNTING_URL}/api/credits/allocate", _admin_headers(current_user), request.dict())


@router.post("/credits/set")
async def admin_set_credits(
    request: SetCreditsRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Set absolute credit balance (proxy → accounting-service POST /api/credits/set)."""
    return await _proxy("POST", f"{ACCOUNTING_URL}/api/credits/set", _admin_headers(current_user), request.dict())


@router.delete("/credits/remove")
async def admin_remove_credits(
    request: RemoveCreditsRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Remove all credits from a user (proxy → accounting-service DELETE /api/credits/remove)."""
    return await _proxy("DELETE", f"{ACCOUNTING_URL}/api/credits/remove", _admin_headers(current_user), request.dict())


@router.put("/credits/adjust")
async def admin_adjust_credits(
    request: AdjustCreditsRequest,
    current_user: Dict = Depends(require_admin_role)
):
    """Adjust credits for a user (proxy → accounting-service PUT /api/credits/adjust)."""
    return await _proxy("PUT", f"{ACCOUNTING_URL}/api/credits/adjust", _admin_headers(current_user), request.dict())


# =================================================================================
# Admin Usage / Token Stats Routes (proxy → accounting-service)
# =================================================================================

@router.get("/usage/system-stats")
async def admin_get_system_stats(
    current_user: Dict = Depends(require_admin_role)
):
    """Get system-wide usage stats (proxy → accounting-service GET /api/usage/system-stats)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/usage/system-stats", _admin_headers(current_user))


@router.get("/usage/stats/{user_id}")
async def admin_get_user_stats(
    user_id: str,
    current_user: Dict = Depends(require_admin_role)
):
    """Get per-user usage stats (proxy → accounting-service GET /api/usage/stats/:userId)."""
    return await _proxy("GET", f"{ACCOUNTING_URL}/api/usage/stats/{user_id}", _admin_headers(current_user))

