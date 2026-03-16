from fastapi import HTTPException, Security, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Dict, Optional
from app.auth.jwt_handler import JWTHandler
from app.models.user import User
from app.models.chatflow import UserChatflow
from datetime import datetime
import logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

security = HTTPBearer()

ADMIN_ROLE = 'admin'
USER_ROLE = 'user' # This seems to be used as a general 'non-admin' identifier in some places
SUPERVISOR_ROLE = 'supervisor' # Added for the new function
TEACHER_ROLE = 'teacher'  # Teacher role - elevated privileges for managing students
ENDUSER_ROLE = 'enduser' # Assuming this is the most basic role

# Roles with elevated (admin-level) access
ELEVATED_ROLES = {ADMIN_ROLE, SUPERVISOR_ROLE, TEACHER_ROLE}

# Role hierarchy constants (optional, but good for clarity if you have more complex rules
#   ADMIN_ROLE = 'admin',        // Highest privilege level - full system access
#   SUPERVISOR_ROLE = 'supervisor', // Mid-level privilege - user management
#   ENDUSER_ROLE = 'enduser',    // Base level access - standard user operations
#   USER_ROLE = 'user' // Base level access - standard user operations

async def ensure_user_exists_locally(jwt_payload: Dict) -> None:
    """Ensure user from JWT token exists in local database"""
    try:
        external_user_id = jwt_payload.get("sub") or jwt_payload.get("user_id")
        email = jwt_payload.get("email")
        username = jwt_payload.get("username") or jwt_payload.get("name", email)
        role = jwt_payload.get("role", "enduser")
        
        if not external_user_id or not email:
            logger.warning(f"⚠️ Missing required user data in JWT: external_id={external_user_id}, email={email}")
            return
        
        # Check if user already exists locally
        existing_user = await User.find_one(User.external_id == external_user_id)
        
        if existing_user:
            # Update existing user if needed
            needs_update = False
            if existing_user.email != email:
                existing_user.email = email
                needs_update = True
            if existing_user.username != username:
                existing_user.username = username
                needs_update = True
            if existing_user.role != role:
                existing_user.role = role
                needs_update = True
                
            if needs_update:
                existing_user.updated_at = datetime.utcnow()
                await existing_user.save()
                logger.info(f"✅ Updated existing user: {email}")
        else:
            # Create new user
            new_user = User(
                external_id=external_user_id,
                username=username,
                email=email,
                role=role,
                is_active=True,
                credits=0,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow()
            )
            await new_user.save()
            logger.info(f"✅ Created new local user: {email} with external_id: {external_user_id}")
            
    except Exception as e:
        logger.error(f"❌ Error syncing user to local database: {e}")
        # Don't raise exception - authentication should still work even if sync fails

async def sync_external_user_to_local(jwt_payload: Dict) -> User:
    """
    Create local user record from external auth JWT payload.
    This maintains your admin-controlled security model:
    - Creates user record for authentication
    - NO chatflow access by default
    - Admin must explicitly assign chatflows
    """
    try:
        external_user_id = jwt_payload.get('sub') or jwt_payload.get('external_id')
        email = jwt_payload.get('email')
        username = jwt_payload.get('username') or jwt_payload.get('name', email)
        role = jwt_payload.get('role', 'enduser')
        
        # Create local user record with NO access by default
        new_user = User(
            external_id=external_user_id,
            username=username,
            email=email,
            role=role,
            is_active=True,
            credits=0,  # No credits by default - admin controls this
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow()
        )
        await new_user.save()
        
        logger.info(f"✅ Auto-created local user record for {email} (external_id: {external_user_id})")
        logger.info(f"   - User has NO chatflow access by default")
        logger.info(f"   - Admin must explicitly assign chatflows")
        
        return new_user
        
    except Exception as e:
        logger.error(f"❌ Error syncing external user to local: {e}")
        raise HTTPException(
            status_code=500,
            detail="Failed to create local user record"
        )

