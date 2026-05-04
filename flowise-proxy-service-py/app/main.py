# app/main.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from app.api import chatflows, admin, auth_routes, predict_routes, session_routes, file_routes
from app.config import settings
from app.database import connect_to_mongo, close_mongo_connection

# Add imports for all models here to ensure they are discovered by Beanie
from app.models.user import User
from app.models.chatflow import (
    Chatflow,
)  # Added UserChatflow as it's likely needed if Chatflow is
from app.models.refresh_token import RefreshToken

# It's good practice to also ensure UserChatflow is imported if it's a separate model used with Chatflow
from app.models.chatflow import (
    UserChatflow,
)  # Explicitly adding, adjust if not a separate model or already covered

from app.tasks.chatflow_sync import chatflow_sync_task

# app.core.logging is imported as logger, but then logging module is also imported.
# Standard practice is to get a logger instance, e.g., logger = logging.getLogger(__name__)
# For now, using your structure, but be mindful of potential shadowing or confusion.
from app.core.logging import (
    logger as app_logger,
)  # Renaming to avoid conflict with standard logging module
import logging
import asyncio
from contextlib import asynccontextmanager
import os  # For PID logging consistency if we add it back
import datetime  # Importing datetime here for lifespan logging

# Configure basic logging (can be enhanced by app.core.logging)
# If app.core.logging already configures the root logger, this might be redundant or override settings.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(name)s - PID:%(process)d - %(message)s",
)
# It's often better to get a specific logger for this module:
module_logger = logging.getLogger(__name__)
PID = os.getpid()  # For consistent logging with previous steps

module_logger.info(f"TOP OF app/main.py EXECUTING (PID: {PID})")


