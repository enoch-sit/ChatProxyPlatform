import json
from datetime import datetime
from typing import List, Optional, Dict, Any
from motor.motor_asyncio import AsyncIOMotorDatabase
from fastapi import HTTPException
from app.models.chatflow import Chatflow, UserChatflow
from app.services.flowise_service import FlowiseService
from app.exceptions import FlowiseAPIError
from app.core.logging import logger
from app.models.user import User
from app.services.external_auth_service import ExternalAuthService
# Import the schemas from the new central location
from app.schemas import (
    ChatflowSyncResult,
    UserAuditResult,
    UserCleanupResult,
    InvalidUserAssignment,
    BulkUserAssignmentResponse,
    UserAssignmentResponse,
    ChatflowUserResponse,
    SyncUserResponse
)

class ChatflowService:
    BATCH_REMOVAL_PROTECTED_ROLES = {"admin", "supervisor", "teacher"}

    def __init__(self, db: AsyncIOMotorDatabase, flowise_service: FlowiseService, external_auth_service: ExternalAuthService):
        self.db = db
        self.flowise_service = flowise_service
        self.external_auth_service = external_auth_service

    def _identifier_type(self, identifier: str) -> str:
        return "email" if "@" in identifier else "username"

    async def _get_local_user_by_identifier(self, identifier: str) -> Optional[User]:
        if self._identifier_type(identifier) == "email":
            return await User.find_one(User.email == identifier)
        return await User.find_one(User.username == identifier)

    def _is_admin_user(self, user: User) -> bool:
        return (user.role or "").lower() == "admin"

    def _is_batch_removal_protected(self, user: User) -> bool:
        return (user.role or "").lower() in self.BATCH_REMOVAL_PROTECTED_ROLES

    async def _get_external_user_data_by_identifier(self, identifier: str, admin_token: str) -> Dict[str, Any]:
        lookup_type = self._identifier_type(identifier)
        external_user_data = (
            await self.external_auth_service.get_user_by_email(identifier, admin_token)
            if lookup_type == "email"
            else await self.external_auth_service.get_user_by_username(identifier, admin_token)
        )

        if not external_user_data:
            raise HTTPException(
                status_code=404,
                detail=f"User with {lookup_type} '{identifier}' not found in external system.",
            )

        return external_user_data

    async def _sync_external_user_data(self, external_user_data: Dict[str, Any], identifier: str) -> SyncUserResponse:
        external_id = external_user_data.get('user_id')
        if not external_id:
            raise HTTPException(status_code=400, detail="External user data is missing user_id.")

        local_user = await User.find_one(User.external_id == external_id)

        if not local_user:
            if not external_user_data.get('username') or not external_user_data.get('email'):
                raise HTTPException(status_code=400, detail="External user data is missing required fields for new user creation (username, email).")

            local_user = User(
                external_id=external_id,
                username=external_user_data['username'],
                email=external_user_data['email'],
                role=external_user_data.get('role', 'user'),
                is_active=external_user_data.get('is_verified', True)
            )
        else:
            local_user.username = external_user_data.get('username', local_user.username)
            local_user.email = external_user_data.get('email', local_user.email)
            local_user.role = external_user_data.get('role', local_user.role)
            local_user.is_active = external_user_data.get('is_verified', local_user.is_active)
            local_user.updated_at = datetime.utcnow()

        await local_user.save()

        logger.info(f"Successfully synced user '{identifier}' (External ID: {external_id}) to local database.")
        return SyncUserResponse(
            status="success",
            message="User synchronized successfully.",
            user_details=local_user.model_dump(mode='json')
        )

    async def sync_user_by_identifier(self, identifier: str, admin_token: str) -> SyncUserResponse:
        external_user_data = await self._get_external_user_data_by_identifier(identifier, admin_token)
        return await self._sync_external_user_data(external_user_data, identifier)

    async def sync_chatflows_from_flowise(self) -> ChatflowSyncResult:
        """
        Synchronize chatflows from Flowise API to local database using Beanie ODM.
        """
        result = ChatflowSyncResult(
            total_fetched=0,
            created=0,
            updated=0,
            deleted=0,
            errors=0,
            error_details=[]
        )
        
        try:
            # Fetch chatflows from Flowise
            try:
                flowise_chatflows = await self.flowise_service.list_chatflows()
            except FlowiseAPIError as e:
                result.errors += 1
                error_msg = f"Failed to fetch chatflows from Flowise API: {str(e)}"
                result.error_details.append({"error": error_msg, "type": "flowise_api_error"})
                logger.error(error_msg)
                return result

            result.total_fetched = len(flowise_chatflows)
            
            # Get existing chatflows from database using Beanie
            existing_chatflows = await Chatflow.find_all().to_list()
            existing_ids_map = {cf.flowise_id: cf for cf in existing_chatflows}
            
            # Guard: if Flowise returned 0 chatflows but we have local data,
            # skip the deletion step to prevent accidental mass-deletion
            # (e.g. during a Flowise restart or API key mismatch).
            skip_deletion = (
                len(flowise_chatflows) == 0 and len(existing_chatflows) > 0
            )
            if skip_deletion:
                warning_msg = (
                    f"Flowise returned 0 chatflows but {len(existing_chatflows)} exist locally "
                    f"— skipping deletion to prevent data loss"
                )
                result.error_details.append({"warning": warning_msg, "type": "empty_response_guard"})
                logger.warning(warning_msg)

            # Track current Flowise IDs
            current_flowise_ids = set()
            
            # Process each chatflow from Flowise
            for flowise_cf in flowise_chatflows:
                try:
                    flowise_id = flowise_cf["id"]
                    current_flowise_ids.add(flowise_id)
                    
                    # Convert Flowise chatflow to our model data
                    chatflow_data = await self._convert_flowise_chatflow(flowise_cf)
                    
                    # Check if chatflow exists
                    if flowise_id in existing_ids_map:
                        # Update existing chatflow using Beanie
                        chatflow_to_update = existing_ids_map[flowise_id]
                        await chatflow_to_update.update({"$set": chatflow_data})
                        result.updated += 1
                        logger.info(f"Updated chatflow: {chatflow_data['name']} ({flowise_id})")
                    else:
                        # Create new chatflow using Beanie
                        new_chatflow = Chatflow(**chatflow_data)
                        await new_chatflow.insert()
                        result.created += 1
                        logger.info(f"Created chatflow: {chatflow_data['name']} ({flowise_id})")
                        
                except Exception as e:
                    result.errors += 1
                    error_msg = f"Error processing chatflow {flowise_cf.get('id', 'unknown')}: {str(e)}"
                    result.error_details.append({"error": error_msg, "chatflow_id": flowise_cf.get('id', 'unknown')})
                    logger.error(error_msg)
            
            # Mark deleted chatflows using Beanie
            if not skip_deletion:
                deleted_ids = set(existing_ids_map.keys()) - current_flowise_ids
                if deleted_ids:
                    await Chatflow.find({"flowise_id": {"$in": list(deleted_ids)}}).update(
                        {"$set": {"sync_status": "deleted", "synced_at": datetime.utcnow()}}
                    )
                    result.deleted = len(deleted_ids)
                    logger.info(f"Marked {len(deleted_ids)} chatflows as deleted")
            
        except Exception as e:
            result.errors += 1
            error_msg = f"Failed to sync chatflows: {str(e)}"
            result.error_details.append({"error": error_msg, "type": "general_sync_error"})
            logger.error(error_msg)
        
        return result

    async def list_chatflows(self, include_deleted: bool = False) -> List[Chatflow]:
        """
        Lists chatflows from the database.
        If include_deleted is False, it only returns chatflows that are not deleted.
        """
        if include_deleted:
            query = {}
        else:
            # This will return chatflows where sync_status is not 'deleted'
            query = {"sync_status": {"$ne": "deleted"}}
        
        return await Chatflow.find(query).to_list()

    async def get_chatflow_stats(self) -> Dict[str, Any]:
        """
        Get chatflow statistics using Beanie ODM.
        """
        pipeline = [
            {
                "$group": {
                    "_id": "$sync_status",
                    "count": {"$sum": 1}
                }
            }
        ]
        
        stats_cursor = Chatflow.aggregate(pipeline)
        stats_list = await stats_cursor.to_list()
        
        stats = {item["_id"]: item["count"] for item in stats_list}
        
        total = await Chatflow.count()
        last_sync = await self._get_last_sync_time()

        return {
            "total": total,
            "active": stats.get("active", 0),
            "deleted": stats.get("deleted", 0),
            "error": stats.get("error", 0),
            "last_sync": last_sync if last_sync else None
        }

    async def _get_last_sync_time(self) -> Optional[datetime]:
        """
        Get the timestamp of the last successful sync using Beanie ODM.
        """
        result = await Chatflow.find_one(sort=[(Chatflow.synced_at, -1)])
        return result.synced_at if result else None

    async def get_chatflow_by_flowise_id(self, flowise_id: str) -> Optional[Chatflow]:
        """
        Get chatflow by Flowise ID using Beanie ODM.
        """
        return await Chatflow.find_one(Chatflow.flowise_id == flowise_id)

    async def add_user_to_chatflow_by_email(self, email: str, flowise_id: str, admin_user: Dict) -> UserAssignmentResponse:
        """Assigns a single user to a chatflow by their email address."""
        admin_token = admin_user.get("access_token")

        chatflow = await self.get_chatflow_by_flowise_id(flowise_id)
        if not chatflow:
            raise HTTPException(status_code=404, detail=f"Chatflow with ID '{flowise_id}' not found.")

        try:
            # 1. Sync user to ensure they exist locally and get their external_id
            sync_response = await self.sync_user_by_email(email, admin_token)
            if sync_response.status != "success":
                # sync_user_by_email can raise HTTPException, which is fine.
                # If it returns a non-success status without raising, we raise here.
                raise HTTPException(status_code=400, detail=sync_response.message)
            
            external_user_id = sync_response.user_details['external_id']

            # 2. Check for existing assignment
            existing_assignment = await UserChatflow.find_one(
                UserChatflow.external_user_id == external_user_id,
                UserChatflow.chatflow_id == str(chatflow.id)
            )

            if existing_assignment:
                if not existing_assignment.is_active:
                    existing_assignment.is_active = True
                    existing_assignment.assigned_at = datetime.utcnow()
                    await existing_assignment.save()
                    status = "Reactivated"
                    message = "Existing inactive assignment has been reactivated."
                else:
                    status = "No Action"
                    message = "User is already actively assigned to this chatflow."
            else:
                # 3. Create new assignment
                new_assignment = UserChatflow(
                    external_user_id=external_user_id,
                    chatflow_id=str(chatflow.id),
                    assigned_by=admin_user.get('sub'),
                    is_active=True
                )
                await new_assignment.insert()
                status = "Assigned"
                message = "User successfully assigned to the chatflow."

            return UserAssignmentResponse(email=email, status=status, message=message)

        except HTTPException:
            raise # Re-raise HTTPException to be handled by FastAPI
        except Exception as e:
            logger.error(f"Failed to assign user '{email}' to chatflow '{flowise_id}': {e}")
            raise HTTPException(status_code=500, detail=f"An unexpected error occurred: {str(e)}")

    async def add_users_to_chatflow_by_email(self, emails: List[str], flowise_id: str, admin_user: Dict) -> BulkUserAssignmentResponse:
        """Assigns multiple users to a chatflow by their email addresses."""
        return await self.add_users_to_chatflow_by_identifier(emails, flowise_id, admin_user)

    async def add_users_to_chatflow_by_identifier(self, identifiers: List[str], flowise_id: str, admin_user: Dict) -> BulkUserAssignmentResponse:
        """Assigns multiple users to a chatflow using usernames or emails."""
        successful_assignments = []
        failed_assignments = []
        admin_token = admin_user.get("access_token")

        chatflow = await self.get_chatflow_by_flowise_id(flowise_id)
        if not chatflow:
            raise HTTPException(status_code=404, detail=f"Chatflow with ID '{flowise_id}' not found.")

        for identifier in identifiers:
            try:
                external_user_data = await self._get_external_user_data_by_identifier(identifier, admin_token)
                sync_response = await self._sync_external_user_data(external_user_data, identifier)
                if sync_response.status != "success":
                    raise HTTPException(status_code=404, detail=sync_response.message)
                
                external_user_id = sync_response.user_details['external_id']

                # 2. Check for existing assignment
                existing_assignment = await UserChatflow.find_one(
                    UserChatflow.external_user_id == external_user_id,
                    UserChatflow.chatflow_id == str(chatflow.id)
                )

                if existing_assignment:
                    if not existing_assignment.is_active:
                        existing_assignment.is_active = True
                        existing_assignment.assigned_at = datetime.utcnow()
                        await existing_assignment.save()
                        status = "Reactivated"
                        message = "Existing inactive assignment has been reactivated."
                    else:
                        status = "No Action"
                        message = "User is already actively assigned to this chatflow."
                else:
                    # 3. Create new assignment
                    new_assignment = UserChatflow(
                        external_user_id=external_user_id,
                        chatflow_id=str(chatflow.id),
                        assigned_by=admin_user.get('sub'),
                        is_active=True
                    )
                    await new_assignment.insert()
                    status = "Assigned"
                    message = "User successfully assigned to the chatflow."

                successful_assignments.append(UserAssignmentResponse(
                    identifier=identifier,
                    email=external_user_data.get('email'),
                    username=external_user_data.get('username'),
                    status=status,
                    message=message,
                ))

            except Exception as e:
                logger.error(f"Failed to assign user '{identifier}' to chatflow '{flowise_id}': {e}")
                failed_assignments.append(UserAssignmentResponse(identifier=identifier, status="Failed", message=str(e)))
        
        return BulkUserAssignmentResponse(
            successful_assignments=successful_assignments,
            failed_assignments=failed_assignments
        )

    async def list_users_for_chatflow(self, flowise_id: str) -> List[ChatflowUserResponse]:
        chatflow = await self.get_chatflow_by_flowise_id(flowise_id)
        if not chatflow:
            raise HTTPException(status_code=404, detail="Chatflow not found")

        assignments = await UserChatflow.find(
            UserChatflow.chatflow_id == str(chatflow.id),
            UserChatflow.is_active == True
        ).to_list()

        response = []
        for assignment in assignments:
            user = await User.find_one(User.external_id == assignment.external_user_id)
            if user:
                response.append(
                    ChatflowUserResponse(
                        username=user.username,
                        email=user.email,
                        role=user.role,
                        external_user_id=user.external_id,
                        assigned_at=assignment.assigned_at  # Fixed attribute
                    )
                )
        return response

    async def remove_users_from_chatflow_by_identifier(self, identifiers: List[str], flowise_id: str, admin_user: Dict) -> BulkUserAssignmentResponse:
        chatflow = await self.get_chatflow_by_flowise_id(flowise_id)
        if not chatflow:
            raise HTTPException(status_code=404, detail=f"Chatflow with ID '{flowise_id}' not found.")

        successful_assignments = []
        failed_assignments = []

        for identifier in identifiers:
            try:
                user = await self._get_local_user_by_identifier(identifier)
                if not user or not user.external_id:
                    raise HTTPException(status_code=404, detail=f"User '{identifier}' not found or has no external ID.")

                if self._is_batch_removal_protected(user):
                    status = "Blocked"
                    message = f"Users with role '{user.role}' cannot be batch removed from chatflows."
                    failed_assignments.append(UserAssignmentResponse(
                        identifier=identifier,
                        email=user.email,
                        username=user.username,
                        status=status,
                        message=message,
                    ))
                    continue

                assignment = await UserChatflow.find_one(
                    UserChatflow.external_user_id == user.external_id,
                    UserChatflow.chatflow_id == str(chatflow.id)
                )

                if not assignment or not assignment.is_active:
                    raise HTTPException(status_code=404, detail="Active assignment for this user and chatflow not found.")

                assignment.is_active = False
                assignment.assigned_at = datetime.utcnow()
                await assignment.save()

                logger.info(
                    f"Admin '{admin_user.get('email')}' batch-deactivated access for user '{identifier}' from chatflow '{flowise_id}'"
                )
                successful_assignments.append(UserAssignmentResponse(
                    identifier=identifier,
                    email=user.email,
                    username=user.username,
                    status="Deactivated",
                    message="User access has been successfully revoked.",
                ))

            except HTTPException as exc:
                failed_assignments.append(UserAssignmentResponse(identifier=identifier, status="Failed", message=exc.detail))
            except Exception as e:
                logger.error(f"Failed to batch remove user '{identifier}' from chatflow '{flowise_id}': {e}")
                failed_assignments.append(UserAssignmentResponse(identifier=identifier, status="Failed", message=str(e)))

        return BulkUserAssignmentResponse(
            successful_assignments=successful_assignments,
            failed_assignments=failed_assignments
        )

    async def remove_user_from_chatflow_by_email(self, email: str, flowise_id: str, admin_user: Dict) -> UserAssignmentResponse:
        chatflow = await self.get_chatflow_by_flowise_id(flowise_id)
        if not chatflow:
            raise HTTPException(status_code=404, detail="Chatflow not found")

        user = await User.find_one(User.email == email)
        if not user or not user.external_id:
            raise HTTPException(status_code=404, detail=f"User with email '{email}' not found or has no external ID.")

        if self._is_admin_user(user):
            raise HTTPException(status_code=403, detail="Admin users cannot be removed from chatflows.")

        assignment = await UserChatflow.find_one(
            UserChatflow.external_user_id == user.external_id,
            UserChatflow.chatflow_id == str(chatflow.id)
        )

        if not assignment or not assignment.is_active:
            raise HTTPException(status_code=404, detail="Active assignment for this user and chatflow not found.")

        assignment.is_active = False
        assignment.assigned_at = datetime.utcnow()
        await assignment.save()

        logger.info(f"Admin '{admin_user.get('email')}' deactivated access for user '{email}' from chatflow '{flowise_id}'")
        return UserAssignmentResponse(identifier=email, email=email, username=user.username, status="Deactivated", message="User access has been successfully revoked.")

    async def sync_user_by_email(self, email: str, admin_token: str) -> SyncUserResponse:
        try:
            return await self.sync_user_by_identifier(email, admin_token)
        except Exception as e:
            logger.error(f"Failed to sync user '{email}': {e}")
            raise

    async def audit_user_assignments(self, admin_token: str, chatflow_ids: Optional[list[str]] = None) -> UserAuditResult:
        """Audits all UserChatflow records for integrity issues."""
        query_filter = {}
        if chatflow_ids:
            query_filter["chatflow_id"] = {"$in": chatflow_ids}

        all_assignments = await UserChatflow.find(query_filter).to_list()
        all_chatflows = await Chatflow.find().to_list()
        chatflow_map = {str(cf.id): cf for cf in all_chatflows}

        invalid_assignments = []
        assignments_by_issue_type = {}

        for assignment in all_assignments:
            issue_found = False
            issue_type = None
            details = ""
            suggested_action = "N/A"

            # Check 1: Does the user exist in the external system?
            external_user = await self.external_auth_service.get_user_by_id(assignment.external_user_id, admin_token)
            if not external_user:
                issue_found = True
                issue_type = "user_not_found"
                details = f"User with external_id {assignment.external_user_id} not found in the external authentication service."
                suggested_action = "deactivate_invalid"
            
            # If you add more checks (e.g., email mismatch), they would go here.

            if issue_found:
                chatflow_name = chatflow_map.get(assignment.chatflow_id, "Unknown Chatflow")
                invalid_assignments.append(InvalidUserAssignment(
                    user_chatflow_id=str(assignment.id),
                    external_user_id=assignment.external_user_id,
                    chatflow_id=assignment.chatflow_id,
                    chatflow_name=chatflow_name.name if chatflow_name != "Unknown Chatflow" else chatflow_name,
                    issue_type=issue_type,
                    details=details,
                    suggested_action=suggested_action
                ))
                assignments_by_issue_type[issue_type] = assignments_by_issue_type.get(issue_type, 0) + 1

        return UserAuditResult(
            total_assignments=len(all_assignments),
            valid_assignments=len(all_assignments) - len(invalid_assignments),
            invalid_assignments=len(invalid_assignments),
            assignments_by_issue_type=assignments_by_issue_type,
            chatflows_affected=len(set(ia.chatflow_id for ia in invalid_assignments)),
            invalid_user_details=invalid_assignments,
            audit_timestamp=datetime.utcnow(),
            recommendations=["Run the cleanup endpoint to resolve invalid assignments."]
        )

    async def cleanup_user_assignments(self, admin_token: str, action: str, dry_run: bool, chatflow_ids: Optional[list[str]] = None) -> UserCleanupResult:
        """Cleans up invalid UserChatflow records."""
        audit_result = await self.audit_user_assignments(admin_token, chatflow_ids)
        
        result = UserCleanupResult(
            total_records_processed=audit_result.total_assignments,
            invalid_user_ids_found=audit_result.invalid_assignments,
            records_deleted=0,
            records_deactivated=0,
            records_reassigned=0, # Not implemented yet
            errors=0,
            error_details=[],
            dry_run=dry_run,
            cleanup_timestamp=datetime.utcnow(),
            invalid_assignments=audit_result.invalid_user_details
        )

        if not dry_run:
            for invalid in audit_result.invalid_user_details:
                try:
                    if action == "deactivate_invalid":
                        await UserChatflow.find_one(UserChatflow.id == invalid.user_chatflow_id).update({"$set": {"is_active": False}})
                        result.records_deactivated += 1
                    elif action == "delete_invalid":
                        await UserChatflow.find_one(UserChatflow.id == invalid.user_chatflow_id).delete()
                        result.records_deleted += 1
                except Exception as e:
                    result.errors += 1
                    result.error_details.append({
                        "error": f"Failed to process record {invalid.user_chatflow_id}: {e}",
                        "record_id": invalid.user_chatflow_id,
                        "type": "cleanup_error"
                    })

        return result

    async def _convert_flowise_chatflow(self, flowise_cf: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert Flowise chatflow format to our database format
        """
        # Parse JSON strings to objects
        def safe_json_parse(json_str: str) -> Optional[Dict[str, Any]]:
            if not json_str or json_str == "{}":
                return None
            try:
                return json.loads(json_str)
            except (json.JSONDecodeError, TypeError):
                return None

        # Parse ISO timestamps
        def parse_timestamp(timestamp_str: str) -> Optional[datetime]:
            if not timestamp_str:
                return None
            try:
                return datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            except (ValueError, TypeError):
                return None

        return {
            "flowise_id": flowise_cf["id"],
            "name": flowise_cf.get("name", ""),
            "description": flowise_cf.get("description", ""),
            "deployed": flowise_cf.get("deployed", False),
            "is_public": flowise_cf.get("isPublic", False),
            "category": flowise_cf.get("category"),
            "type": flowise_cf.get("type", "CHATFLOW"),
            "api_key_id": flowise_cf.get("apikeyid"),
            
            # Parse configuration JSON strings
            "flow_data": safe_json_parse(flowise_cf.get("flowData")),
            "chatbot_config": safe_json_parse(flowise_cf.get("chatbotConfig")),
            "api_config": safe_json_parse(flowise_cf.get("apiConfig")),
            "analytic_config": safe_json_parse(flowise_cf.get("analytic")),
            "speech_to_text_config": safe_json_parse(flowise_cf.get("speechToText")),
            
            # Parse timestamps
            "created_date": parse_timestamp(flowise_cf.get("createdDate")),
            "updated_date": parse_timestamp(flowise_cf.get("updatedDate")),
            "synced_at": datetime.utcnow(),
            "sync_status": "active",
            "sync_error": None
        }

    async def get_users_for_chatflow(self, chatflow_id: str, admin_user: Dict) -> List[Dict]:
        """Lists all users assigned to a specific chatflow."""
        # 1. Check if chatflow exists
        chatflow = await self.get_chatflow_by_flowise_id(chatflow_id)
        if not chatflow:
            raise HTTPException(status_code=404, detail=f"Chatflow with ID {chatflow_id} not found")

        # 2. Find all active assignments for the given chatflow
        user_chatflows = await UserChatflow.find(
            UserChatflow.chatflow_id == chatflow_id,
            UserChatflow.is_active == True
        ).to_list()

        if not user_chatflows:
            return []

        # 3. Get the list of external_user_ids from the assignments
        external_user_ids = [uc.external_user_id for uc in user_chatflows]

        # 4. Find the corresponding local user records to get username and email
        local_users = await User.find(User.external_id.in_(external_user_ids)).to_list()
        users_map = {user.external_id: user for user in local_users}

        # 5. Construct the response
        response = []
        for uc in user_chatflows:
            user_info = users_map.get(uc.external_user_id)
            response.append({
                "external_user_id": uc.external_user_id,
                "username": user_info.username if user_info else "N/A",
                "email": user_info.email if user_info else "N/A",
                "assigned_at": uc.assigned_at
            })

        return response

    async def add_user_to_chatflow(self, flowise_id: str, email: str, assigned_by: str) -> Dict[str, Any]:
        """
        Assigns a user to a chatflow.

        Args:
            flowise_id: The ID of the chatflow.
            email: The email of the user to assign.
            assigned_by: The username of the admin performing the assignment.

        Returns:
            A dictionary with the assignment status.
        
        Raises:
            ValueError: If the user or chatflow is not found.
        """
        user = await User.find_one(User.email == email)
        if not user:
            raise ValueError(f"User with email '{email}' not found in local DB. Please sync first.")

        chatflow = await Chatflow.find_one(Chatflow.flowise_id == flowise_id)
        if not chatflow:
            raise ValueError(f"Chatflow with ID '{flowise_id}' not found.")

        # Check if assignment already exists
        existing_assignment = await UserChatflow.find_one(
            UserChatflow.external_user_id == user.external_id,
            UserChatflow.chatflow_id == str(chatflow.id)
        )
        if existing_assignment:
            # This case is handled as a 409 conflict in the API layer, but we can return a specific message.
            return {
                "email": email,
                "status": "already_assigned",
                "message": f"User '{email}' is already assigned to chatflow '{chatflow.name}'"
            }

        new_assignment = UserChatflow(
            external_user_id=user.external_id,
            chatflow_id=str(chatflow.id),
            assigned_by=assigned_by,
            assigned_at=datetime.utcnow()
        )
        await new_assignment.insert()

        return {
            "email": email,
            "status": "assigned",
            "message": f"User '{email}' has been successfully assigned to chatflow '{chatflow.name}'"
        }
