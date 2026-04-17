from fastapi import APIRouter, Depends, HTTPException
from typing import List, Dict, Optional
from app.auth.middleware import authenticate_user, ELEVATED_ROLES
from app.services.flowise_service import FlowiseService
from app.services.auth_service import AuthService
from app.models.chatflow import UserChatflow, Chatflow
from app.models.user import User
from app.core.logging import logger
from beanie.operators import In
from bson import ObjectId

router = APIRouter(prefix="/api/v1/chatflows", tags=["chatflows"])

async def get_local_user_from_jwt(current_user: Dict) -> Optional[User]:
    """Helper function to get local user from JWT token data"""
    user_email = current_user.get('email')
    external_user_id = current_user.get('sub') or current_user.get('external_id')
    
    # Find the local user by external_id or email
    local_user = None
    if external_user_id:
        local_user = await User.find_one(User.external_id == external_user_id)
    
    if not local_user and user_email:
        local_user = await User.find_one(User.email == user_email)
        
    return local_user

async def validate_user_chatflow_access(local_user_id: str, chatflow_id: str) -> bool:
    """Validate if user has access to specific chatflow using local user ID"""
    try:
        user_chatflow = await UserChatflow.find_one(
            UserChatflow.user_id == local_user_id,
            UserChatflow.chatflow_id == chatflow_id,
            UserChatflow.is_active == True
        )
        return user_chatflow is not None
    except Exception as e:
        logger.error(f"Error validating user chatflow access: {e}")
        return False

@router.get("", response_model=List[Dict])
async def list_chatflows(
    current_user: Dict = Depends(authenticate_user)
):
    """
    Get list of chatflows available to the current user.
    This endpoint filters chatflows based on user permissions.
    """
    try:
        user_role = current_user.get('role', '')

        # Elevated roles (admin/supervisor/teacher) see ALL active chatflows
        if user_role in ELEVATED_ROLES:
            chatflows = await Chatflow.find(
                Chatflow.sync_status != "deleted",
            ).to_list()
            logger.info(f"🔑 Elevated user {current_user.get('email')} ({user_role}): returning all {len(chatflows)} chatflows")
            return [
                {
                    "id": chatflow.flowise_id,
                    "name": chatflow.name,
                    "description": chatflow.description,
                    "is_public": chatflow.is_public
                }
                for chatflow in chatflows
            ]

        # Regular users: filter by their UserChatflow assignments
        local_user = await get_local_user_from_jwt(current_user)
        if not local_user:
            logger.warning(f"Could not find local user for JWT: {current_user.get('email')}")
            return []

        logger.info(f"🔍 Fetching chatflows for local_user_id: {local_user.id}")

        # Get user's active chatflow access records using the user's external_id
        user_chatflows = await UserChatflow.find(
            UserChatflow.external_user_id == local_user.external_id, # Use external_id from the local user object
            UserChatflow.is_active == True
        ).to_list()
        
        logger.info(f"🔍 Found {len(user_chatflows)} active chatflow assignments for user {local_user.email}")
        
        if not user_chatflows:
            return []
        
        # Extract chatflow IDs (these are flowise_ids)
        chatflow_ids = [ObjectId(uc.chatflow_id) for uc in user_chatflows]
        
        # Get chatflow details from local database
        chatflows = await Chatflow.find(
            In(Chatflow.id, chatflow_ids), # Match against the document's internal _id
            Chatflow.sync_status != "deleted",
        ).to_list()
        
        logger.info(f"🔍 Found {len(chatflows)} deployed chatflows matching user access")
        
        # Create response
        result = [
            {
                "id": chatflow.flowise_id,
                "name": chatflow.name,
                "description": chatflow.description,
                "is_public": chatflow.is_public
            }
            for chatflow in chatflows
        ]
        
        return result

    except Exception as e:
        logger.error(f"Error listing chatflows for user {current_user.get('email')}: {e}")
        raise HTTPException(status_code=500, detail="An error occurred while fetching chatflows.")