# Lifespan event handler
@asynccontextmanager
async def lifespan(app_instance: FastAPI):  # Changed app to app_instance for clarity
    """Handle startup and shutdown events for the FastAPI application."""
    # Using module_logger for consistency, assuming app_logger is for more general app logging
    module_logger.info(
        f"!!! LIFESPAN (PID:{PID}): Startup sequence initiated (print was here) !!!"
    )
    print(
        f"!!! PID:{PID} - LIFESPAN FUNCTION ENTERED (print statement) !!!"
    )  # Retaining your print

    # Startup logic
    module_logger.info(f"Starting Flowise Proxy Service (PID:{PID})")

    # Initialize database connection
    try:
        module_logger.info(
            f"LIFESPAN (PID:{PID}): Attempting to connect to MongoDB and initialize Beanie..."
        )
        await connect_to_mongo()
        module_logger.info(
            f"LIFESPAN (PID:{PID}): MongoDB connected and Beanie initialized."
        )

        # Setup collections for file system
        module_logger.info(
            f"LIFESPAN (PID:{PID}): Setting up collections for file system..."
        )
        try:
            from app.services.collection_setup_service import collection_setup_service

            # Check if force setup is enabled via environment variable
            force_setup = os.getenv("FORCE_COLLECTION_SETUP", "false").lower() == "true"

            setup_report = await collection_setup_service.setup_all_collections(
                force_recreate=force_setup
            )

            if setup_report["success"]:
                module_logger.info(
                    f"LIFESPAN (PID:{PID}): ✅ Collection setup completed successfully!"
                )
            else:
                module_logger.warning(
                    f"LIFESPAN (PID:{PID}): ⚠️ Collection setup completed with warnings"
                )
                module_logger.warning(
                    f"LIFESPAN (PID:{PID}): Setup errors: {setup_report['errors']}"
                )

            # Write setup report for debugging
            import json

            with open("collection_setup_report.json", "w") as f:
                json.dump(setup_report, f, indent=2, default=str)

        except Exception as setup_error:
            module_logger.error(
                f"LIFESPAN (PID:{PID}): Collection setup failed: {setup_error}",
                exc_info=True,
            )
            # Continue with startup even if collection setup fails
            # The collections might already exist from previous runs

        # Create lifespan_startup.txt for external verification, similar to previous debug steps
        with open("lifespan_startup.txt", "a") as f:
            f.write(
                f"Lifespan startup executed by PID {PID} at {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S,%f')[:-3]}\n"
            )
        module_logger.info(
            f"LIFESPAN (PID:{PID}): Successfully wrote to lifespan_startup.txt"
        )

    except Exception as e:
        module_logger.error(
            f"LIFESPAN (PID:{PID}): Error during DB connection/Beanie init: {e}",
            exc_info=True,
        )
        # Still yield, or re-raise depending on desired behavior if DB fails
        # For now, if DB fails, app might not be usable, but we continue to yield to see lifecycle.

    # Start periodic chatflow sync if enabled
    # Ensure settings are loaded correctly for this check
    sync_task_instance = None
    if hasattr(settings, "ENABLE_CHATFLOW_SYNC") and settings.ENABLE_CHATFLOW_SYNC:
        module_logger.info(
            f"LIFESPAN (PID:{PID}): ENABLE_CHATFLOW_SYNC is True. Starting periodic chatflow sync."
        )
        sync_task_instance = asyncio.create_task(
            chatflow_sync_task.start_periodic_sync()
        )
    else:
        module_logger.info(
            f"LIFESPAN (PID:{PID}): ENABLE_CHATFLOW_SYNC is False or not set. Periodic sync disabled."
        )

    try:
        yield  # Application runs here
    finally:
        # Shutdown logic
        module_logger.info(
            f"!!! LIFESPAN (PID:{PID}): Shutdown sequence initiated (print was here) !!!"
        )
        print(
            f"!!! PID:{PID} - LIFESPAN FUNCTION EXITED (print statement) !!!"
        )  # Retaining your print
        module_logger.info(f"Shutting down Flowise Proxy Service (PID:{PID})")

        # Stop periodic sync
        if (
            sync_task_instance
            and hasattr(settings, "ENABLE_CHATFLOW_SYNC")
            and settings.ENABLE_CHATFLOW_SYNC
        ):
            module_logger.info(
                f"LIFESPAN (PID:{PID}): Stopping periodic chatflow sync."
            )
            chatflow_sync_task.stop_periodic_sync()  # This typically sets a flag
            try:
                await asyncio.wait_for(
                    sync_task_instance, timeout=5.0
                )  # Wait for task to acknowledge stop
                module_logger.info(
                    f"LIFESPAN (PID:{PID}): Periodic chatflow sync task finished."
                )
            except asyncio.TimeoutError:
                module_logger.warning(
                    f"LIFESPAN (PID:{PID}): Timeout waiting for chatflow_sync_task to stop."
                )
            except Exception as e:  # Catch other potential errors during task shutdown
                module_logger.error(
                    f"LIFESPAN (PID:{PID}): Error stopping chatflow_sync_task: {e}",
                    exc_info=True,
                )

        # Close database connection
        try:
            module_logger.info(
                f"LIFESPAN (PID:{PID}): Attempting to disconnect from MongoDB..."
            )
            await close_mongo_connection()
            module_logger.info(f"LIFESPAN (PID:{PID}): MongoDB disconnected.")
            # Create lifespan_shutdown.txt for external verification
            with open(
                "lifespan_shutdown.txt", "a"
            ) as f:  # Need to import datetime for this
                f.write(
                    f"Lifespan shutdown executed by PID {PID} at {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S,%f')[:-3]}\n"
                )
            module_logger.info(
                f"LIFESPAN (PID:{PID}): Successfully wrote to lifespan_shutdown.txt"
            )
        except Exception as e:
            module_logger.error(
                f"LIFESPAN (PID:{PID}): Error during DB disconnection: {e}",
                exc_info=True,
            )


# Create FastAPI application
app = FastAPI(
    title="Flowise Proxy Service",
    description="Proxy service for Flowise with authentication and credit management",
    version="1.0.0",
    debug=settings.DEBUG,
    lifespan=lifespan,  # Assigning your lifespan function here
)
module_logger.info(f"FastAPI app object created with lifespan. App: {app} (PID: {PID})")

# Add CORS middleware.
# CORS_ALLOW_ORIGINS is a comma-separated string from env; split here.
# Note: when allow_credentials=True, Starlette will NOT echo Origin if any
# entry is "*". Use explicit origins (e.g. http://localhost:3082).
_cors_raw = getattr(settings, "CORS_ALLOW_ORIGINS", "*") or "*"
_cors_origins = [o.strip() for o in str(_cors_raw).split(",") if o.strip()] or ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
module_logger.info(
    f"CORS middleware added. Allowed origins: {app.user_middleware[-1].options['allow_origins']} (PID: {PID})"
)


