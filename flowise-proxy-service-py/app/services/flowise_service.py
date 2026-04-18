import httpx
from typing import Dict, List, Optional, Any
from app.config import settings
from app.database import get_database

class FlowiseService:
    def __init__(self):
        self.flowise_url = settings.FLOWISE_API_URL
        self.api_key = settings.FLOWISE_API_KEY
        self.timeout = 10000  # Increased from 3000ms to 10000ms (10 seconds)

    async def _get_runtime_api_key(self) -> Optional[str]:
        """Resolve API key from runtime settings with .env fallback."""
        try:
            db = await get_database()
            if db is not None:
                doc = await db["runtime_settings"].find_one({"_id": "flowise_proxy"})
                if doc and doc.get("flowise_api_key"):
                    return doc.get("flowise_api_key")
        except Exception:
            # Fall back to startup value when runtime settings are unavailable.
            pass
        return self.api_key

    async def _get_headers(self) -> Dict[str, str]:
        """Get headers for Flowise API requests"""
        headers = {"Content-Type": "application/json"}
        api_key = await self._get_runtime_api_key()
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        return headers

    async def list_chatflows(self) -> Optional[List[Dict]]:
        """Get list of all available chatflows from Flowise"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.flowise_url}/api/v1/chatflows",
                    headers=await self._get_headers(),
                    timeout=self.timeout
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    print(f"Flowise API error: {response.status_code}")
                    return None
                    
        except httpx.RequestError as e:
            print(f"Flowise connection error: {e}")
            return None
        except Exception as e:
            print(f"Unexpected Flowise error: {e}")
            return None

    async def get_chatflow(self, chatflow_id: str) -> Optional[Dict]:
        """Get specific chatflow details"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.flowise_url}/api/v1/chatflows/{chatflow_id}",
                    headers=await self._get_headers(),
                    timeout=self.timeout
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    return None
                    
        except Exception as e:
            print(f"Chatflow retrieval error: {e}")
            return None

    async def predict(self, chatflow_id: str, question: str, override_config: Dict[str, Any] = None) -> Optional[Dict]:
        """Send prediction request to Flowise chatflow"""
        try:
            payload = {
                "question": question
            }
            
            if override_config:
                payload["overrideConfig"] = override_config

            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.flowise_url}/api/v1/prediction/{chatflow_id}",
                    headers=await self._get_headers(),
                    json=payload,
                    timeout=self.timeout  # Longer timeout for AI responses
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    print(f"Prediction error: {response.status_code} - {response.text}")
                    return None
                    
        except httpx.TimeoutException:
            print("Prediction request timed out")
            return None
        except httpx.RequestError as e:
            print(f"Prediction connection error: {e}")
            return None
        except Exception as e:
            print(f"Prediction error: {e}")
            return None

    async def validate_chatflow_exists(self, chatflow_id: str) -> bool:
        """Check if a chatflow exists and is accessible"""
        chatflow = await self.get_chatflow(chatflow_id)
        return chatflow is not None

    async def get_chatflow_config(self, chatflow_id: str) -> Optional[Dict]:
        """Get chatflow configuration"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.flowise_url}/api/v1/chatflows/{chatflow_id}/config",
                    headers=await self._get_headers(),
                    timeout=self.timeout
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    return None
                    
        except Exception as e:
            print(f"Config retrieval error: {e}")
            return None
