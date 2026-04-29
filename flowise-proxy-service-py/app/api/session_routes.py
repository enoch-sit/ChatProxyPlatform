from fastapi import APIRouter, Depends, HTTPException, Request
from typing import Dict, List
from app.auth.middleware import authenticate_user, ELEVATED_ROLES
from app.models.chat_session import ChatSession
from app.models.chat_message import ChatMessage
from app.api.chat_models import (
    ChatHistoryResponse,
    SessionListResponse,
    SessionSummary,
    DeleteChatHistoryResponse,
    DeleteSessionResponse,
    MyAssignedChatflowsResponse,
)
from app.models.chatflow import UserChatflow
from app.services.accounting_service import AccountingService

router = APIRouter(prefix="/api/v1/chat", tags=["sessions"])

@router.get("/credits")
async def get_user_credits(
    request: Request, current_user: Dict = Depends(authenticate_user)
):
    """Get current user's credit balance"""
    try:
        accounting_service = AccountingService()
        user_id = current_user.get("user_id")
        user_token = current_user.get("access_token")

        credits = await accounting_service.check_user_credits(user_id, user_token)
        if credits is None:
            raise HTTPException(status_code=404, detail="User credits not found")

        return {"credits": credits}

    except HTTPException as e:
        raise e
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get credits: {str(e)}")


@router.get("/my-assigned-chatflows", response_model=MyAssignedChatflowsResponse)
async def get_my_assigned_chatflows(current_user: Dict = Depends(authenticate_user)):
    """Get a list of chatflow IDs the current authenticated user is actively assigned to."""
    try:
        external_user_id = current_user.get("sub") or current_user.get("external_id") or current_user.get("user_id")

        # Find all assignments for the user
        user_chatflows = await UserChatflow.find({"external_user_id": external_user_id}).to_list()

        assigned_ids = [uc.chatflow_id for uc in user_chatflows]

        return {"assigned_chatflow_ids": assigned_ids, "count": len(assigned_ids)}

    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to retrieve assigned chatflows: {str(e)}"
        )


@router.get("/sessions/{session_id}/history", response_model=ChatHistoryResponse)
async def get_chat_history(
    session_id: str, current_user: Dict = Depends(authenticate_user)
):
    user_id = current_user.get("user_id")
    user_role = current_user.get("role", "")
    is_elevated = user_role in ELEVATED_ROLES

    # 1. Verify the session exists; elevated roles (admin/supervisor/teacher) bypass ownership check
    if is_elevated:
        session = await ChatSession.find_one({"session_id": session_id})
    else:
        session = await ChatSession.find_one({"session_id": session_id, "user_id": user_id})
    if not session:
        raise HTTPException(
            status_code=404, detail="Chat session not found or access denied"
        )

    # 2. Fetch message history for the session
    messages = (
        await ChatMessage.find(ChatMessage.session_id == session_id)
        .sort(ChatMessage.created_at)
        .to_list()
    )

    # 3. Format the response with file metadata
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
            "uploads": []  # Enhanced file information for rendering
        }
        
        # If message has files, fetch file metadata for rendering
        if msg.has_files and msg.file_ids:
            try:
                from app.models.file_upload import FileUpload as FileUploadModel
                
                file_records = await FileUploadModel.find(
                    {"file_id": {"$in": msg.file_ids}, "user_id": user_id}
                ).to_list()
                
                for file_record in file_records:
                    file_info = {
                        "file_id": file_record.file_id,
                        "name": file_record.original_name,
                        "mime": file_record.mime_type,
                        "size": file_record.file_size,
                        "type": file_record.upload_type,
                        "url": f"/api/v1/chat/files/{file_record.file_id}",
                        "download_url": f"/api/v1/chat/files/{file_record.file_id}?download=true",
                        "is_image": file_record.mime_type.startswith("image/"),
                        "uploaded_at": file_record.uploaded_at.isoformat()
                    }
                    
                    if file_record.mime_type.startswith("image/"):
                        file_info["thumbnail_url"] = f"/api/v1/chat/files/{file_record.file_id}/thumbnail"
                    
                    message_data["uploads"].append(file_info)
                    
            except Exception as e:
                # Continue without file metadata if there's an error
                pass
        
        history_list.append(message_data)

    return {"history": history_list, "count": len(history_list)}


@router.get("/sessions", response_model=SessionListResponse)
async def get_all_user_sessions(current_user: Dict = Depends(authenticate_user)):
    """
    Retrieves a summary of all chat sessions for the current user,
    """
    user_id = current_user.get("user_id")

    # Find all sessions for the current user, sorted by creation date.
    sessions = (
        await ChatSession.find({"user_id": user_id})
        .sort(-ChatSession.created_at)
        .to_list()
    )

    session_summaries = [
        SessionSummary(
            session_id=session.session_id,
            chatflow_id=session.chatflow_id,
            topic=session.topic,
            created_at=session.created_at,
            first_message=None,
        )
        for session in sessions
    ]

    return {"sessions": session_summaries, "count": len(session_summaries)}


@router.delete("/history", response_model=DeleteChatHistoryResponse)
async def delete_user_chat_history(current_user: Dict = Depends(authenticate_user)):
    """
    Delete all chat history (sessions and messages) for the authenticated user.
    This is irreversible and will remove all conversation data.
    """
    user_id = current_user.get("user_id")
    
    try:
        # Find all sessions for the user
        sessions_to_delete = await ChatSession.find({"user_id": user_id}).to_list()
        session_ids = [s.session_id for s in sessions_to_delete]
        
        # Delete all messages for these sessions
        messages_deleted_result = await ChatMessage.find(
            ChatMessage.session_id.in_(session_ids)
        ).delete()
        
        # Delete all sessions
        sessions_deleted_result = await ChatSession.find({"user_id": user_id}).delete()
        
        return {
            "message": "All chat history has been deleted.",
            "sessions_deleted": sessions_deleted_result.deleted_count,
            "messages_deleted": messages_deleted_result.deleted_count,
            "user_id": user_id,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete chat history: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to delete chat history: {str(e)}")


@router.delete("/sessions/{session_id}", response_model=DeleteSessionResponse)
async def delete_session(
    session_id: str, current_user: Dict = Depends(authenticate_user)
):
    """
    Delete a specific chat session and all its messages for the authenticated user.
    This is irreversible and will remove all conversation data for this session.
    """
    user_id = current_user.get("user_id")
    
    try:
        # Verify session belongs to the user before deleting
        session = await ChatSession.find_one({"session_id": session_id, "user_id": user_id})
        if not session:
            raise HTTPException(status_code=404, detail="Session not found or access denied")
            
        # Delete all messages for this session
        messages_deleted_result = await ChatMessage.find(
            ChatMessage.session_id == session_id
        ).delete()
        
        # Delete the session itself
        await session.delete()
        
        return {
            "message": f"Session {session_id} and its messages have been deleted.",
            "session_id": session_id,
            "messages_deleted": messages_deleted_result.deleted_count,
            "user_id": user_id,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete session: {str(e)}")
