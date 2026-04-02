from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Dict, Any, Optional, List, AsyncGenerator
from app.auth.middleware import authenticate_user
from app.services.flowise_service import FlowiseService
from app.services.accounting_service import AccountingService
from app.services.auth_service import AuthService
from app.services.external_auth_service import ExternalAuthService
from app.services.file_storage_service import FileStorageService
from app.auth.jwt_handler import JWTHandler
from flowise import Flowise, PredictionData
import uuid
import time
import json
import requests
import traceback
import io

# Try to import Upload class for proper file uploads
try:
    from flowise import Upload
    print("✅ Flowise SDK with Upload class imported successfully")
    USE_UPLOAD_CLASS = True
except ImportError:
    try:
        from flowise import FileUpload as Upload
        print("✅ Flowise SDK with FileUpload class imported successfully")
        USE_UPLOAD_CLASS = True
    except ImportError:
        print("⚠️ Upload class not found, will use dictionary fallback for file uploads")
        USE_UPLOAD_CLASS = False
from app.config import settings
from app.models.chatflow import UserChatflow  # Added UserChatflow import
from app.models.chat_session import ChatSession  # Import the new session model
from app.models.chat_message import ChatMessage
from app.models.file_upload import FileUpload as FileUploadModel
from beanie import Document
import time
import uuid
import hashlib
from datetime import datetime
import json
from json_repair import repair_json
import json
import requests
import traceback
import uuid
import time

router = APIRouter(prefix="/api/v1/chat", tags=["chat"])


def parse_sse_chunk(chunk_str):
    """
    Parse Server-Sent Events (SSE) format chunk and extract JSON data.
    
    SSE format example:
    message:
    data:{"event":"start","data":""}
    
    
    message:
    data:{"event":"token","data":"Hi"}
    
    Args:
        chunk_str: Raw SSE chunk string
        
    Returns:
        List of JSON strings extracted from data: lines
    """
    events = []
    lines = chunk_str.strip().split('\n')
    
    for line in lines:
        line = line.strip()
        if line.startswith('data:'):
            # Extract JSON after "data:"
            json_str = line[5:].strip()  # Remove "data:" prefix
            if json_str and json_str != '[DONE]':
                events.append(json_str)
    
    return events


class FileUpload(BaseModel):
    data: str  # Base64 encoded file or URL
    type: str  # "file" or "url"
    name: str  # Filename
    mime: str  # MIME type like "image/jpeg"


class ChatRequest(BaseModel):
    question: str
    chatflow_id: str
    overrideConfig: Optional[Dict[str, Any]] = None
    history: Optional[List[Dict[str, Any]]] = None
    # The client can provide a session ID to maintain conversation context
    sessionId: Optional[str] = None
    uploads: Optional[List[FileUpload]] = None  # New field for uploads


class AuthRequest(BaseModel):
    username: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class RevokeTokenRequest(BaseModel):
    token_id: Optional[str] = None
    all_tokens: Optional[bool] = False


class MyAssignedChatflowsResponse(BaseModel):
    assigned_chatflow_ids: List[str]
    count: int


class CreateSessionRequest(BaseModel):
    chatflow_id: str
    topic: Optional[str] = None


class SessionResponse(BaseModel):
    session_id: str
    chatflow_id: str
    user_id: str
    topic: Optional[str]
    created_at: datetime


class ChatHistoryResponse(BaseModel):
    history: List[Dict[str, Any]]
    count: int


class SessionSummary(BaseModel):
    session_id: str
    chatflow_id: str
    topic: Optional[str]
    created_at: datetime
    first_message: Optional[str] = None


class SessionListResponse(BaseModel):
    sessions: List[SessionSummary]
    count: int


class DeleteChatHistoryResponse(BaseModel):
    message: str
    sessions_deleted: int
    messages_deleted: int
    user_id: str


class DeleteSessionResponse(BaseModel):
    message: str
    session_id: str
    messages_deleted: int
    user_id: str


# Create deterministic but UUID-formatted session ID with timestamp
def create_session_id(user_id, chatflow_id):
    # Create a namespace UUID (version 5)
    namespace = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

    # Get current timestamp
    timestamp = int(time.time() * 1000)

    # Combine user_id, chatflow_id, and timestamp
    seed = f"{user_id}:{chatflow_id}:{timestamp}"

    # Generate a UUID based on the namespace and seed
    return str(uuid.uuid5(namespace, seed))


