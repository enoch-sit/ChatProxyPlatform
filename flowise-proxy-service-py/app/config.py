import os
from pydantic_settings import BaseSettings
from pydantic import field_validator
from typing import Optional
import secrets

class Settings(BaseSettings):
    # JWT Configuration - Separate secret keys for access and refresh tokens
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "dev_access_secret_key_change_this_in_production")  # Legacy support
    JWT_ACCESS_SECRET: str = os.getenv("JWT_ACCESS_SECRET", os.getenv("JWT_SECRET_KEY", "dev_access_secret_key_change_this_in_production"))
    JWT_REFRESH_SECRET: str = os.getenv("JWT_REFRESH_SECRET", os.getenv("JWT_SECRET_KEY", "dev_refresh_secret_key_change_this_in_production"))
    JWT_ALGORITHM: str = os.getenv("JWT_ALGORITHM", "HS256")
    JWT_EXPIRATION_HOURS: int = int(os.getenv("JWT_EXPIRATION_HOURS", "24"))  # Legacy support
    
    # Token expiration configuration
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", "15"))
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = int(os.getenv("JWT_REFRESH_TOKEN_EXPIRE_DAYS", "7"))    # Flowise Configuration
    FLOWISE_API_URL: str = os.getenv("FLOWISE_API_URL", "http://somepublicendpoint.com")
    FLOWISE_API_KEY: Optional[str] = os.getenv("FLOWISE_API_KEY")
    
    # Chatflow sync settings
    ENABLE_CHATFLOW_SYNC: bool = os.getenv("ENABLE_CHATFLOW_SYNC", "true").lower() == "true"
    CHATFLOW_SYNC_INTERVAL_HOURS: float = float(os.getenv("CHATFLOW_SYNC_INTERVAL_HOURS", "0.05"))  # 3 minutes (0.05 hours)

    # External Services URLs - Updated to use new container-based URLs
    AUTH_API_URL: str = os.getenv("AUTH_API_URL", "http://localhost:3000")
    ACCOUNTING_API_URL: str = os.getenv("ACCOUNTING_API_URL", "http://localhost:3001")
    
    # Fallback URLs for local development
    EXTERNAL_AUTH_URL: str = os.getenv("EXTERNAL_AUTH_URL", "http://localhost:3000")
    ACCOUNTING_SERVICE_URL: str = os.getenv("ACCOUNTING_SERVICE_URL", "http://localhost:3001")    # Database - Updated to MongoDB
    MONGODB_URL: str = os.getenv("MONGODB_URL", "mongodb://mongodb:27017")
    MONGODB_DATABASE_NAME: str = os.getenv("MONGODB_DATABASE_NAME", "flowise_proxy")

    # Streaming Configuration
    MAX_STREAMING_DURATION: int = int(os.getenv("MAX_STREAMING_DURATION", "180000"))  # Increased from 120000ms to 180000ms (3 minutes)    # CORS Configuration
    CORS_ORIGIN: str = os.getenv("CORS_ORIGIN", "*")
    # CORS_ALLOW_ORIGINS: comma-separated list of explicit origins. Required when
    # allow_credentials=True (Starlette refuses to echo Origin if value is "*"
    # while credentials are allowed). Falls back to CORS_ORIGIN, then "*".
    CORS_ALLOW_ORIGINS: str = os.getenv(
        "CORS_ALLOW_ORIGINS",
        os.getenv("CORS_ORIGIN", "*"),
    )
      # Server Configuration
    DEBUG: bool = os.getenv("DEBUG", "true").lower() == "true"
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", "8000"))    # Logging Configuration
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO" if not os.getenv("DEBUG", "true").lower() == "true" else "DEBUG")
    
    @field_validator('LOG_LEVEL')
    @classmethod
    def validate_log_level(cls, v):
        """Validate log level is one of the allowed values"""
        allowed_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in allowed_levels:
            raise ValueError(f"LOG_LEVEL must be one of {allowed_levels}, got: {v}")
        return v.upper()
    
    def __post_init__(self):
        """Validate configuration after initialization"""
        # Validate JWT algorithm
        if self.JWT_ALGORITHM != "HS256":
            raise ValueError(f"Only HS256 algorithm is supported for JWT tokens, got: {self.JWT_ALGORITHM}")
        
        # Warn about weak secrets in production
        if not self.DEBUG:
            weak_secrets = [
                "your-super-secret-jwt-key-here",
                "dev_access_secret_key_change_this_in_production",
                "dev_refresh_secret_key_change_this_in_production",
                "secret", "password", "123456"
            ]
            
            # Check access secret
            if self.JWT_ACCESS_SECRET in weak_secrets or len(self.JWT_ACCESS_SECRET) < 32:
                raise ValueError("SECURITY WARNING: Weak JWT access secret detected in production mode. Use a strong, randomly generated secret key of at least 32 characters.")
            
            # Check refresh secret
            if self.JWT_REFRESH_SECRET in weak_secrets or len(self.JWT_REFRESH_SECRET) < 32:
                raise ValueError("SECURITY WARNING: Weak JWT refresh secret detected in production mode. Use a strong, randomly generated secret key of at least 32 characters.")
              # Check legacy secret (still used as fallback)
            if self.JWT_SECRET_KEY in weak_secrets or len(self.JWT_SECRET_KEY) < 32:
                raise ValueError("SECURITY WARNING: Weak JWT secret detected in production mode. Use a strong, randomly generated secret key of at least 32 characters.")

    class Config:
        env_file = ".env"
        extra = "ignore"  # Allow extra environment variables to be ignored

settings = Settings()

# Validate settings on module import
try:
    settings.__post_init__()
except Exception as e:
    print(f"⚠️  Configuration Warning: {e}")
