import base64
import hashlib
import io
import os
from typing import List, Optional, Dict, Any, Tuple
from datetime import datetime
from motor.motor_asyncio import AsyncIOMotorGridFSBucket

try:
    import magic
except ImportError:
    magic = None

from app.database import get_database
from app.models.file_upload import FileUpload as FileUploadModel
from app.config import settings


class FileStorageService:
    """Service for handling file uploads and storage using MongoDB GridFS."""
    
    def __init__(self):
        self.max_file_size = 10 * 1024 * 1024  # 10MB default
        self.allowed_mime_types = {
            'image/jpeg', 'image/png', 'image/gif', 'image/webp',
            'application/pdf', 'text/plain', 'text/csv',
            'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        }
    
    async def get_gridfs_bucket(self):
        """Get GridFS bucket for file operations."""
        print(f"DEBUG: get_gridfs_bucket called")
        try:
            db = await get_database()
            print(f"DEBUG: get_database returned: {db}, type: {type(db)}")
            
            if db is None:
                print(f"DEBUG: Database is None!")
                raise RuntimeError("Database instance is None")
                
            bucket = AsyncIOMotorGridFSBucket(db)
            print(f"DEBUG: Created GridFS bucket: {bucket}")
            return bucket
            
        except Exception as e:
            print(f"DEBUG: Exception in get_gridfs_bucket: {e}")
            print(f"DEBUG: Exception type: {type(e)}")
            import traceback
            traceback.print_exc()
            raise
    
    def calculate_file_hash(self, file_data: bytes) -> str:
        """Calculate SHA256 hash of file data for deduplication."""
        return hashlib.sha256(file_data).hexdigest()
    
    def validate_file(self, file_data: bytes, mime_type: str, filename: str) -> Tuple[bool, str]:
        """Validate file data, mime type, and size."""
        # Check file size
        if len(file_data) > self.max_file_size:
            return False, f"File size {len(file_data)} exceeds maximum {self.max_file_size} bytes"
        
        # Check MIME type
        if mime_type not in self.allowed_mime_types:
            return False, f"MIME type {mime_type} not allowed"
        
        # Validate file content matches MIME type
        try:
            if magic is None:
                return True, "Valid"

            detected_mime = magic.from_buffer(file_data, mime=True)
            if detected_mime != mime_type:
                return False, f"File content ({detected_mime}) doesn't match declared MIME type ({mime_type})"
        except Exception:
            # If magic detection fails, continue with basic validation
            pass
        
        return True, "Valid"
    
    async def store_file(
        self,
        file_data: bytes,
        filename: str,
        mime_type: str,
        user_id: str,
        session_id: str,
        chatflow_id: str,
        message_id: str,
        upload_type: str = "file"
    ) -> Optional[FileUploadModel]:
        """Store file in GridFS and create metadata record."""
        
        print(f"DEBUG: store_file called with filename={filename}, mime_type={mime_type}")
        
        try:
            # Validate file
            is_valid, error_msg = self.validate_file(file_data, mime_type, filename)
            if not is_valid:
                print(f"DEBUG: File validation failed: {error_msg}")
                raise ValueError(error_msg)
            
            print(f"DEBUG: File validation passed")
            
            # Calculate file hash for deduplication
            file_hash = self.calculate_file_hash(file_data)
            print(f"DEBUG: File hash calculated: {file_hash}")
            
            # Check if file already exists (deduplication)
            print(f"DEBUG: Checking for existing file with hash={file_hash}")
            existing_file = await FileUploadModel.find_one(
                FileUploadModel.file_hash == file_hash,
                FileUploadModel.user_id == user_id
            )
            
            if existing_file:
                print(f"DEBUG: Found existing file, creating duplicate record")
                # Create new metadata record but reuse existing file
                file_record = FileUploadModel(
                    file_id=existing_file.file_id,
                    original_name=filename,
                    mime_type=mime_type,
                    message_id=message_id,
                    session_id=session_id,
                    user_id=user_id,
                    chatflow_id=chatflow_id,
                    file_size=len(file_data),
                    upload_type=upload_type,
                    file_hash=file_hash,
                    processed=False,
                    metadata={"deduplicated": True, "original_file_id": existing_file.file_id}
                )
                await file_record.insert()
                print(f"DEBUG: Duplicate record created: {file_record.file_id}")
                return file_record
            
            print(f"DEBUG: No existing file found, storing new file")
            # Store new file in GridFS
            gridfs_bucket = await self.get_gridfs_bucket()
            print(f"DEBUG: Got GridFS bucket: {gridfs_bucket}")
            
            # Create file metadata for GridFS
            gridfs_metadata = {
                "user_id": user_id,
                "session_id": session_id,
                "chatflow_id": chatflow_id,
                "message_id": message_id,
                "upload_type": upload_type,
                "file_hash": file_hash,
                "mime_type": mime_type,  # Add mime_type to GridFS metadata
                "uploaded_at": datetime.utcnow().isoformat()
            }
            
            print(f"DEBUG: GridFS metadata: {gridfs_metadata}")
            
            # Upload file to GridFS
            file_id = await gridfs_bucket.upload_from_stream(
                filename,
                io.BytesIO(file_data),
                metadata=gridfs_metadata
            )
            
            print(f"DEBUG: File uploaded to GridFS with ID: {file_id}")
            
            # Create metadata record
            file_record = FileUploadModel(
                file_id=str(file_id),
                original_name=filename,
                mime_type=mime_type,
                message_id=message_id,
                session_id=session_id,
                user_id=user_id,
                chatflow_id=chatflow_id,
                file_size=len(file_data),
                upload_type=upload_type,
                file_hash=file_hash,
                processed=False
            )
            
            print(f"DEBUG: Created file record: {file_record}")
            await file_record.insert()
            print(f"DEBUG: File record inserted successfully")
            return file_record
            
        except Exception as e:
            print(f"DEBUG: Exception in store_file: {e}")
            print(f"DEBUG: Exception type: {type(e)}")
            import traceback
            traceback.print_exc()
            raise
    
    async def get_file(self, file_id: str) -> Optional[Tuple[bytes, str, str]]:
        """Retrieve file from GridFS by file_id."""
        print(f"🔍 DEBUG: get_file called with file_id: {file_id}")
        
        try:
            gridfs_bucket = await self.get_gridfs_bucket()
            print(f"✅ DEBUG: Got GridFS bucket: {gridfs_bucket}")
            
            # Convert string file_id to ObjectId for GridFS
            from bson import ObjectId
            
            if not ObjectId.is_valid(file_id):
                print(f"❌ DEBUG: Invalid ObjectId format: {file_id}")
                return None
            
            object_id = ObjectId(file_id)
            print(f"✅ DEBUG: Converted to ObjectId: {object_id}")
            
            # First check if file exists in GridFS
            file_cursor = gridfs_bucket.find({"_id": object_id})
            file_info_list = await file_cursor.to_list(length=1)
            
            if not file_info_list:
                print(f"❌ DEBUG: File not found in GridFS: {file_id}")
                return None
            
            file_info = file_info_list[0]
            print(f"✅ DEBUG: File info found: {file_info}")
            
            # Download file from GridFS
            file_stream = io.BytesIO()
            await gridfs_bucket.download_to_stream(object_id, file_stream)
            file_data = file_stream.getvalue()
            
            print(f"✅ DEBUG: File downloaded, size: {len(file_data)} bytes")
            
            # Extract metadata
            filename = file_info.get("filename", "unknown")
            
            # Try to get mime_type from GridFS metadata first
            gridfs_metadata = file_info.get("metadata", {})
            mime_type = gridfs_metadata.get("mime_type")
            
            if not mime_type:
                # Fallback: try to get from file record
                print(f"🔍 DEBUG: No mime_type in GridFS metadata, checking file record")
                file_record = await FileUploadModel.find_one(FileUploadModel.file_id == file_id)
                if file_record:
                    mime_type = file_record.mime_type
                    print(f"✅ DEBUG: Got mime_type from file record: {mime_type}")
                else:
                    print(f"❌ DEBUG: No file record found for file_id: {file_id}")
            
            # Final fallback
            if not mime_type:
                mime_type = "application/octet-stream"
                print(f"⚠️ DEBUG: Using fallback mime_type: {mime_type}")
            
            print(f"✅ DEBUG: Returning file - filename: {filename}, mime_type: {mime_type}, size: {len(file_data)}")
            return file_data, filename, mime_type
            
        except Exception as e:
            print(f"❌ DEBUG: Exception in get_file: {e}")
            print(f"❌ DEBUG: Exception type: {type(e)}")
            import traceback
            traceback.print_exc()
            return None
            
        except Exception as e:
            print(f"Error retrieving file {file_id}: {e}")
            return None
    
    async def delete_file(self, file_id: str) -> bool:
        """Delete file from GridFS and metadata."""
        try:
            gridfs_bucket = await self.get_gridfs_bucket()
            
            # Delete from GridFS
            await gridfs_bucket.delete(file_id)
            
            # Delete metadata records
            await FileUploadModel.find(
                FileUploadModel.file_id == file_id
            ).delete()
            
            return True
            
        except Exception as e:
            print(f"Error deleting file {file_id}: {e}")
            return False
    
    async def process_upload_list(
        self,
        uploads: List[Dict[str, Any]],
        user_id: str,
        session_id: str,
        chatflow_id: str,
        message_id: str
    ) -> List[FileUploadModel]:
        """Process a list of uploads and store them."""
        stored_files = []
        
        print(f"DEBUG: process_upload_list called with {len(uploads)} uploads")
        for i, upload in enumerate(uploads):
            print(f"DEBUG: Processing upload {i}: type={type(upload)}, value={upload}")
            
            try:
                upload_type = upload.get("type", "file")
                print(f"DEBUG: upload_type = {upload_type}")
                
                if upload_type == "file":
                    # Decode base64 file data
                    file_data_b64 = upload.get("data", "")
                    print(f"DEBUG: file_data_b64 length = {len(file_data_b64)}")
                    
                    # Remove data URI prefix if present
                    if file_data_b64.startswith("data:"):
                        file_data_b64 = file_data_b64.split(",", 1)[1]
                    
                    # Decode base64
                    file_data = base64.b64decode(file_data_b64)
                    print(f"DEBUG: Decoded file_data length = {len(file_data)}")
                    
                    # Store file
                    print(f"DEBUG: Calling store_file with filename={upload.get('name', 'unknown')}")
                    file_record = await self.store_file(
                        file_data=file_data,
                        filename=upload.get("name", "unknown"),
                        mime_type=upload.get("mime", "application/octet-stream"),
                        user_id=user_id,
                        session_id=session_id,
                        chatflow_id=chatflow_id,
                        message_id=message_id,
                        upload_type=upload_type
                    )
                    
                    if file_record:
                        print(f"DEBUG: File stored successfully: {file_record.file_id}")
                        stored_files.append(file_record)
                    else:
                        print(f"DEBUG: File storage returned None")
                        
                elif upload_type == "url":
                    print(f"DEBUG: Processing URL upload")
                    # For URLs, we might want to download and store them
                    # For now, just create a metadata record
                    file_record = FileUploadModel(
                        file_id=f"url_{hash(upload.get('data', ''))}",
                        original_name=upload.get("name", "URL"),
                        mime_type=upload.get("mime", "text/uri-list"),
                        message_id=message_id,
                        session_id=session_id,
                        user_id=user_id,
                        chatflow_id=chatflow_id,
                        file_size=len(upload.get("data", "")),
                        upload_type=upload_type,
                        processed=True,
                        metadata={"url": upload.get("data", "")}
                    )
                    
                    await file_record.insert()
                    stored_files.append(file_record)
                    print(f"DEBUG: URL record created: {file_record.file_id}")
                    
            except Exception as e:
                print(f"DEBUG: Exception in process_upload_list for upload {i}: {e}")
                print(f"DEBUG: Exception type: {type(e)}")
                import traceback
                traceback.print_exc()
                continue
        
        print(f"DEBUG: process_upload_list returning {len(stored_files)} files")
        return stored_files
    
    async def get_files_for_session(self, session_id: str) -> List[FileUploadModel]:
        """Get all files for a chat session."""
        return await FileUploadModel.find(
            FileUploadModel.session_id == session_id
        ).sort(FileUploadModel.uploaded_at).to_list()
    
    async def get_files_for_message(self, message_id: str) -> List[FileUploadModel]:
        """Get all files for a specific message."""
        return await FileUploadModel.find(
            FileUploadModel.message_id == message_id
        ).to_list()