@router.get("/my-chatflows", response_model=List[Dict])
async def get_my_chatflows(
    current_user: Dict = Depends(authenticate_user)
):
    """
    Get list of chatflows accessible to the current user.
    This endpoint returns chatflows from the local database that the user has access to.
    """
    try:
        user_role = current_user.get('role', '')

        # Elevated roles (admin/supervisor/teacher) see ALL active chatflows
        if user_role in ELEVATED_ROLES:
            chatflows = await Chatflow.find(
                Chatflow.sync_status != "deleted",
            ).to_list()
            logger.info(f"🔑 Elevated user {current_user.get('email')} ({user_role}): returning all {len(chatflows)} chatflows")
            return [
                {
                    "id": chatflow.flowise_id,
                    "name": chatflow.name,
                    "description": chatflow.description,
                    "category": chatflow.category,
                    "type": chatflow.type,
                    "deployed": chatflow.deployed,
                    "assigned_at": None
                }
                for chatflow in chatflows
            ]

        # Regular users: filter by their UserChatflow assignments
        local_user = await get_local_user_from_jwt(current_user)
        
        if not local_user:
            logger.error(f"❌ Local user not found for JWT: {current_user}")
            return []
        
        local_user_id = str(local_user.id)
        logger.info(f"✅ My-chatflows: Found local user: {local_user.email} with local ID: {local_user_id}")
        
        # Get user's active chatflow access records using LOCAL user ID
        user_chatflows = await UserChatflow.find(
            UserChatflow.external_user_id == current_user["sub"],  # Use local MongoDB ObjectId as string
            UserChatflow.is_active == True
        ).to_list()
        
        if not user_chatflows:
            logger.info(f"No active chatflows found for user {local_user_id}")
            return []
        
        # Extract chatflow IDs (these are flowise_ids stored in chatflow_id field)
        chatflow_ids = [uc.chatflow_id for uc in user_chatflows]

        # Original (find nothing)
        # Get chatflow details from local database
        # chatflows = await Chatflow.find(
        #     In(Chatflow.flowise_id, chatflow_ids),
        #     Chatflow.sync_status != "deleted",  # Exclude deleted chatflows
        #     # Chatflow.deployed == True  # Only show deployed chatflows to users
        # ).to_list()

        # Throw error: 'ExpressionField' object is not callable
        # chatflows = await Chatflow.find(
        #     Chatflow.flowise_id.in_(chatflow_ids),
        #     Chatflow.sync_status != "deleted",  # Exclude deleted chatflows
        #     # Chatflow.deployed == True  # Only show deployed chatflows to users
        # ).to_list()

        object_ids = [ObjectId(cid) for cid in chatflow_ids if ObjectId.is_valid(cid)]

        chatflows = await Chatflow.find(
            In(Chatflow.id, object_ids),  # This works
            Chatflow.sync_status != "deleted",
        ).to_list()
        
        # Create response with user-friendly information
        result = []
        for chatflow in chatflows:
            # Find corresponding access record for additional info
            access_record = next(
                (uc for uc in user_chatflows if uc.chatflow_id == chatflow.flowise_id), 
                None
            )
            
            chatflow_dict = {
                "id": chatflow.flowise_id,
                "name": chatflow.name,
                "description": chatflow.description,
                "category": chatflow.category,
                "type": chatflow.type,
                "deployed": chatflow.deployed,
                "assigned_at": access_record.assigned_at.isoformat() if access_record and access_record.assigned_at else None
            }
            result.append(chatflow_dict)
        
        logger.info(f"✅ My-chatflows: Returning {len(result)} accessible chatflows for user {local_user.email}")
        return result
        
    except Exception as e:
        logger.error(f"Error getting chatflows for user {current_user.get('username', 'unknown')}: {e}")
        raise HTTPException(
            status_code=500, 
            detail="Internal server error while retrieving your chatflows"
        )


@router.get("/{chatflow_id}")
async def get_chatflow(
    chatflow_id: str,
    current_user: Dict = Depends(authenticate_user)
):
    """Get specific chatflow details if user has access"""
    try:
        user_role = current_user.get('role', '')

        # Elevated roles bypass per-chatflow access checks
        if user_role not in ELEVATED_ROLES:
            local_user = await get_local_user_from_jwt(current_user)
            if not local_user:
                raise HTTPException(status_code=404, detail="User not found")
            if not await validate_user_chatflow_access(str(local_user.id), chatflow_id):
                raise HTTPException(status_code=403, detail="Access denied to this chatflow")

        # Get chatflow details from local database first
        chatflow = await Chatflow.find_one(Chatflow.flowise_id == chatflow_id)
        
        if not chatflow:
            raise HTTPException(
                status_code=404,
                detail="Chatflow not found"
            )
        
        # Return chatflow details
        return {
            "id": chatflow.flowise_id,
            "name": chatflow.name,
            "description": chatflow.description,
            "category": chatflow.category,
            "type": chatflow.type,
            "deployed": chatflow.deployed,
            "created": chatflow.created.isoformat() if chatflow.created else None,
            "updated": chatflow.updated.isoformat() if chatflow.updated else None
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting chatflow {chatflow_id}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve chatflow: {str(e)}"
        )

@router.get("/{chatflow_id}/config")
async def get_chatflow_config(
    chatflow_id: str,
    current_user: Dict = Depends(authenticate_user)
):
    """Get chatflow configuration if user has access"""
    try:
        user_role = current_user.get('role', '')

        # Elevated roles bypass per-chatflow access checks
        if user_role not in ELEVATED_ROLES:
            local_user = await get_local_user_from_jwt(current_user)
            if not local_user:
                raise HTTPException(status_code=404, detail="User not found")
            if not await validate_user_chatflow_access(str(local_user.id), chatflow_id):
                raise HTTPException(status_code=403, detail="Access denied to this chatflow")

        # Get chatflow config from Flowise service
        flowise_service = FlowiseService()
        config = await flowise_service.get_chatflow_config(chatflow_id)
        
        if config is None:
            raise HTTPException(
                status_code=404,
                detail="Chatflow configuration not found"
            )
        
        return config
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting chatflow config {chatflow_id}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve chatflow config: {str(e)}"
        )

