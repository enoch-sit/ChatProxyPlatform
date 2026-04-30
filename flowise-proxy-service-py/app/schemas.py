from pydantic import BaseModel, Field, EmailStr
from typing import List, Dict, Optional, Literal
from datetime import datetime

# =================================================================================
# Request Models
# =================================================================================

class AddUsersByIdentifierRequest(BaseModel):
    """Request to add users to a chatflow using usernames or emails."""
    identifiers: List[str] = Field(default_factory=list)
    emails: List[EmailStr] = Field(default_factory=list)

    def resolved_identifiers(self) -> List[str]:
        if self.identifiers:
            return [identifier.strip() for identifier in self.identifiers if identifier.strip()]
        return [str(email).strip() for email in self.emails if str(email).strip()]

class AddUsersByEmailRequest(BaseModel):
    """Legacy request to add users to a chatflow using their emails."""
    chatflow_id: str
    emails: List[EmailStr]

class UserCleanupRequest(BaseModel):
    """Request model for user cleanup operations."""
    action: Literal["delete_invalid", "deactivate_invalid"] = Field("deactivate_invalid", description="The cleanup action to perform.")
    chatflow_ids: Optional[List[str]] = Field(None, description="Optional list of chatflow IDs to limit the scope of the cleanup.")
    dry_run: bool = Field(True, description="If true, the cleanup will only be simulated without making actual changes.")

class SyncUserByEmailRequest(BaseModel):
    """Request to synchronize a user's data from the external auth system."""
    email: EmailStr = Field(..., example="user@example.com", description="The email of the user to synchronize.")

class AddUserToChatflowRequest(BaseModel):
    """Request to add a single user to a chatflow by email."""
    email: EmailStr

class ChatflowSyncResult(BaseModel):
    total_fetched: int
    created: int
    updated: int
    deleted: int
    errors: int
    error_details: Optional[List[Dict]] = None

class ChatflowStats(BaseModel):
    total: int
    active: int
    deleted: int
    error: int
    last_sync: Optional[datetime] = None

class ChatflowResponse(BaseModel):
    flowise_id: str
    name: str
    description: Optional[str] = None
    category: Optional[str] = None
    deployed: bool
    is_public: Optional[bool] = None
    sync_status: Optional[str] = None
    created_date: Optional[datetime] = None
    updated_date: Optional[datetime] = None
    synced_at: Optional[datetime] = None

# =================================================================================
# Response Models
# =================================================================================

class UserAssignmentResponse(BaseModel):
    """Response for a single user-to-chatflow assignment operation."""
    identifier: str
    email: Optional[str] = None
    username: Optional[str] = None
    status: str
    message: Optional[str] = None

class BulkUserAssignmentResponse(BaseModel):
    """Response for a bulk user assignment operation."""
    successful_assignments: List[UserAssignmentResponse]
    failed_assignments: List[UserAssignmentResponse]

class ChatflowUserResponse(BaseModel):
    """Represents a user assigned to a chatflow."""
    username: str
    email: str
    role: str
    external_user_id: str
    assigned_at: datetime

class InvalidUserAssignment(BaseModel):
    """Details of an invalid user-chatflow assignment found during an audit."""
    user_chatflow_id: str
    external_user_id: str
    chatflow_id: str
    chatflow_name: Optional[str] = None
    issue_type: Literal["user_not_found_in_external_auth", "user_record_mismatch"]
    details: str

class UserAuditResult(BaseModel):
    """Response model for the user assignment audit."""
    total_assignments_checked: int
    valid_assignments: int
    invalid_assignments: int
    invalid_assignment_details: List[InvalidUserAssignment]
    audit_timestamp: datetime

class UserCleanupResult(BaseModel):
    """Response model for the user cleanup operation."""
    total_records_processed: int
    records_deactivated: int
    records_deleted: int
    errors: List[str]
    dry_run: bool
    cleanup_timestamp: datetime
    invalid_assignments_found: List[InvalidUserAssignment]

class SyncUserResponse(BaseModel):
    """Response for a user synchronization operation."""
    status: str
    message: str
    user_details: Optional[Dict] = None
