from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from typing import Dict, Any, Optional, List, AsyncGenerator
from app.auth.middleware import authenticate_user
from app.services.accounting_service import AccountingService
from app.services.auth_service import AuthService
from app.services.file_storage_service import FileStorageService
from flowise import Flowise, PredictionData
import json
import requests
import uuid
from datetime import datetime
from json_repair import repair_json

from app.api.chat_models import ChatRequest
from app.api.utils import parse_sse_chunk, create_session_id
from app.config import settings
from app.models.chat_session import ChatSession
from app.models.chat_message import ChatMessage

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

router = APIRouter(prefix="/api/v1/chat", tags=["predict"])

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
                        # for i, upload in enumerate(chat_request.uploads):
                        #     if hasattr(upload, 'model_dump'):
                        #         print(f"DEBUG: Upload {i} model_dump result: {upload.model_dump()}")
                        #     else:
                        #         print(f"DEBUG: Upload {i} as dict: {upload}")
                        
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
                    
                    first_chunk = next(completion, None)
                    if first_chunk is not None:
                        print("✅ SDK approach working, using optimized streaming")
                        chunk_str = ""
                        if isinstance(first_chunk, bytes):
                            chunk_str = first_chunk.decode("utf-8", errors="ignore")
                        else:
                            chunk_str = str(first_chunk)
                        good_json_string = repair_json(chunk_str)
                        
                        full_assistant_response_ls.append(good_json_string)
                        yield good_json_string
                        
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
                    
                    payload = {
                        "question": chat_request.question,
                        "overrideConfig": override_config,
                        "streaming": True,
                        "history": chat_request.history
                    }
                    
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
                                sse_events = parse_sse_chunk(chunk_str)
                                
                                for event_json in sse_events:
                                    if event_json.strip():
                                        good_json_string = repair_json(event_json)
                                        full_assistant_response_ls.append(good_json_string)
                                        yield good_json_string
                                        response_streamed = True
                    else:
                        raise Exception(f"Direct API call failed: {response.status_code} - {response.text}")

                if response_streamed:
                    
                    def process_json(full_assistant_response_ls):
                        result = []
                        non_Token_event_result = []
                        token_data = ""

                        for good_json_string in full_assistant_response_ls:
                            try:
                                obj = json.loads(good_json_string)
                                
                                if isinstance(obj, dict):
                                    if obj.get("event") == "token":
                                        token_data += obj.get("data", "")
                                    else:
                                        if token_data:
                                            result.append(
                                                {"event": "token", "data": token_data}
                                            )
                                            token_data = ""
                                        non_Token_event_result.append(obj)
                                elif isinstance(obj, list):
                                    for event in obj:
                                        if isinstance(event, dict):
                                            if event.get("event") == "token":
                                                token_data += event.get("data", "")
                                            else:
                                                if token_data:
                                                    result.append(
                                                        {"event": "token", "data": token_data}
                                                    )
                                                    token_data = ""
                                                non_Token_event_result.append(event)
                                        else:
                                            print(f"🔍 DEBUG: Skipping non-dict event in list: {event}")
                                else:
                                    print(f"🔍 DEBUG: Skipping non-dict/non-list object: {obj}")
                                    
                            except json.JSONDecodeError as e:
                                print(f"🔍 DEBUG: JSON decode error: {e}")
                                continue

                        if token_data:
                            result.append({"event": "token", "data": token_data})

                        return json.dumps(result), non_Token_event_result

                    await accounting_service.log_transaction(
                        user_token, user_id, "chat", chatflow_id, cost, True
                    )
                    
                    await user_message.insert()
                    
                    if stored_files:
                        try:
                            for i, file in enumerate(stored_files):
                                
                                file.message_id = str(user_message.id)
                                await file.save()
                            
                            user_message.file_ids = [file.file_id for file in stored_files]
                            user_message.has_files = True
                            await user_message.save()
                            
                        except Exception as e:
                            import traceback
                            traceback.print_exc()
                    
                    try:
                        token_content, metadata_events = process_json(full_assistant_response_ls)
                    except Exception as process_error:
                        import traceback
                        traceback.print_exc()
                        token_content = "[]"
                        metadata_events = []
                    
                    assistant_message = ChatMessage(
                        chatflow_id=chatflow_id,
                        session_id=session_id,
                        user_id=user_id,
                        role="assistant",
                        content=token_content,
                        metadata=metadata_events,
                        has_files=False,
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
                            topic=topic,
                        )
                        try:
                            await new_chat_session.insert()
                        except Exception as session_insert_error:
                            import traceback
                            traceback.print_exc()
                    else:
                        existing_session = await ChatSession.find_one(
                            ChatSession.session_id == session_id,
                            ChatSession.user_id == user_id
                        )
                        if existing_session:
                            print(f"🔍 DEBUG: Existing session found: {existing_session}")
                        else:
                            print(f"🔍 DEBUG: WARNING: Existing session not found for session_id: {session_id}")

                else:
                    await accounting_service.log_transaction(
                        user_token, user_id, "chat", chatflow_id, cost, False
                    )
                    yield json.dumps({
                        "event": "error",
                        "data": "No response was streamed from the service.",
                        "timestamp": datetime.utcnow().isoformat()
                    })

            except Exception as e:
                import traceback
                traceback.print_exc()
                await accounting_service.log_transaction(
                    user_token, user_id, "chat", chatflow_id, cost, False
                )
                yield json.dumps({
                    "event": "error",
                    "data": f"An error occurred during streaming: {str(e)}",
                    "timestamp": datetime.utcnow().isoformat()
                })

        return StreamingResponse(stream_generator(), media_type="text/event-stream")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Request failed: {str(e)}")
