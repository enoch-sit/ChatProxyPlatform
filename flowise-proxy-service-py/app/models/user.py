from beanie import Document, PydanticObjectId
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class User(Document):
    username: Optional[str] = Field(..., max_length=50)
    email: Optional[str]
    role: str = Field(default="user")
    is_active: bool = Field(default=True)
    external_id: Optional[str] = Field(None, index=True, unique=True, sparse=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "users"
        indexes = [
            "external_id",
        ]

    class Config:
        # This is the crucial part
        json_encoders = {
            PydanticObjectId: str,
        }