async def authenticate_user(credentials: HTTPAuthorizationCredentials = Security(security)) -> Dict:
    """Middleware to authenticate users based on JWT token with auto-sync and external validation"""
    
    try:
        token = credentials.credentials
        payload = JWTHandler.verify_access_token(token)
        
        if payload is None:
            raise HTTPException(
                status_code=401,
                detail="Invalid or expired token",
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        # Handle both old and new payload formats for backward compatibility
        user_id = payload.get("sub") or payload.get("user_id")
        
        if not user_id:
            raise HTTPException(
                status_code=401,
                detail="Invalid token payload - missing user ID",
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        # Normalize payload format
        normalized_payload = payload.copy()
        normalized_payload["user_id"] = user_id  # Ensure user_id is available for existing code
        normalized_payload["access_token"] = token  # Store raw token for admin operations
        
        logger.debug(f"✅ Authentication successful for user: {payload.get('email')}")
        return normalized_payload
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Authentication failed: {e}")
        raise HTTPException(
            status_code=401,
            detail=f"Authentication failed: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )

async def require_role(required_role: str):
    """Decorator factory to require specific roles"""
    def role_checker(current_user: Dict = Depends(authenticate_user)) -> Dict:
        user_role = current_user.get("role", "") # Default to empty string if role is missing
        if user_role != required_role:
            raise HTTPException(
                status_code=403,
                detail=f"Access denied. Required role: {required_role}"
            )
        return current_user
    return role_checker

async def get_current_admin_user(
    current_user: Dict = Depends(authenticate_user)
) -> Dict:
    """
    Dependency to get current user and verify admin role.
    
    Returns:
        Dict: Current user with admin privileges
        
    Raises:
        HTTPException: If user is not admin
    """
    user_role = current_user.get('role')
    if user_role != ADMIN_ROLE:
        raise HTTPException(
            status_code=403, 
            detail="Admin access required for this operation."
        )
    return current_user

async def require_admin_role(current_user: Dict = Depends(authenticate_user)) -> Dict:
    """
    Dependency to enforce that the current user has the 'admin' role.
    """
    user_role = current_user.get('role')
    if user_role != ADMIN_ROLE:
        raise HTTPException(
            status_code=403,
            detail="Access denied. Administrator privileges required."
        )
    return current_user

async def require_admin_or_supervisor_role(current_user: Dict = Depends(authenticate_user)) -> Dict:
    """
    Dependency to enforce that the current user has either 'admin', 'supervisor', or 'teacher' role.
    """
    user_role = current_user.get('role')
    if user_role not in [ADMIN_ROLE, SUPERVISOR_ROLE, TEACHER_ROLE]:
        raise HTTPException(
            status_code=403,
            detail="Access denied. Administrator, Supervisor, or Teacher privileges required."
        )
    return current_user


async def require_elevated_role(current_user: Dict = Depends(authenticate_user)) -> Dict:
    """
    Dependency that allows admin, supervisor, or teacher roles.
    Use this for management endpoints that teachers should also access.
    """
    user_role = current_user.get('role')
    if user_role not in ELEVATED_ROLES:
        raise HTTPException(
            status_code=403,
            detail="Access denied. Elevated privileges (admin, supervisor, or teacher) required."
        )
    return current_user

async def validate_external_user_status(external_user_id: str, user_email: str, admin_token: Optional[str] = None) -> bool:
    """
    Validate if user still exists and is active in external auth system.
    This prevents deleted external users from accessing the system.
    
    Args:
        external_user_id: External auth system user ID
        user_email: User's email for logging
        admin_token: Optional admin token for user validation
        
    Returns:
        bool: True if user exists and is valid, False if definitely removed/invalid
        
    Note:
        For admin users, this function is more lenient and allows system operations
        to continue even if external validation is uncertain.
    """
    try:
        from app.services.external_auth_service import ExternalAuthService
        
        external_auth_service = ExternalAuthService()
        
        # Check if user exists in external auth system
        user_exists = await external_auth_service.check_user_exists(external_user_id, admin_token)
        
        if not user_exists:
            logger.warning(f"🚨 SECURITY: User {user_email} (external_id: {external_user_id}) no longer exists in external auth system")
            return False
            
        logger.debug(f"✅ External validation successful for user: {user_email}")
        return True
        
    except Exception as e:
        logger.error(f"❌ Failed to validate external user status for {user_email}: {e}")
        # For security, default to denying access if we can't verify
        # BUT the caller (authenticate_user) may choose to be more lenient for admin users
        return False

async def deactivate_removed_external_user(local_user: User) -> None:
    """
    Deactivate local user and all their chatflow access when they're removed from external auth.
    """
    try:
        # Deactivate the local user
        local_user.is_active = False
        local_user.updated_at = datetime.utcnow()
        await local_user.save()
        
        # Deactivate all their chatflow assignments
        user_chatflows = await UserChatflow.find(
            UserChatflow.user_id == str(local_user.id),
            UserChatflow.is_active == True
        ).to_list()
        
        for uc in user_chatflows:
            uc.is_active = False
            await uc.save()
            
        logger.warning(f"🚨 SECURITY: Deactivated user {local_user.email} and {len(user_chatflows)} chatflow assignments due to external auth removal")
        
    except Exception as e:
        logger.error(f"❌ Failed to deactivate removed user {local_user.email}: {e}")