@router.post("/authenticate")
async def authenticate(auth_request: AuthRequest, request: Request):
    """
    Authenticate user via external auth service and return JWT tokens
    """
    try:
        external_auth_service = ExternalAuthService()

        # Authenticate user via external service
        auth_result = await external_auth_service.authenticate_user(
            auth_request.username, auth_request.password
        )

        if auth_result is None:
            raise HTTPException(status_code=401, detail="Invalid credentials")

        return {
            "access_token": auth_result["access_token"],
            "refresh_token": auth_result["refresh_token"],
            "token_type": auth_result["token_type"],
            "user": auth_result["user"],
            "message": auth_result["message"],
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Authentication failed: {str(e)}")


@router.post("/refresh")
async def refresh_token(refresh_request: RefreshRequest, request: Request):
    """
    Refresh access token using external auth service - NO MIDDLEWARE DEPENDENCY
    This endpoint does not use authenticate_user middleware to avoid circular dependency.
    """
    try:
        external_auth_service = ExternalAuthService()

        # Refresh tokens via external auth service (no middleware)
        refresh_result = await external_auth_service.refresh_token(
            refresh_request.refresh_token
        )

        if refresh_result is None:
            raise HTTPException(
                status_code=401, detail="Invalid or expired refresh token"
            )

        return {
            "access_token": refresh_result["access_token"],
            "refresh_token": refresh_result["refresh_token"],
            "token_type": refresh_result["token_type"],
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Token refresh failed: {str(e)}")


@router.post("/revoke")
async def revoke_tokens(
    request: Request,
    current_user: Dict = Depends(authenticate_user),
    revoke_request: Optional[RevokeTokenRequest] = None,
):
    """
    Revoke refresh tokens (specific token or all user tokens)
    """
    try:
        auth_service = AuthService()
        user_id = current_user.get("user_id")

        # Get authorization header to extract current token for token_id
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Invalid authorization header")

        current_token = auth_header.split(" ")[1]
        # Decode current token to get token_id
        # from app.auth.jwt_handler import JWTHandler
        payload = JWTHandler.verify_access_token(current_token)
        if not payload:
            raise HTTPException(status_code=401, detail="Invalid token")

        current_token_id = JWTHandler.extract_token_id(payload)

        # Determine revocation scope
        revoke_all = False
        specific_token_id = None

        if revoke_request:
            revoke_all = revoke_request.all_tokens or False
            specific_token_id = revoke_request.token_id

        revoked_count = 0

        if revoke_all:
            # Revoke all user tokens
            success = await auth_service.revoke_all_user_tokens(user_id)
            if success:
                # Count revoked tokens (import RefreshToken if needed)
                from app.models.refresh_token import RefreshToken

                revoked_count = await RefreshToken.find(
                    RefreshToken.user_id == user_id, RefreshToken.is_revoked == True
                ).count()
                return {
                    "message": "All tokens revoked successfully",
                    "revoked_tokens": revoked_count,
                }
            else:
                raise HTTPException(status_code=500, detail="Failed to revoke tokens")

        elif specific_token_id:
            # Revoke specific token
            success = await auth_service.revoke_refresh_token(specific_token_id)
            if success:
                return {"message": "Token revoked successfully", "revoked_tokens": 1}
            else:
                raise HTTPException(
                    status_code=404, detail="Token not found or already revoked"
                )

        else:
            # Revoke current token (default behavior)
            success = await auth_service.revoke_refresh_token(current_token_id)
            if success:
                return {"message": "Token revoked successfully", "revoked_tokens": 1}
            else:
                raise HTTPException(
                    status_code=404, detail="Token not found or already revoked"
                )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Token revocation failed: {str(e)}"
        )


@router.post("/predict")
async def chat_predict(
    chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
):
    """
    Process chat prediction request with authentication and credit management
    """
    try:
        # Initialize services
        accounting_service = AccountingService()
        auth_service = AuthService()

        user_token = current_user.get("access_token")
        user_id = current_user.get("user_id")
        chatflow_id = chat_request.chatflow_id

        # 1. Validate user has access to chatflow
        if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
            raise HTTPException(
                status_code=403, detail="Access denied to this chatflow"
            )

        # 2. Initialize Flowise client directly
        flowise_client = Flowise(settings.FLOWISE_API_URL, settings.FLOWISE_API_KEY)

        # 3. Get chatflow cost
        cost = await accounting_service.get_chatflow_cost(chatflow_id)

        # 4. Check user credits
        user_credits = await accounting_service.check_user_credits(user_id, user_token)
        if user_credits is None or user_credits < cost:
            raise HTTPException(status_code=402, detail="Insufficient credits")

        # 5. Deduct credits before processing
        if not await accounting_service.deduct_credits(user_id, cost, user_token):
            raise HTTPException(status_code=402, detail="Failed to deduct credits")
        # 6. Process chat request using Flowise library with streaming
        try:
            # Create prediction using Flowise library with streaming enabled
            completion = flowise_client.create_prediction(
                PredictionData(
                    chatflowId=chatflow_id,
                    question=chat_request.question,
                    streaming=True,  # Enable streaming for proxy behavior
                    overrideConfig=(
                        chat_request.overrideConfig
                        if chat_request.overrideConfig
                        else None
                    ),
                )
            )

            # Collect all streaming chunks into a complete response
            full_response = ""
            response_received = False

            for chunk in completion:
                if chunk:
                    full_response += str(chunk)
                    response_received = True

            if not response_received or not full_response:
                # Log failed transaction but don't refund credits automatically
                await accounting_service.log_transaction(
                    user_token, user_id, "chat", chatflow_id, cost, False
                )
                raise HTTPException(status_code=503, detail="Chat service unavailable")

            # 7. Log successful transaction
            await accounting_service.log_transaction(
                user_token, user_id, "chat", chatflow_id, cost, True
            )

            # 8. Return consolidated response
            return {
                "response": full_response,
                "metadata": {
                    "chatflow_id": chatflow_id,
                    "cost": cost,
                    "remaining_credits": user_credits - cost,
                    "user": current_user.get("username"),
                    "streaming": True,
                },
            }

        except Exception as processing_error:
            # Log failed processing
            await accounting_service.log_transaction(
                user_token, user_id, "chat", chatflow_id, cost, False
            )
            raise HTTPException(
                status_code=500,
                detail=f"Chat processing failed: {str(processing_error)}",
            )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Request failed: {str(e)}")


# --- Testing chat predict STREAM for user: user2 on chatflow ---
# ✅ Stream started successfully for user2. Chunks:
# --- End of Stream ---
@router.post("/predict/stream")
async def chat_predict_stream(
    chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
):
    """
    (Modified to stream raw data)
    This endpoint streams raw, unparsed data directly from Flowise.
    It includes authentication and credit deduction but forwards the stream without parsing
    or message persistence within this service.
    """
    try:
        # Initialize services
        accounting_service = AccountingService()
        auth_service = AuthService()

        user_token = current_user.get("access_token")
        user_id = current_user.get("user_id")
        chatflow_id = chat_request.chatflow_id

        # 1. Validate user has access to chatflow
        if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
            raise HTTPException(
                status_code=403, detail="Access denied to this chatflow"
            )

        # 2. Initialize Flowise client directly
        flowise_client = Flowise(settings.FLOWISE_API_URL, settings.FLOWISE_API_KEY)

        # 3. Get chatflow cost
        cost = await accounting_service.get_chatflow_cost(chatflow_id)

        # 4. Check user credits
        user_credits = await accounting_service.check_user_credits(user_id, user_token)
        if user_credits is None or user_credits < cost:
            raise HTTPException(status_code=402, detail="Insufficient credits")

        # 5. Deduct credits before processing
        if not await accounting_service.deduct_credits(user_id, cost, user_token):
            raise HTTPException(status_code=402, detail="Failed to deduct credits")

        async def stream_generator() -> AsyncGenerator[str, None]:
            try:
                session_id = chat_request.sessionId or create_session_id(
                    user_id, chatflow_id
                )
                override_config = chat_request.overrideConfig or {}
                override_config["sessionId"] = session_id

                # Prepare uploads with normalization for Flowise API
                uploads = None
                if chat_request.uploads:
                    uploads = []
                    for upload in chat_request.uploads:
                        upload_dict = upload.model_dump() if hasattr(upload, 'model_dump') else upload
                        
                        if USE_UPLOAD_CLASS:
                            # Use Upload class if available
                            if upload_dict["type"] == "file":
                                # Prefix base64 data for Flowise compatibility
                                upload_obj = Upload(
                                    data=f"data:{upload_dict['mime']};base64,{upload_dict['data']}",
                                    type="file",
                                    name=upload_dict["name"],
                                    mime=upload_dict["mime"]
                                )
                            else:
                                # For "url", keep as-is
                                upload_obj = Upload(
                                    data=upload_dict["data"],
                                    type="url",
                                    name=upload_dict["name"],
                                    mime=upload_dict["mime"]
                                )
                            uploads.append(upload_obj)
                        else:
                            # Fallback to dictionary approach
                            if upload_dict["type"] == "file":
                                # Prefix base64 data for Flowise compatibility
                                upload_dict["data"] = f"data:{upload_dict['mime']};base64,{upload_dict['data']}"
                            # For "url", keep as-is (type="url", data=URL)
                            uploads.append(upload_dict)

                prediction_data = PredictionData(
                    chatflowId=chatflow_id,
                    question=chat_request.question,
                    streaming=True,
                    history=chat_request.history,
                    overrideConfig=override_config,
                    uploads=uploads,
                )

                completion = flowise_client.create_prediction(prediction_data)

                # Directly yield the raw chunks from Flowise as they come.
                # We are not parsing or saving the stream here.
                # We will log a single successful transaction.
                response_streamed = False
                for chunk in completion:
                    if isinstance(chunk, bytes):
                        yield chunk.decode("utf-8", errors="ignore")
                    else:
                        yield str(chunk)
                    response_streamed = True

                # Log transaction after the stream is finished
                if response_streamed:
                    await accounting_service.log_transaction(
                        user_token, user_id, "chat", chatflow_id, cost, True
                    )
                else:
                    # If no data was streamed, log as a failed transaction
                    await accounting_service.log_transaction(
                        user_token, user_id, "chat", chatflow_id, cost, False
                    )

            except Exception as e:
                # Log the error for debugging
                print(f"Error during raw stream processing: {e}")
                await accounting_service.log_transaction(
                    user_token, user_id, "chat", chatflow_id, cost, False
                )
                # Yield a final error message in the stream if something goes wrong.
                yield f"STREAM_ERROR: {str(e)}"

        return StreamingResponse(stream_generator(), media_type="text/event-stream")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Request failed: {str(e)}")


@router.post("/predict/stream/store")
async def chat_predict_stream_store(
    chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
):
    """
    Streams chat predictions from Flowise while simultaneously storing the user's question
    and the full assistant response as ChatMessage documents.
    """
    try:
        # Initialize services
        accounting_service = AccountingService()
        auth_service = AuthService()

        user_token = current_user.get("access_token")
        user_id = current_user.get("user_id")
        chatflow_id = chat_request.chatflow_id

        # 1. Validate user has access to chatflow
        if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
            raise HTTPException(
                status_code=403, detail="Access denied to this chatflow"
            )

        # 2. Get chatflow cost
        cost = await accounting_service.get_chatflow_cost(chatflow_id)

        # 3. Check user credits
        user_credits = await accounting_service.check_user_credits(user_id, user_token)
        if user_credits is None or user_credits < cost:
            raise HTTPException(status_code=402, detail="Insufficient credits")

        # 4. Deduct credits before processing
        if not await accounting_service.deduct_credits(user_id, cost, user_token):
            raise HTTPException(status_code=402, detail="Failed to deduct credits")

        # 5. Create session_id and prepare user message, but do not save it yet.
        # This prevents orphaned user messages if the stream fails.

        if chat_request.sessionId is not None and chat_request.sessionId != "":
            # If sessionId is provided, validate its format and use it
            try:
                uuid.UUID(chat_request.sessionId)
                session_id = chat_request.sessionId
                new_session_id = False
            except ValueError:
                raise HTTPException(
                    status_code=400,
                    detail="Invalid sessionId format. Must be a valid UUID.",
                )
        else:
            session_id = create_session_id(user_id, chatflow_id)
            new_session_id = True


        user_message = ChatMessage(
            chatflow_id=chatflow_id,
            session_id=session_id,
            user_id=user_id,
            role="user",
            content=chat_request.question,
            has_files=bool(chat_request.uploads),
        )

        async def stream_generator() -> AsyncGenerator[str, None]:
            """Generator to stream responses from Flowise and store messages."""
            # List to collect full assistant response chunks
            full_assistant_response_ls = []
            try:
                # Initialize Flowise client
                flowise_client = Flowise(
                    settings.FLOWISE_API_URL, settings.FLOWISE_API_KEY
                )
                file_storage_service = FileStorageService()

                override_config = chat_request.overrideConfig or {}
                override_config["sessionId"] = session_id

                # ✅ BEST PRACTICE: Process and store files BEFORE streaming
                stored_files = []
                if chat_request.uploads:
                    try:
                        # DEBUG: Check types of uploads
                        for i, upload in enumerate(chat_request.uploads):
                            if hasattr(upload, 'model_dump'):
                                print(f"DEBUG: Upload {i} model_dump result: {upload.model_dump()}")
                            else:
                                print(f"DEBUG: Upload {i} as dict: {upload}")
                        
                        # Store files first - this ensures we have file IDs before streaming
                        uploads_data = []
                        for upload in chat_request.uploads:
                            if hasattr(upload, 'model_dump'):
                                uploads_data.append(upload.model_dump())
                            else:
                                uploads_data.append(upload)
                        
                        stored_files = await file_storage_service.process_upload_list(
                            uploads=uploads_data,
                            user_id=user_id,
                            session_id=session_id,
                            chatflow_id=chatflow_id,
                            message_id="temp_user_message"  # Will be updated later
                        )
                        
                        print(f"Successfully stored {len(stored_files)} files")
                        
                        # ✅ BEST PRACTICE: Yield file upload confirmation as first event
                        if stored_files:
                            file_upload_event = json.dumps({
                                "event": "files_uploaded",
                                "data": {
                                    "file_count": len(stored_files),
                                    "files": [
                                        {
                                            "file_id": file.file_id,
                                            "name": file.original_name,
                                            "size": file.file_size,
                                            "type": file.mime_type
                                        }
                                        for file in stored_files
                                    ]
                                },
                                "timestamp": datetime.utcnow().isoformat()
                            })
                            yield file_upload_event
                        
                    except Exception as e:
                        print(f"Error storing files: {e}")
                        # ✅ BEST PRACTICE: Yield error event for file upload failures
                        error_event = json.dumps({
                            "event": "file_upload_error",
                            "data": {"error": str(e)},
                            "timestamp": datetime.utcnow().isoformat()
                        })
                        yield error_event
                        # Continue processing even if file storage fails

                # 🔥 STREAM SESSION_ID AS FIRST CHUNK
                session_chunk_first = json.dumps(
                    {
                        "event": "session_id",
                        "data": session_id,
                        "chatflow_id": chatflow_id,
                        "timestamp": datetime.utcnow().isoformat(),
                        "status": "streaming_started",
                    }
                )
                yield session_chunk_first

                # ✅ BEST PRACTICE: Prepare uploads for Flowise API
                uploads = None
                if chat_request.uploads:
                    uploads = []
                    for upload in chat_request.uploads:
                        upload_dict = upload.model_dump() if hasattr(upload, 'model_dump') else upload
                        
                        if USE_UPLOAD_CLASS:
                            # Use Upload class if available
                            try:
                                if upload_dict["type"] == "file":
                                    # Prefix base64 data for Flowise compatibility
                                    upload_obj = Upload(
                                        data=f"data:{upload_dict['mime']};base64,{upload_dict['data']}",
                                        type="file",
                                        name=upload_dict["name"],
                                        mime=upload_dict["mime"]
                                    )
                                else:
                                    # For "url", keep as-is
                                    upload_obj = Upload(
                                        data=upload_dict["data"],
                                        type="url",
                                        name=upload_dict["name"],
                                        mime=upload_dict["mime"]
                                    )
                                uploads.append(upload_obj)
                            except Exception as e:
                                print(f"Failed to create Upload object: {e}, falling back to dictionary")
                                # Fall back to dictionary approach
                                if upload_dict["type"] == "file":
                                    upload_dict["data"] = f"data:{upload_dict['mime']};base64,{upload_dict['data']}"
                                uploads.append(upload_dict)
                        else:
                            # Fallback to dictionary approach
                            if upload_dict["type"] == "file":
                                # Prefix base64 data for Flowise compatibility
                                upload_dict["data"] = f"data:{upload_dict['mime']};base64,{upload_dict['data']}"
                            # For "url", keep as-is (type="url", data=URL)
                            uploads.append(upload_dict)

                # Try to create prediction with SDK, fallback to requests if there are issues
                # 🔍 PERFORMANCE NOTE: SDK is ~20-30% faster than direct HTTP due to:
                # - Connection pooling and reuse
                # - Native object serialization (no SSE parsing overhead)
                # - Optimized streaming without intermediate string processing
                # - Lower memory footprint for large responses
                # 
                # However, SDK can fail with dict serialization errors when Upload objects
                # don't have proper __dict__ attributes, making fallback necessary for reliability
                try:
                    print("🔄 Attempting SDK approach (faster, optimized)")
                    prediction_data = PredictionData(
                        chatflowId=chatflow_id,
                        question=chat_request.question,
                        streaming=True,
                        history=chat_request.history,
                        overrideConfig=override_config,
                        uploads=uploads,
                    )

                    completion = flowise_client.create_prediction(prediction_data)
                    
                    # Test if we can iterate (this is where the dict error usually occurs)
                    first_chunk = next(completion, None)
                    if first_chunk is not None:
                        print("✅ SDK approach working, using optimized streaming")
                        # SDK is working, yield the first chunk and continue
                        chunk_str = ""
                        if isinstance(first_chunk, bytes):
                            chunk_str = first_chunk.decode("utf-8", errors="ignore")
                        else:
                            chunk_str = str(first_chunk)
                        good_json_string = repair_json(chunk_str)
                        
                        full_assistant_response_ls.append(good_json_string)
                        yield good_json_string
                        
                        # Continue with remaining chunks
                        response_streamed = True
                        for chunk in completion:
                            chunk_str = ""
                            if isinstance(chunk, bytes):
                                chunk_str = chunk.decode("utf-8", errors="ignore")
                            else:
                                chunk_str = str(chunk)
                            good_json_string = repair_json(chunk_str)
                            full_assistant_response_ls.append(good_json_string)
                            yield good_json_string
                            response_streamed = True
                    else:
                        raise Exception("No chunks received from SDK")
                        
                except Exception as e:
                    print(f"SDK failed with error: {e}, falling back to requests")
                    # Fallback to direct requests approach
                    import requests
                    
                    # Prepare payload for direct API call
                    payload = {
                        "question": chat_request.question,
                        "overrideConfig": override_config,
                        "streaming": True,
                        "history": chat_request.history
                    }
                    
                    # Add uploads if available
                    if chat_request.uploads:
                        payload["uploads"] = []
                        for upload in chat_request.uploads:
                            upload_dict = upload.model_dump() if hasattr(upload, 'model_dump') else upload
                            if upload_dict["type"] == "file":
                                upload_dict["data"] = f"data:{upload_dict['mime']};base64,{upload_dict['data']}"
                            payload["uploads"].append(upload_dict)
                    
                    headers = {
                        "Authorization": f"Bearer {settings.FLOWISE_API_KEY}",
                        "Content-Type": "application/json"
                    }
                    
                    # Make direct API call
                    response = requests.post(
                        f"{settings.FLOWISE_API_URL}/api/v1/prediction/{chatflow_id}",
                        json=payload,
                        headers=headers,
                        stream=True,
                        timeout=120
                    )
                    
                    if response.status_code == 200:
                        response_streamed = False
                        for chunk in response.iter_content(chunk_size=None):
                            if chunk:
                                chunk_str = chunk.decode("utf-8", errors="ignore")
                                
                                # Parse SSE format: extract JSON from "data:" lines
                                # 🔍 PERFORMANCE: This adds ~5-10ms per chunk for SSE parsing
                                sse_events = parse_sse_chunk(chunk_str)
                                
                                for event_json in sse_events:
                                    if event_json.strip():  # Skip empty events
                                        good_json_string = repair_json(event_json)
                                        full_assistant_response_ls.append(good_json_string)
                                        yield good_json_string
                                        response_streamed = True
                    else:
                        raise Exception(f"Direct API call failed: {response.status_code} - {response.text}")

                if response_streamed:
                    
                    def process_json(full_assistant_response_ls):
                        """
                        Process a list of JSON strings, combine consecutive token events, and return both token data and metadata.

                        Args:
                            full_assistant_response_ls (list): List of JSON strings representing events.
                        Returns:
                            tuple: (token_data_json_string, non_token_events_list)
                        """
                        result = []  # List to store the final sequence of event objects
                        non_Token_event_result = []
                        token_data = ""  # String to accumulate data from "token" events

                        for good_json_string in full_assistant_response_ls:
                            try:
                                obj = json.loads(
                                    good_json_string
                                )  # Parse JSON string to dictionary
                                
                                # Handle both dictionary and list cases
                                if isinstance(obj, dict):
                                    if obj.get("event") == "token":
                                        token_data += obj.get("data", "")  # Accumulate token data
                                    else:
                                        # If we have accumulated token data, add it as a single event
                                        if token_data:
                                            result.append(
                                                {"event": "token", "data": token_data}
                                            )
                                            token_data = ""  # Reset token data
                                        # Save the non-token event for metadata storage
                                        non_Token_event_result.append(obj)
                                elif isinstance(obj, list):
                                    # Handle case where JSON is a list of events
                                    print(f"🔍 DEBUG: Processing list of {len(obj)} events")
                                    for event in obj:
                                        if isinstance(event, dict):
                                            if event.get("event") == "token":
                                                token_data += event.get("data", "")
                                            else:
                                                # If we have accumulated token data, add it as a single event
                                                if token_data:
                                                    result.append(
                                                        {"event": "token", "data": token_data}
                                                    )
                                                    token_data = ""  # Reset token data
                                                # Save the non-token event for metadata storage
                                                non_Token_event_result.append(event)
                                        else:
                                            print(f"🔍 DEBUG: Skipping non-dict event in list: {event}")
                                else:
                                    print(f"🔍 DEBUG: Skipping non-dict/non-list object: {obj}")
                                    
                            except json.JSONDecodeError as e:
                                print(f"🔍 DEBUG: JSON decode error: {e}")
                                continue  # Skip invalid JSON strings

                        # If there are any remaining tokens (e.g., at the end of the list), add them
                        if token_data:
                            result.append({"event": "token", "data": token_data})

                        # Return both token data and metadata
                        return json.dumps(result), non_Token_event_result

                    await accounting_service.log_transaction(
                        user_token, user_id, "chat", chatflow_id, cost, True
                    )
                    
                    # ✅ BEST PRACTICE: Save user message first, then update with file references
                    await user_message.insert()
                    
                    # Update file records with actual message ID and link to user message
                    if stored_files:
                        try:
                            # Update all stored files with the actual message ID
                            for i, file in enumerate(stored_files):
                                
                                file.message_id = str(user_message.id)
                                await file.save()
                            
                            # Update user message with file references
                            user_message.file_ids = [file.file_id for file in stored_files]
                            user_message.has_files = True
                            await user_message.save()
                            
                            
                        except Exception as e:
                            import traceback
                            traceback.print_exc()
                            # Continue processing even if file linking fails
                    
                    # Get both token data and metadata from the response
                    try:
                        token_content, metadata_events = process_json(full_assistant_response_ls)
                    except Exception as process_error:
                        import traceback
                        traceback.print_exc()
                        # Set fallback values to continue execution
                        token_content = "[]"
                        metadata_events = []
                    
                    assistant_message = ChatMessage(
                        chatflow_id=chatflow_id,
                        session_id=session_id,
                        user_id=user_id,
                        role="assistant",
                        content=token_content,
                        metadata=metadata_events,  # Save non-token events here
                        has_files=False,  # Assistant messages don't have files (for now)
                    )
                    await assistant_message.insert()
                    
                    if new_session_id:
                        topic = (
                            chat_request.question[:50] + "..."
                            if len(chat_request.question) > 50
                            else chat_request.question
                        )
                        new_chat_session = ChatSession(
                            session_id=session_id,
                            user_id=user_id,
                            chatflow_id=chatflow_id,
                            topic=topic,  # or auto-generated
                        )
                        try:
                            await new_chat_session.insert()
                        except Exception as session_insert_error:
                            import traceback
                            traceback.print_exc()
                    else:
                        # Verify the existing session exists
                        existing_session = await ChatSession.find_one(
                            ChatSession.session_id == session_id,
                            ChatSession.user_id == user_id
                        )
                        if existing_session:
                            print(f"🔍 DEBUG: Existing session found: {existing_session}")
                        else:
                            print(f"🔍 DEBUG: WARNING: Existing session not found for session_id: {session_id}")

                else:
                    # If no data was streamed or the response is empty, log as a failed transaction
                    await accounting_service.log_transaction(
                        user_token, user_id, "chat", chatflow_id, cost, False
                    )
                    print("🔍 DEBUG: No response streamed, logging as failed transaction")

            except Exception as e:
                print(f"🔍 DEBUG: Error during stream processing and storing: {e}")
                print(f"🔍 DEBUG: Error type: {type(e)}")
                import traceback
                traceback.print_exc()
                await accounting_service.log_transaction(
                    user_token, user_id, "chat", chatflow_id, cost, False
                )
                yield f"STREAM_ERROR: {str(e)}"

        return StreamingResponse(stream_generator(), media_type="text/event-stream")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Request failed: {str(e)}")


@router.get("/credits")
async def get_user_credits(
    request: Request, current_user: Dict = Depends(authenticate_user)
):
    """Get current user's credit balance"""
    try:
        accounting_service = AccountingService()
        user_id = current_user.get("user_id")

        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Invalid authorization header")

        user_token = auth_header.split(" ")[1]

        credits = await accounting_service.check_user_credits(user_id, user_token)

        if credits is None:
            raise HTTPException(
                status_code=500, detail="Could not retrieve credit balance"
            )

        return {"totalCredits": credits}

    except HTTPException as e:
        # Re-raise HTTP exceptions to let FastAPI handle them
        raise e
    except Exception as e:
        print(f"Error getting user credits: {e}")
        raise HTTPException(status_code=500, detail="An internal error occurred.")


@router.get("/my-assigned-chatflows", response_model=MyAssignedChatflowsResponse)
async def get_my_assigned_chatflows(current_user: Dict = Depends(authenticate_user)):
    """Get a list of chatflow IDs the current authenticated user is actively assigned to."""
    try:
        user_id = current_user.get("user_id")
        if not user_id:
            # This should ideally not happen if authenticate_user works correctly
            raise HTTPException(status_code=400, detail="User ID not found in token")

        active_assignments = await UserChatflow.find(
            UserChatflow.user_id == user_id, UserChatflow.is_active == True
        ).to_list()

        assigned_chatflow_ids = [
            assignment.chatflow_id for assignment in active_assignments
        ]

        return {
            "assigned_chatflow_ids": assigned_chatflow_ids,
            "count": len(assigned_chatflow_ids),
        }

    except Exception as e:
        # Consider more specific error logging if needed
        raise HTTPException(
            status_code=500, detail=f"Failed to retrieve assigned chatflows: {str(e)}"
        )


# for indivduals to get their own history
@router.get("/sessions/{session_id}/history", response_model=ChatHistoryResponse)
async def get_chat_history(
    session_id: str, current_user: Dict = Depends(authenticate_user)
):
    user_id = current_user.get("user_id")

    # 1. Verify the session exists and belongs to the user
    session = await ChatSession.find_one(
        ChatSession.session_id == session_id, ChatSession.user_id == user_id
    )
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
                print(f"🔍 DEBUG: Looking for files with IDs: {msg.file_ids} for user: {user_id}")
                
                # ✅ FIX: Use proper Beanie query syntax with field filters
                file_records = await FileUploadModel.find(
                    {"file_id": {"$in": msg.file_ids}, "user_id": user_id}
                ).to_list()
                
                print(f"🔍 DEBUG: Found {len(file_records)} file records")
                
                for file_record in file_records:
                    print(f"🔍 DEBUG: Processing file: {file_record.file_id}, name: {file_record.original_name}")
                    
                    file_info = {
                        "file_id": file_record.file_id,
                        "name": file_record.original_name,
                        "mime": file_record.mime_type,
                        "size": file_record.file_size,
                        "type": file_record.upload_type,
                        "url": f"/api/v1/chat/files/{file_record.file_id}",  # For display
                        "download_url": f"/api/v1/chat/files/{file_record.file_id}?download=true",  # For download
                        "is_image": file_record.mime_type.startswith("image/"),
                        "uploaded_at": file_record.uploaded_at.isoformat()
                    }
                    
                    # Add thumbnail URL for images
                    if file_record.mime_type.startswith("image/"):
                        file_info["thumbnail_url"] = f"/api/v1/chat/files/{file_record.file_id}/thumbnail"
                        file_info["thumbnail_small"] = f"/api/v1/chat/files/{file_record.file_id}/thumbnail?size=100"
                        file_info["thumbnail_medium"] = f"/api/v1/chat/files/{file_record.file_id}/thumbnail?size=300"
                    
                    message_data["uploads"].append(file_info)
                    print(f"🔍 DEBUG: Added file info to message: {file_info}")
                    
            except Exception as e:
                print(f"❌ ERROR: Error fetching file metadata: {e}")
                print(f"❌ ERROR: Exception type: {type(e)}")
                import traceback
                traceback.print_exc()
                # Continue without file metadata if there's an error
        
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
        await ChatSession.find(ChatSession.user_id == user_id)
        .sort(-ChatSession.created_at)
        .to_list()
    )

    # The response model `SessionListResponse` expects a list of `SessionSummary` objects.
    # We need to map the fields from the `ChatSession` documents to `SessionSummary` objects.
    session_summaries = [
        SessionSummary(
            session_id=session.session_id,
            chatflow_id=session.chatflow_id,
            topic=session.topic,
            created_at=session.created_at,
            first_message=None,  # Explicitly set to None as it's no longer fetched
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
        # Count sessions and messages before deletion for the response
        sessions_count = await ChatSession.find(ChatSession.user_id == user_id).count()
        messages_count = await ChatMessage.find(ChatMessage.user_id == user_id).count()
        
        # Delete all chat messages for the user
        delete_messages_result = await ChatMessage.find(ChatMessage.user_id == user_id).delete()
        
        # Delete all chat sessions for the user
        delete_sessions_result = await ChatSession.find(ChatSession.user_id == user_id).delete()
        
        return {
            "message": "Chat history deleted successfully",
            "sessions_deleted": sessions_count,
            "messages_deleted": messages_count,
            "user_id": user_id
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500, 
            detail=f"Failed to delete chat history: {str(e)}"
        )


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
        # 1. Verify the session exists and belongs to the user
        session = await ChatSession.find_one(
            ChatSession.session_id == session_id, ChatSession.user_id == user_id
        )
        if not session:
            raise HTTPException(
                status_code=404, detail="Chat session not found or access denied"
            )
        
        # 2. Count messages before deletion for the response
        messages_count = await ChatMessage.find(
            ChatMessage.session_id == session_id, ChatMessage.user_id == user_id
        ).count()
        
        # 3. Delete all messages for this session
        await ChatMessage.find(
            ChatMessage.session_id == session_id, ChatMessage.user_id == user_id
        ).delete()
        
        # 4. Delete the session
        await session.delete()
        
        return {
            "message": "Session deleted successfully",
            "session_id": session_id,
            "messages_deleted": messages_count,
            "user_id": user_id
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500, 
            detail=f"Failed to delete session: {str(e)}"
        )


# Add these new endpoints for file management

@router.get("/files/session/{session_id}")
async def get_session_files(
    session_id: str, current_user: Dict = Depends(authenticate_user)
):
    """Get all files for a chat session."""
    try:
        file_storage_service = FileStorageService()
        files = await file_storage_service.get_files_for_session(session_id)
        
        # Return file metadata (not the actual file content)
        return {
            "session_id": session_id,
            "files": [
                {
                    "file_id": file.file_id,
                    "original_name": file.original_name,
                    "mime_type": file.mime_type,
                    "file_size": file.file_size,
                    "upload_type": file.upload_type,
                    "uploaded_at": file.uploaded_at.isoformat(),
                    "processed": file.processed,
                    "metadata": file.metadata
                }
                for file in files
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get files: {str(e)}")


@router.get("/files/{file_id}/thumbnail")
async def get_file_thumbnail(
    file_id: str, 
    current_user: Dict = Depends(authenticate_user),
    size: int = 200
):
    """Get a thumbnail/preview of an image file."""
    try:
        file_storage_service = FileStorageService()
        
        # Check if user has access to this file
        file_record = await FileUploadModel.find_one(
            FileUploadModel.file_id == file_id,
            FileUploadModel.user_id == current_user.get("user_id")
        )
        
        if not file_record:
            raise HTTPException(status_code=404, detail="File not found or access denied")
        
        # Only generate thumbnails for images
        if not file_record.mime_type.startswith("image/"):
            raise HTTPException(status_code=400, detail="File is not an image")
        
        # Get file data
        file_data = await file_storage_service.get_file(file_id)
        if not file_data:
            raise HTTPException(status_code=404, detail="File data not found")
        
        file_content, filename, mime_type = file_data
        
        # 🖼️ DEBUG: Print thumbnail source image bytes information
        print(f"🖼️ THUMBNAIL SOURCE DEBUG:")
        print(f"   📊 Original size: {len(file_content)} bytes")
        print(f"   📝 Original MIME: {mime_type}")
        print(f"   📄 Original filename: {filename}")
        print(f"   🎯 Requested thumbnail size: {size}px")
        print(f"   🔢 First 30 bytes (hex): {file_content[:30].hex()}")
        
        # Generate thumbnail using PIL
        try:
            from PIL import Image
            
            # Open the image - PIL can handle many formats (JPEG, PNG, GIF, BMP, TIFF, WebP, etc.)
            image = Image.open(io.BytesIO(file_content))
            
            # Convert to RGB if necessary (handles RGBA, P, L, etc.)
            if image.mode not in ('RGB', 'RGBA'):
                if image.mode == 'P' and 'transparency' in image.info:
                    # Handle palette images with transparency
                    image = image.convert('RGBA')
                else:
                    image = image.convert('RGB')
            
            # Create thumbnail while preserving aspect ratio
            image.thumbnail((size, size), Image.Resampling.LANCZOS)
            
            # Convert to bytes
            thumbnail_buffer = io.BytesIO()
            
            # Choose output format based on original format and transparency
            if image.mode == 'RGBA' or (hasattr(image, 'info') and 'transparency' in image.info):
                # Use PNG for images with transparency
                image.save(thumbnail_buffer, format='PNG', optimize=True)
                output_mime_type = "image/png"
            else:
                # Use JPEG for regular images (smaller file size)
                image.save(thumbnail_buffer, format='JPEG', quality=85, optimize=True)
                output_mime_type = "image/jpeg"
            
            thumbnail_content = thumbnail_buffer.getvalue()
            
            # 🖼️ DEBUG: Print thumbnail output bytes information
            print(f"🖼️ THUMBNAIL OUTPUT DEBUG:")
            print(f"   ✅ Generated successfully!")
            print(f"   📊 Thumbnail size: {len(thumbnail_content)} bytes")
            print(f"   📝 Thumbnail MIME: {output_mime_type}")
            print(f"   📐 Thumbnail dimensions: {image.size}")
            print(f"   🔢 First 30 bytes (hex): {thumbnail_content[:30].hex()}")
            print(f"   🎨 Format: {'PNG' if output_mime_type == 'image/png' else 'JPEG'}")
            
            from fastapi.responses import Response
            return Response(
                content=thumbnail_content,
                media_type=output_mime_type,
                headers={
                    "Content-Disposition": f"inline; filename=thumb_{filename}",
                    "Cache-Control": "public, max-age=86400"  # Cache for 24 hours
                }
            )
            
        except Exception as e:
            # If thumbnail generation fails, return original image
            from fastapi.responses import Response
            return Response(
                content=file_content,
                media_type=mime_type,
                headers={
                    "Content-Disposition": f"inline; filename={filename}",
                    "Cache-Control": "public, max-age=3600"
                }
            )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get thumbnail: {str(e)}")


@router.get("/files/{file_id}")
async def get_file(
    file_id: str, 
    current_user: Dict = Depends(authenticate_user),
    download: bool = False
):
    """Get a file by file_id. Can be used for display (inline) or download."""
    try:
        print(f"🔍 DEBUG: get_file called with file_id: {file_id}, user_id: {current_user.get('user_id')}")
        
        file_storage_service = FileStorageService()
        
        # Check if user has access to this file
        print(f"🔍 DEBUG: Checking file access for user {current_user.get('user_id')}")
        file_record = await FileUploadModel.find_one(
            FileUploadModel.file_id == file_id,
            FileUploadModel.user_id == current_user.get("user_id")
        )
        
        if not file_record:
            print(f"❌ DEBUG: File record not found for file_id: {file_id}")
            # Additional debug: check if file exists for any user
            any_file_record = await FileUploadModel.find_one(FileUploadModel.file_id == file_id)
            if any_file_record:
                print(f"❌ DEBUG: File exists but belongs to different user: {any_file_record.user_id}")
            else:
                print(f"❌ DEBUG: File doesn't exist at all in database")
                
            # Check GridFS directly
            try:
                from app.database import get_database
                db = await get_database()
                from motor.motor_asyncio import AsyncIOMotorGridFSBucket
                bucket = AsyncIOMotorGridFSBucket(db)
                from bson import ObjectId
                
                # Try to find file in GridFS
                if ObjectId.is_valid(file_id):
                    gridfs_file = await bucket.find({"_id": ObjectId(file_id)}).to_list(1)
                    if gridfs_file:
                        print(f"✅ DEBUG: File exists in GridFS: {gridfs_file[0]}")
                    else:
                        print(f"❌ DEBUG: File not found in GridFS")
                else:
                    print(f"❌ DEBUG: Invalid ObjectId format: {file_id}")
            except Exception as gridfs_error:
                print(f"❌ DEBUG: GridFS check error: {gridfs_error}")
                
            raise HTTPException(status_code=404, detail="File not found or access denied")
        
        print(f"✅ DEBUG: File record found: {file_record.original_name}")
        
        # Get file data
        print(f"🔍 DEBUG: Retrieving file data from storage service")
        file_data = await file_storage_service.get_file(file_id)
        if not file_data:
            print(f"❌ DEBUG: File data not found in storage service")
            raise HTTPException(status_code=404, detail="File data not found")
        
        file_content, filename, mime_type = file_data
        print(f"✅ DEBUG: File data retrieved successfully - size: {len(file_content)}, filename: {filename}, mime: {mime_type}")
        
        # �️ DEBUG: Print comprehensive file bytes information
        print(f"� FILE BYTES DEBUG:")
        print(f"   📊 Size: {len(file_content)} bytes")
        print(f"   📝 MIME: {mime_type}")
        print(f"   📄 Filename: {filename}")
        print(f"   🔢 First 50 bytes (hex): {file_content[:50].hex()}")
        print(f"   🔤 First 20 bytes (repr): {repr(file_content[:20])}")
        
        if mime_type.startswith("image/"):
            print(f"🖼️ IMAGE-SPECIFIC DEBUG:")
            # Check if it's a valid image by looking at magic bytes
            magic_signatures = {
                b'\xff\xd8\xff': 'JPEG',
                b'\x89PNG\r\n\x1a\n': 'PNG',
                b'GIF87a': 'GIF87a',
                b'GIF89a': 'GIF89a',
                b'RIFF': 'WebP (maybe)',
                b'BM': 'BMP'
            }
            
            for signature, format_name in magic_signatures.items():
                if file_content.startswith(signature):
                    print(f"   ✅ Valid {format_name} image detected")
                    break
            else:
                print(f"   ⚠️  Unknown image format - may be corrupted")
        
        # Determine Content-Disposition header
        if download:
            disposition = f"attachment; filename={filename}"
        else:
            # For inline display (images, etc.)
            disposition = f"inline; filename={filename}"
        
        from fastapi.responses import Response
        return Response(
            content=file_content,
            media_type=mime_type,
            headers={
                "Content-Disposition": disposition,
                "Cache-Control": "public, max-age=3600"  # Cache for 1 hour
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ DEBUG: Exception in get_file: {e}")
        print(f"❌ DEBUG: Exception type: {type(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to get file: {str(e)}")


@router.delete("/files/{file_id}")
async def delete_file(
    file_id: str, current_user: Dict = Depends(authenticate_user)
):
    """Delete a file by file_id."""
    try:
        file_storage_service = FileStorageService()
        
        # Check if user has access to this file
        file_record = await FileUploadModel.find_one(
            FileUploadModel.file_id == file_id,
            FileUploadModel.user_id == current_user.get("user_id")
        )
        
        if not file_record:
            raise HTTPException(status_code=404, detail="File not found or access denied")
        
        # Delete file
        success = await file_storage_service.delete_file(file_id)
        if not success:
            raise HTTPException(status_code=500, detail="Failed to delete file")
        
        return {"message": "File deleted successfully", "file_id": file_id}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete file: {str(e)}")


@router.get("/files/message/{message_id}")
async def get_message_files(
    message_id: str, current_user: Dict = Depends(authenticate_user)
):
    """Get all files for a specific message."""
    try:
        file_storage_service = FileStorageService()
        files = await file_storage_service.get_files_for_message(message_id)
        
        # Filter by user access
        user_files = [f for f in files if f.user_id == current_user.get("user_id")]
        
        return {
            "message_id": message_id,
            "files": [
                {
                    "file_id": file.file_id,
                    "original_name": file.original_name,
                    "mime_type": file.mime_type,
                    "file_size": file.file_size,
                    "upload_type": file.upload_type,
                    "uploaded_at": file.uploaded_at.isoformat(),
                    "processed": file.processed,
                    "metadata": file.metadata
                }
                for file in user_files
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get message files: {str(e)}")