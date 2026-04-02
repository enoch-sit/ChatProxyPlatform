import httpx
import logging
from typing import Dict, Optional
from datetime import datetime
from app.config import settings
from app.auth.jwt_handler import JWTHandler
from app.auth.middleware import ELEVATED_ROLES
from app.models.user import User
from app.models.chatflow import Chatflow, UserChatflow
from app.models.refresh_token import RefreshToken


class AuthService:
    def __init__(self):
        self.jwt_handler = JWTHandler()
        self.logger = logging.getLogger(__name__)
        logging.basicConfig(level=logging.INFO)

    async def validate_user_permissions(self, user_id: str, chatflow_id: str, user_role: str = None) -> bool:
        """Validate if user has access to specific chatflow using MongoDB.
        
        Elevated roles (admin/supervisor/teacher) are granted access to all chatflows
        without requiring an explicit UserChatflow assignment.
        
        user_role: role from the JWT payload (preferred); falls back to DB lookup if not provided.
        """
        try:
            # 0. Check if user has an elevated role — bypass assignment check entirely
            # Prefer role from JWT (already trusted/validated); fall back to DB lookup
            effective_role = user_role
            if not effective_role:
                local_user = await User.find_one(User.external_id == user_id)
                effective_role = local_user.role if local_user else None

            if effective_role in ELEVATED_ROLES:
                self.logger.info(f"ACCESS GRANTED (elevated role '{effective_role}'): User '{user_id}' bypasses assignment check for chatflow '{chatflow_id}'")
                return True

            # The chatflow_id passed here is the flowise_id from the API request
            flowise_chatflow_id = chatflow_id

            # 1. Find the internal chatflow document from the flowise_id
            chatflow = await Chatflow.find_one(Chatflow.flowise_id == flowise_chatflow_id)
            
            if not chatflow:
                self.logger.warning(f"Permission check: No chatflow found with flowise_id: {flowise_chatflow_id}")
                return False
                
            # 2. Get the internal MongoDB _id as a string
            internal_chatflow_id = str(chatflow.id)

            # 3. Validate user has an active assignment to this internal chatflow_id
            user_chatflow = await UserChatflow.find_one(
                UserChatflow.external_user_id == user_id,
                UserChatflow.chatflow_id == internal_chatflow_id,
                UserChatflow.is_active == True
            )
            
            if user_chatflow:
                self.logger.info(f"ACCESS GRANTED: User '{user_id}' has access to chatflow '{flowise_chatflow_id}'")
            else:
                self.logger.warning(f"ACCESS DENIED: User '{user_id}' does not have access to chatflow '{flowise_chatflow_id}' (internal id: {internal_chatflow_id})")
            
            return user_chatflow is not None
        
        except Exception as e:
            self.logger.error(f"Permission validation error: {e}")
            return False
    
    def create_access_token(self, user_data: Dict) -> str:
        """Create JWT access token for authenticated user (legacy method)"""
        user_id = user_data.get("id")
        role = user_data.get("role", "User")
        return self.jwt_handler.create_access_token(user_id, role)
    
    async def create_token_pair(self, user_data: Dict, user_agent: str = None, ip_address: str = None) -> Dict:
        """Create both access and refresh tokens, store refresh token in database"""
        try:
            user_id = str(user_data.get("id"))
            role = user_data.get("role", "User")
            
            # Create token pair
            token_pair = self.jwt_handler.create_token_pair(user_id, role)
            
            # Store refresh token in database
            refresh_token_doc = RefreshToken(
                token_id=token_pair["token_id"],
                user_id=user_id,
                token_hash=self.jwt_handler.hash_token(token_pair["refresh_token"]),
                expires_at=RefreshToken.create_expiration(settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS),
                user_agent=user_agent,
                ip_address=ip_address
            )
            await refresh_token_doc.insert()
            
            self.logger.info(f"Created token pair for user {user_id}")
            return token_pair
            
        except Exception as e:
            self.logger.error(f"Error creating token pair: {e}")
            raise
    
    async def refresh_access_token(self, refresh_token: str, user_agent: str = None, ip_address: str = None) -> Optional[Dict]:
        """Refresh access token using refresh token with rotation"""
        try:
            # Verify refresh token
            payload = self.jwt_handler.verify_refresh_token(refresh_token)
            if not payload:
                return None
            
            user_id = self.jwt_handler.extract_user_id(payload)
            token_id = self.jwt_handler.extract_token_id(payload)
            
            # Find and validate stored refresh token
            stored_token = await RefreshToken.find_one(
                RefreshToken.token_id == token_id,
                RefreshToken.user_id == user_id
            )
            
            if not stored_token or not stored_token.is_valid():
                return None
            
            # Verify token hash matches
            if stored_token.token_hash != self.jwt_handler.hash_token(refresh_token):
                # Potential security issue - revoke all user tokens
                await self.revoke_all_user_tokens(user_id)
                self.logger.warning(f"Refresh token hash mismatch for user {user_id} - all tokens revoked")
                return None
            
            # Get user data for new tokens
            user = await User.get(user_id)
            if not user or not user.is_active:
                return None
            
            # Revoke old refresh token
            await self.revoke_refresh_token(token_id)
            
            # Create new token pair (token rotation)
            user_data = {
                "id": str(user.id),
                "username": user.username,
                "email": user.email,
                "role": user.role,
                "credits": user.credits
            }
            
            new_token_pair = await self.create_token_pair(user_data, user_agent, ip_address)
            self.logger.info(f"Refreshed tokens for user {user_id}")
            return new_token_pair
            
        except Exception as e:
            self.logger.error(f"Error refreshing token: {e}")
            return None
    
    async def revoke_refresh_token(self, token_id: str) -> bool:
        """Revoke a specific refresh token"""
        try:
            token = await RefreshToken.find_one(RefreshToken.token_id == token_id)
            if token:
                token.revoke()
                await token.save()
                return True
            return False
        except Exception as e:
            self.logger.error(f"Error revoking token {token_id}: {e}")
            return False
    
    async def revoke_all_user_tokens(self, user_id: str) -> bool:
        """Revoke all refresh tokens for a user"""
        try:
            tokens = await RefreshToken.find(
                RefreshToken.user_id == user_id,
                RefreshToken.is_revoked == False
            ).to_list()
            
            for token in tokens:
                token.revoke()
                await token.save()
            
            self.logger.info(f"Revoked {len(tokens)} tokens for user {user_id}")
            return True
        except Exception as e:
            self.logger.error(f"Error revoking all tokens for user {user_id}: {e}")
            return False
    
    async def cleanup_expired_tokens(self) -> int:
        """Clean up expired refresh tokens (manual cleanup, TTL handles automatic)"""
        try:
            expired_tokens = await RefreshToken.find(
                RefreshToken.expires_at < datetime.utcnow()
            ).to_list()
            
            for token in expired_tokens:
                await token.delete()
            
            self.logger.info(f"Cleaned up {len(expired_tokens)} expired tokens")
            return len(expired_tokens)
        except Exception as e:
            self.logger.error(f"Error cleaning up expired tokens: {e}")
            return 0
