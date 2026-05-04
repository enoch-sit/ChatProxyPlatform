from motor.motor_asyncio import AsyncIOMotorClient
from beanie import init_beanie
from app.config import settings
from app.models.user import User
from app.models.chatflow import Chatflow, UserChatflow
from app.models.refresh_token import RefreshToken
from app.models.chat_session import ChatSession  # Added import
from app.models.chat_message import ChatMessage
from app.models.file_upload import FileUpload
import logging
import uuid  # Added import
logger = logging.getLogger(__name__)


class DatabaseManager:
    client = None
    database = None
    init_count: int = 0  # Added counter
    current_client_instance_id: uuid.UUID | None = (
        None  # Added tracker for client instance ID
    )


database = DatabaseManager()


async def connect_to_mongo():
    """Create database connection"""
    database.init_count += 1
    call_instance_id = uuid.uuid4()

    if database.client is not None:
        logger.warning(
            f"CONNECT_TO_MONGO: Re-initializing. Previous client (instance_id: {database.current_client_instance_id}) existed. New call_instance_id: {call_instance_id}. Init count: {database.init_count}"
        )
    else:
        logger.info(
            f"CONNECT_TO_MONGO: Initializing. Call_instance_id: {call_instance_id}. Init count: {database.init_count}"
        )

    try:
        if database.client is not None:
            try:
                database.client.close()
            except Exception:
                pass

        logger.info(
            f"Attempting to connect to MongoDB at {settings.MONGODB_URL} (call_id: {call_instance_id})"
        )
        logger.info(
            f"Database name: {settings.MONGODB_DATABASE_NAME} (call_id: {call_instance_id})"
        )

        new_client = AsyncIOMotorClient(settings.MONGODB_URL)
        new_db_instance = new_client[settings.MONGODB_DATABASE_NAME]

        # Test the connection
        await new_client.admin.command("ping")
        logger.info(
            f"MongoDB ping successful for new client (call_id: {call_instance_id})"
        )

        database.client = new_client
        database.database = new_db_instance
        database.current_client_instance_id = call_instance_id

        # Initialize beanie with the document models
        await init_beanie(
            database=database.database,
            document_models=[
                User,
                Chatflow,
                UserChatflow,
                RefreshToken,
                ChatSession,
                ChatMessage,
                FileUpload,
            ],
        )

        logger.info(
            f"Successfully connected to MongoDB and initialized Beanie (call_id: {call_instance_id}, init_count: {database.init_count})"
        )

        # !!! START DEBUGGING CODE !!!
        try:
            logger.info(
                f"!!! DEBUG: Attempting to access User.external_id post-init. Type: {type(User.external_id)}"
            )
            # If the above works, User.external_id is a Beanie query field.
            # You could also log its representation if needed:
            # logger.info(f"!!! DEBUG: Representation of User.external_id: {repr(User.external_id)}")
        except AttributeError as e:
            logger.error(
                f"!!! DEBUG: AttributeError accessing User.external_id post-init: {e}"
            )
        except Exception as e:
            logger.error(
                f"!!! DEBUG: Other error accessing User.external_id post-init: {e}"
            )
        # !!! END DEBUGGING CODE !!!

        logger.info(
            f"Using database: {settings.MONGODB_DATABASE_NAME} (call_id: {call_instance_id})"
        )
        # logger.info("Beanie initialization completed") # Covered by the message above

    except Exception as e:
        logger.error(
            f"Failed to connect to MongoDB (call_id: {call_instance_id}, init_count: {database.init_count}): {e}"
        )
        logger.error(f"MongoDB URL: {settings.MONGODB_URL}")
        logger.error(f"Database name: {settings.MONGODB_DATABASE_NAME}")
        raise


async def close_mongo_connection():
    """Close database connection"""
    try:
        if database.client:
            logger.info(
                f"Closing MongoDB connection (client_instance_id: {database.current_client_instance_id}, init_count: {database.init_count})"
            )
            database.client.close()
            logger.info(
                f"Disconnected from MongoDB (client_instance_id: {database.current_client_instance_id}, init_count: {database.init_count})"
            )
            database.client = None
            database.database = None
            database.current_client_instance_id = None
        else:
            logger.info("MongoDB connection already closed or not established.")
    except Exception as e:
        logger.error(f"Error closing MongoDB connection: {e}")


async def get_database():
    """Get database instance"""
    if database.database is None:
        logger.warning(
            f"GET_DATABASE: database.database is None. Current init_count: {database.init_count}. Client instance ID: {database.current_client_instance_id}. Attempting to call connect_to_mongo."
        )
        await connect_to_mongo()
    else:
        try:
            await database.client.admin.command("ping")
        except Exception as exc:
            logger.warning(
                f"GET_DATABASE: existing MongoDB handle is stale (client_instance_id: {database.current_client_instance_id}). Reconnecting. Error: {exc}"
            )
            database.client = None
            database.database = None
            database.current_client_instance_id = None
            await connect_to_mongo()
        else:
            logger.debug(
                f"GET_DATABASE: database.database is already set (client_instance_id: {database.current_client_instance_id}). Current init_count: {database.init_count}"
            )
    return database.database


def get_database_sync():
    """Get database instance synchronously for dependency injection"""
    if database.database is None:
        logger.error(
            f"GET_DATABASE_SYNC: Database connection not established. Current init_count: {database.init_count}. Client instance ID: {database.current_client_instance_id}."
        )
        # This path should ideally not be hit if connect_to_mongo is called at startup.
        # If it needs to work without prior async connection, it would need a sync connection method.
        raise RuntimeError(
            "Database not connected. Synchronous access requires prior async initialization."
        )
    logger.debug(
        f"GET_DATABASE_SYNC: Returning existing database instance (client_instance_id: {database.current_client_instance_id}). Current init_count: {database.init_count}"
    )
    return database.database