# Include routers
app.include_router(chatflows.router)
app.include_router(auth_routes.router)
app.include_router(predict_routes.router)
app.include_router(session_routes.router)
app.include_router(file_routes.router)
app.include_router(admin.router)
module_logger.info(f"Routers included. (PID: {PID})")


@app.get("/")
async def root():
    module_logger.info(f"Root endpoint / called (PID: {PID})")
    return {"message": "Flowise Proxy Service", "version": "1.0.0", "status": "running"}


@app.get("/health")
async def health_check():
    """Enhanced health check with collection status."""
    module_logger.info(f"Health check /health called (PID: {PID})")
    print("=ok=")  # As per your original code

    try:
        from app.services.collection_setup_service import collection_setup_service

        # Get detailed health report
        health_report = await collection_setup_service.health_check()

        return {
            "status": (
                "healthy"
                if health_report["overall_health"] == "healthy"
                else "degraded"
            ),
            "service": "flowise-proxy-service",
            "version": "1.0.0",
            "timestamp": health_report["timestamp"],
            "database": health_report["database_status"],
            "collections": health_report["collections_status"],
            "gridfs": health_report["gridfs_status"],
        }
    except Exception as e:
        module_logger.error(f"Health check failed: {str(e)}")
        return {
            "status": "unhealthy",
            "service": "flowise-proxy-service",
            "version": "1.0.0",
            "error": str(e),
        }


@app.get("/collections/status")
async def collections_status():
    """Get detailed status of all collections."""
    try:
        from app.services.collection_setup_service import collection_setup_service

        setup_status = await collection_setup_service.get_setup_status()
        health_report = await collection_setup_service.health_check()

        return {
            "setup_status": setup_status,
            "health_status": health_report,
            "timestamp": datetime.datetime.utcnow().isoformat(),
        }
    except Exception as e:
        module_logger.error(f"Collections status check failed: {str(e)}")
        return {"error": str(e), "timestamp": datetime.datetime.utcnow().isoformat()}


@app.get("/info")
async def service_info():
    module_logger.info(f"Service info /info called (PID: {PID})")
    return {
        "service": "flowise-proxy-service",
        "version": "1.0.0",
        "flowise_url": settings.FLOWISE_API_URL,
        "debug": settings.DEBUG,
        "endpoints": {
            "authentication": "/api/v1/chat/authenticate",  # Assuming your router prefixes define this
            "chatflows": "/api/v1/chatflows/",
            "prediction": "/api/v1/chat/predict",
            "credits": "/api/v1/chat/credits",
        },
    }


module_logger.info(f"BOTTOM OF app/main.py EXECUTING (PID: {PID})")

if __name__ == "__main__":
    # This block is for running directly with Hypercorn, not typically used when Uvicorn runs the app module.
    # For Uvicorn CLI (e.g., python -m uvicorn app.main:app), this block won't execute in the main server process.
    # It might run if the reloader spawns a new process using `python app/main.py`.
    module_logger.info(
        f"__main__ block entered. Attempting to start with Hypercorn. (PID: {PID})"
    )

    # Ensure settings are fully loaded if relying on them here.
    # from app.config import settings # Already imported, but ensure it's the live settings object.

    # Check if settings has HOST and PORT, provide defaults if not for safety
    HOST = getattr(settings, "HOST", "0.0.0.0")
    PORT = getattr(settings, "PORT", 8000)  # Default to 8000 if not set
    DEBUG_MODE = getattr(settings, "DEBUG", False)

    try:
        import hypercorn.asyncio
        from hypercorn.config import (
            Config as HypercornConfig,
        )  # Alias to avoid confusion if other Config is used

        hypercorn_config = HypercornConfig()
        hypercorn_config.bind = [f"{HOST}:{PORT}"]
        hypercorn_config.debug = DEBUG_MODE
        # hypercorn_config.lifespan = "on" # Hypercorn should pick up app.lifespan

        module_logger.info(
            f"Starting Flowise Proxy Service with Hypercorn on {HOST}:{PORT} (PID: {PID})"
        )
        asyncio.run(hypercorn.asyncio.serve(app, hypercorn_config))
    except ImportError:
        module_logger.error(
            "Hypercorn is not installed. Cannot run with __main__ block's Hypercorn starter."
        )
        module_logger.info("Please run using Uvicorn: uvicorn app.main:app --reload")
    except Exception as e:
        module_logger.error(
            f"Error starting Hypercorn: {e} (PID: {PID})", exc_info=True
        )
