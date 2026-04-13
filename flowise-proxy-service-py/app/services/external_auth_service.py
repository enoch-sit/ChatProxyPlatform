import httpx
import logging
from typing import Dict, Optional
from app.config import settings
import urllib

logger = logging.getLogger(__name__)


class ExternalAuthService:
    def __init__(self):
        self.auth_url = settings.EXTERNAL_AUTH_URL.rstrip("/")
        self.timeout = 10

    async def authenticate_user(self, username: str, password: str) -> Optional[Dict]:
        """
        Authenticate user via external auth service

        Args:
            username: User's username
            password: User's password

        Returns:
            Dict containing token and user info, or None if authentication fails
        """
        try:
            auth_payload = {"username": username, "password": password}

            headers = {"Content-Type": "application/json", "Accept": "application/json"}

            auth_url = f"{self.auth_url}/api/auth/login"
            logger.info(f"Attempting authentication to: {auth_url}")
            logger.info(f"Username: {username}")

            # Use verify=False for internal VPC calls through ALB to avoid
            # SSL certificate issues when calling via internal DNS
            verify_ssl = not self.auth_url.startswith("http://")
            async with httpx.AsyncClient(verify=verify_ssl) as client:
                response = await client.post(
                    auth_url, json=auth_payload, headers=headers, timeout=self.timeout
                )
                logger.info(f"Auth response status code: {response.status_code}")
                # print(f"DEBUG: Auth response status code: {response.status_code}")
                if response.status_code != 200:
                    logger.error(f"Auth response text: {response.text}")
                    # print(f"DEBUG: Auth response text: {response.text}")
                if response.status_code == 200:
                    data = response.json()
                    return {
                        "access_token": data.get("accessToken"),
                        "refresh_token": data.get("refreshToken"),
                        "token_type": "bearer",
                        "user": data.get("user", {}),
                        "message": data.get("message", "Login successful"),
                    }
                    # {
                    #   "message": "Login successful",
                    #   "accessToken": "string",
                    #   "refreshToken": "string",
                    #   "user": {
                    #     "id": "string",
                    #     "username": "string",
                    #     "email": "string",
                    #     "isVerified": boolean,
                    #     "role": "string"
                    #   }
                    # }
                elif response.status_code == 401:
                    error_detail = "Invalid credentials"
                    try:
                        error_data = response.json()
                        error_detail = error_data.get("error", error_data.get("message", error_detail))
                    except Exception:
                        pass
                    logger.warning(
                        f"Authentication failed for {username}: {error_detail}"
                    )
                    return None
                else:
                    logger.error(
                        f"Auth service returned {response.status_code}: {response.text}"
                    )
                    return None

        except httpx.ConnectError as e:
            logger.error(f"Cannot connect to auth service at {self.auth_url}: {e}")
            print(f"DEBUG: Cannot connect to auth service at {self.auth_url}: {e}")
            return None
        except httpx.TimeoutException as e:
            logger.error(f"Timeout connecting to auth service: {e}")
            print(f"DEBUG: Timeout connecting to auth service: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error during authentication: {e}")
            print(f"DEBUG: Unexpected error during authentication: {e}")
            return None

    async def refresh_token(self, refresh_token: str) -> Optional[Dict]:
        """
        Refresh access token using refresh token

        Args:
            refresh_token: The refresh token

        Returns:
            Dict containing new tokens, or None if refresh fails
        """
        try:
            refresh_payload = {"refreshToken": refresh_token}

            headers = {"Content-Type": "application/json", "Accept": "application/json"}

            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.auth_url}/api/auth/refresh",
                    json=refresh_payload,
                    headers=headers,
                    timeout=self.timeout,
                )

                if response.status_code == 200:
                    data = response.json()
                    return {
                        "access_token": data.get("accessToken"),
                        "refresh_token": data.get("refreshToken"),
                        "token_type": "bearer",
                    }
                else:
                    logger.error(
                        f"Token refresh failed: {response.status_code} - {response.text}"
                    )
                    return None

        except Exception as e:
            logger.error(f"Token refresh error: {e}")
            return None

    async def get_all_users(self, access_token: str) -> Optional[Dict]:
        """
        Fetch all users from external auth service

        Args:
            access_token: Admin access token for authentication

        Returns:
            Dict containing users list, or None if request fails
        """
        try:
            headers = {
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": f"Bearer {access_token}",
            }

            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.auth_url}/api/admin/users",
                    headers=headers,
                    timeout=self.timeout,
                )

                if response.status_code == 200:
                    data = response.json()
                    return data
                elif response.status_code == 401:
                    logger.warning("Unauthorized access to external auth service")
                    return None
                elif response.status_code == 403:
                    logger.warning("Forbidden: Admin access required")
                    return None
                else:
                    logger.error(
                        f"External auth service returned {response.status_code}: {response.text}"
                    )
                    return None

        except httpx.ConnectError:
            logger.error(f"Cannot connect to auth service at {self.auth_url}")
            return None
        except httpx.TimeoutException:
            logger.error(f"Timeout connecting to auth service")
            return None
        except Exception as e:
            logger.error(f"Unexpected error fetching users: {e}")
            return None

    async def get_user_by_email(self, email: str, admin_token: str) -> Optional[Dict]:
        """
        Get user details from external auth API by email

        Args:
            email: User's email address
            admin_token: Admin JWT token for authentication

        Returns:
            Dict containing user info, or None if not found
        """
        try:
            # URL encode the email parameter
            encoded_email = urllib.parse.quote(email)

            headers = {
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": f"Bearer {admin_token}",
            }

            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.auth_url}/api/admin/users/by-email/{encoded_email}",
                    headers=headers,
                    timeout=self.timeout,
                )

                if response.status_code == 200:
                    data = response.json()
                    user_data = data.get("user", {})

                    # Normalize the response format to match your needs
                    return {
                        "user_id": user_data.get("_id") or user_data.get("id"),
                        "username": user_data.get("username"),
                        "email": user_data.get("email"),
                        "role": user_data.get("role"),
                        "is_verified": user_data.get("isVerified", False),
                        "created_at": user_data.get("createdAt"),
                        "updated_at": user_data.get("updatedAt"),
                    }
                elif response.status_code == 404:
                    logger.info(
                        f"User with email '{email}' not found in external auth system"
                    )
                    return None
                elif response.status_code == 401:
                    logger.warning("Unauthorized: Invalid or expired admin token")
                    return None
                elif response.status_code == 403:
                    logger.warning("Forbidden: Admin access required")
                    return None
                else:
                    logger.error(
                        f"External auth service returned {response.status_code}: {response.text}"
                    )
                    return None

        except httpx.ConnectError:
            logger.error(f"Cannot connect to auth service at {self.auth_url}")
            return None
        except httpx.TimeoutException:
            logger.error(f"Timeout connecting to auth service")
            return None
        except Exception as e:
            logger.error(f"Error fetching user by email from external auth: {e}")
            return None

    async def get_user_by_id(self, user_id: str, admin_token: str) -> Optional[Dict]:
        """
        Get user details from external auth API by user ID

        Args:
            user_id: User's ID
            admin_token: Admin JWT token for authentication

        Returns:
            Dict containing user info, or None if not found
        """
        try:
            headers = {
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": f"Bearer {admin_token}",
            }

            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.auth_url}/api/admin/users/{user_id}",
                    headers=headers,
                    timeout=self.timeout,
                )

                if response.status_code == 200:
                    data = response.json()
                    user_data = data.get("user", data)  # Handle both formats

                    # Normalize the response format to match your needs
                    return {
                        "user_id": user_data.get("_id") or user_data.get("id"),
                        "username": user_data.get("username"),
                        "email": user_data.get("email"),
                        "role": user_data.get("role"),
                        "is_verified": user_data.get("isVerified", False),
                        "created_at": user_data.get("createdAt"),
                        "updated_at": user_data.get("updatedAt"),
                    }
                elif response.status_code == 404:
                    logger.info(
                        f"User with ID '{user_id}' not found in external auth system"
                    )
                    return None
                elif response.status_code == 401:
                    logger.warning("Unauthorized: Invalid or expired admin token")
                    return None
                elif response.status_code == 403:
                    logger.warning("Forbidden: Admin access required")
                    return None
                else:
                    logger.error(
                        f"External auth service returned {response.status_code}: {response.text}"
                    )
                    return None

        except httpx.ConnectError:
            logger.error(f"Cannot connect to auth service at {self.auth_url}")
            return None
        except httpx.TimeoutException:
            logger.error(f"Timeout connecting to auth service")
            return None
        except Exception as e:
            logger.error(f"Error fetching user by ID from external auth: {e}")
            return None

    async def check_user_exists(
        self, external_user_id: str, admin_token: Optional[str] = None
    ) -> bool:
        """
        Check if a user still exists in the external auth system.
        This is critical for security - prevents deleted users from accessing the system.

        Args:
            external_user_id: The external auth system's user ID
            admin_token: Admin token for checking user existence (optional)

        Returns:
            bool: True if user exists and is active, False otherwise
        """
        try:
            headers = {"Accept": "application/json"}

            # If admin token provided, use it for authentication
            if admin_token:
                headers["Authorization"] = f"Bearer {admin_token}"

            async with httpx.AsyncClient() as client:
                # Try to get user info by ID
                response = await client.get(
                    f"{self.auth_url}/api/auth/users/{external_user_id}",
                    headers=headers,
                    timeout=self.timeout,
                )

                if response.status_code == 200:
                    user_data = response.json()
                    # Check if user exists and is not deleted/disabled
                    is_active = user_data.get(
                        "active", True
                    )  # Default to True if not specified
                    is_deleted = user_data.get("deleted", False)

                    exists_and_active = is_active and not is_deleted
                    logger.debug(
                        f"✅ User {external_user_id} exists in external auth: active={is_active}, deleted={is_deleted}"
                    )
                    return exists_and_active
                elif response.status_code == 404:
                    # User not found
                    logger.warning(
                        f"🚨 User {external_user_id} not found in external auth system"
                    )
                    return False
                elif response.status_code == 401:
                    # Unauthorized - might be token issue or endpoint not available
                    logger.warning(
                        f"⚠️ Unauthorized when checking user {external_user_id} - token may be invalid or endpoint restricted"
                    )
                    # For admin users performing system operations, we might want to be more lenient
                    # Return None to indicate "unknown" rather than definitively False
                    raise Exception(
                        f"Authorization failed when checking user existence (401)"
                    )
                else:
                    # Other error - log but fail secure
                    logger.error(
                        f"❌ Error checking user existence (status {response.status_code}): {response.text}"
                    )
                    raise Exception(
                        f"External auth service returned {response.status_code}"
                    )

        except httpx.ConnectError:
            logger.error(
                f"🔌 Cannot connect to external auth service at {self.auth_url}"
            )
            raise Exception("Cannot connect to external auth service")
        except httpx.TimeoutException:
            logger.error(f"⏰ Timeout checking user existence for {external_user_id}")
            raise Exception("Timeout connecting to external auth service")
        except Exception as e:
            logger.error(
                f"❌ Exception checking user existence for {external_user_id}: {e}"
            )
            raise e
