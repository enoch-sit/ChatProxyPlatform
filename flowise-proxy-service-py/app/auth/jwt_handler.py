import jwt
import logging
from datetime import datetime, timedelta
from typing import Dict, Optional, List, Tuple
from app.config import settings
import secrets
import hashlib
from enum import Enum

logger = logging.getLogger(__name__)

class TokenType(Enum):
    ACCESS = "access"
    REFRESH = "refresh"

class JWTHandler:
    @staticmethod
    def create_access_token(user_id: str, role: str = "User") -> str:
        """Create an access token with 15-minute expiration"""
        payload = {
            "sub": str(user_id),  # Standard JWT subject claim
            "role": role,
            "type": TokenType.ACCESS.value
        }
        return JWTHandler._create_token(payload, expires_minutes=15)
    
    @staticmethod
    def create_refresh_token(user_id: str) -> Tuple[str, str]:
        """Create a refresh token with 7-day expiration. Returns (token, token_id)"""
        token_id = secrets.token_urlsafe(32)
        payload = {
            "sub": str(user_id),  # Standard JWT subject claim
            "type": TokenType.REFRESH.value,
            "jti": token_id  # JWT ID for database storage
        }
        token = JWTHandler._create_token(payload, expires_days=7)
        return token, token_id
    
    @staticmethod
    def create_token_pair(user_id: str, role: str = "User") -> Dict[str, str]:
        """Create both access and refresh tokens"""
        access_token = JWTHandler.create_access_token(user_id, role)
        refresh_token, token_id = JWTHandler.create_refresh_token(user_id)
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_id": token_id,
            "token_type": "Bearer",
            "expires_in": 15 * 60  # 15 minutes in seconds
        }
    
    @staticmethod
    def _create_token(payload: Dict, expires_minutes: int = None, expires_days: int = None) -> str:
        """Internal method to create JWT tokens with specified expiration"""
        try:
            # Validate algorithm is HS256
            if settings.JWT_ALGORITHM != "HS256":
                raise ValueError(f"Only HS256 algorithm is supported, got: {settings.JWT_ALGORITHM}")
            
            # Calculate expiration
            now = datetime.utcnow()
            if expires_minutes:
                expire = now + timedelta(minutes=expires_minutes)
            elif expires_days:
                expire = now + timedelta(days=expires_days)
            else:
                expire = now + timedelta(hours=settings.JWT_EXPIRATION_HOURS)
            
            # Enhanced payload with security fields
            enhanced_payload = payload.copy()
            enhanced_payload.update({
                "exp": expire,
                "iat": now,
                "nbf": now,  # Not valid before
                "iss": "flowise-proxy-service",  # Issuer
                "aud": "flowise-api"  # Audience
            })
            
            # Add jti if not present (for access tokens)
            if "jti" not in enhanced_payload:
                enhanced_payload["jti"] = secrets.token_urlsafe(16)
            
            # Use appropriate secret based on token type
            token_type = payload.get("type", TokenType.ACCESS.value)
            if token_type == TokenType.ACCESS.value:
                secret_key = settings.JWT_ACCESS_SECRET
            elif token_type == TokenType.REFRESH.value:
                secret_key = settings.JWT_REFRESH_SECRET
            else:
                secret_key = settings.JWT_SECRET_KEY  # Fallback for legacy tokens
            
            # Generate token with HS256
            token = jwt.encode(
                enhanced_payload, 
                secret_key, 
                algorithm="HS256"  # Explicitly use HS256
            )
            return token
        except Exception as e:
            raise Exception(f"Error creating JWT token: {str(e)}")    @staticmethod
    def verify_access_token(token: str) -> Optional[Dict]:
        """Verify and decode an access token"""
        payload = JWTHandler._verify_token(token)
        if payload and payload.get("type") == TokenType.ACCESS.value:
            return payload
        return None
    
    @staticmethod
    def verify_refresh_token(token: str) -> Optional[Dict]:
        """Verify and decode a refresh token"""
        payload = JWTHandler._verify_token(token)
        if payload and payload.get("type") == TokenType.REFRESH.value:
            return payload
        return None
    
    @staticmethod
    def _verify_token(token: str) -> Optional[Dict]:
        """Internal method to verify and decode any JWT token with enhanced security checks"""
        try:
            # First decode without verification to get token type
            unverified_payload = jwt.decode(token, options={"verify_signature": False})
            token_type = unverified_payload.get("type", TokenType.ACCESS.value)
            
            # Use appropriate secret based on token type
            if token_type == TokenType.ACCESS.value:
                secret_key = settings.JWT_ACCESS_SECRET
            elif token_type == TokenType.REFRESH.value:
                secret_key = settings.JWT_REFRESH_SECRET
            else:
                secret_key = settings.JWT_SECRET_KEY  # Fallback for legacy tokens
            
            # Explicitly specify HS256 algorithm and validate claims
            # NOTE: require_nbf and verify_nbf are disabled because the auth-service
            # (Node.js jsonwebtoken) does NOT set the `nbf` claim by default.
            # Requiring it causes ALL tokens from auth-service to fail validation.
            payload = jwt.decode(
                token, 
                secret_key, 
                algorithms=["HS256"],  # Only allow HS256
                options={
                    "verify_signature": True,
                    "verify_exp": True,
                    "verify_nbf": False,
                    "verify_iat": True,
                    "require_exp": True,
                    "require_iat": True,
                    "require_nbf": False
                },
            )
            
            # Additional validation - ensure subject (user ID) exists
            if not payload.get("sub"):
                raise jwt.InvalidTokenError("Token missing required sub claim")
            
            # Ensure token type is specified
            if not payload.get("type"):
                raise jwt.InvalidTokenError("Token missing required type claim")
                
            return payload
        except jwt.ExpiredSignatureError:
            logger.warning("Token verification failed: token expired")
            return None
        except jwt.InvalidSignatureError:
            logger.warning("Token verification failed: invalid signature (secret mismatch?)")
            return None
        except jwt.InvalidTokenError as e:
            logger.warning(f"Token verification failed: {type(e).__name__}: {e}")
            return None
        except jwt.InvalidIssuerError:
            logger.warning("Token verification failed: invalid issuer")
            return None
        except jwt.InvalidAudienceError:
            logger.warning("Token verification failed: invalid audience")
            return None
        except Exception as e:
            logger.error(f"Token verification unexpected error: {type(e).__name__}: {e}")
            return None

    @staticmethod
    def create_token(payload: Dict) -> str:
        """Legacy method for backward compatibility - creates access token"""
        user_id = payload.get("user_id") or payload.get("sub")
        role = payload.get("role", "User")
        if not user_id:
            raise ValueError("payload must contain user_id or sub")
        return JWTHandler.create_access_token(user_id, role)

    @staticmethod
    def verify_token(token: str) -> Optional[Dict]:
        """Legacy method for backward compatibility - verifies any token type"""
        return JWTHandler._verify_token(token)

    @staticmethod
    def decode_token(token: str) -> Optional[Dict]:
        """Decode a JWT token without verification (for debugging only)"""
        try:
            payload = jwt.decode(token, options={"verify_signature": False})
            return payload
        except Exception:
            return None
    
    @staticmethod
    def validate_secret_strength(secret: str) -> bool:
        """Validate JWT secret key strength for HS256"""
        if len(secret) < 32:
            return False
        
        # Check for common weak secrets
        weak_secrets = [
            "secret", "password", "123456", "your-secret-key", 
            "dev_access_secret_key_change_this_in_production"
        ]
        
        if secret.lower() in weak_secrets:
            return False
            
        return True
    
    @staticmethod
    def get_token_info(token: str) -> Dict:
        """Get token information for debugging (header and payload)"""
        try:
            # Decode header
            header = jwt.get_unverified_header(token)
              # Decode payload without verification
            payload = jwt.decode(token, options={"verify_signature": False})
            return {
                "header": header,
                "payload": payload,
                "algorithm": header.get("alg"),
                "is_hs256": header.get("alg") == "HS256",
                "token_type": payload.get("type"),
                "expires_at": datetime.fromtimestamp(payload.get("exp", 0)) if payload.get("exp") else None
            }
        except Exception as e:
            return {"error": str(e)}
    
    @staticmethod
    def extract_user_id(token_payload: Dict) -> Optional[str]:
        """Extract user ID from validated token payload (supports both sub and legacy user_id)"""
        return token_payload.get("sub") or token_payload.get("user_id")
    
    @staticmethod
    def extract_user_role(token_payload: Dict) -> Optional[str]:
        """Extract user role from validated token payload"""
        return token_payload.get("role")
    
    @staticmethod
    def extract_token_id(token_payload: Dict) -> Optional[str]:
        """Extract token ID (jti) from validated token payload"""
        return token_payload.get("jti")
    
    @staticmethod
    def extract_token_type(token_payload: Dict) -> Optional[str]:
        """Extract token type from validated token payload"""
        return token_payload.get("type")
    
    @staticmethod
    def is_token_expired(token: str) -> bool:
        """Check if token is expired without full validation"""
        try:
            payload = jwt.decode(token, options={"verify_signature": False})
            exp = payload.get("exp")
            if exp:
                return datetime.utcnow().timestamp() > exp
            return True
        except:
            return True
    
    @staticmethod
    def hash_token(token: str) -> str:
        """Create a secure hash of a token for database storage"""
        return hashlib.sha256(token.encode()).hexdigest()
