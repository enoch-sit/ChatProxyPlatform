# Logout Branch Evidence

Date: 2026-04-15 11:28:40
Base branch: release/aws (35dc12cce1d1e8e397bf97951cc98e3a18b1e67d)
Target branch: fix/remote-login-proxy-url (cfe464535297f3f3d53693e2b439bec163cc7252)
Current branch: release/aws

## Changed Critical Files
- bridge/src/api/auth.ts

## Frontend Auth Evidence

### release/aws: bridge/src/api/auth.ts
```
3:import { API_BASE_URL } from './config';
6:* Authenticates a user against the backend.
9:* @returns A promise that resolves with the login response, including access and refresh tokens.
11:* @evidence This function implements the client-side logic for the `/api/v1/chat/authenticate`
19:const response = await fetch(`${API_BASE_URL}/api/v1/chat/authenticate`, {
29:// FastAPI returns errors in "detail" field, but also check "message" for compatibility
30:throw new Error(errorData.detail || errorData.message || `Authentication failed: ${response.status}`);
37:* Refreshes an expired access token using a refresh token.
39:* @param token The refresh token.
43:* `refresh_token` in the authentication response implies the existence of a refresh mechanism.
44:* This function implements the standard client-side logic for a `/api/v1/chat/refresh` endpoint,
47:export const refreshToken = async (token: string): Promise<LoginResponse> => {
48:// Note: We use fetch here instead of apiClient to avoid auth interceptors during token refresh
49:const response = await fetch(`${API_BASE_URL}/api/v1/chat/refresh`, {
54:body: JSON.stringify({ refresh_token: token }),
59:throw new Error(errorData.detail || errorData.message || `Token refresh failed: ${response.status}`);
66:* Logs out a user and invalidates their refresh token on the server.
68:* @param refreshToken The refresh token to invalidate.
70:* @returns A promise that resolves when logout is complete.
72:export const logout = async (refreshToken: string, accessToken: string): Promise<void> => {
74:// Call the server to invalidate the refresh token
75:const response = await fetch(`${API_BASE_URL}/api/v1/chat/revoke`, {
81:body: JSON.stringify({ refresh_token: refreshToken }),
85:console.warn('Logout request failed, but continuing with local cleanup');
88:console.warn('Logout request error, but continuing with local cleanup:', error);
```

### fix/remote-login-proxy-url: bridge/src/api/auth.ts
```
3:import { API_BASE_URL } from './config';
6:* Authenticates a user against the backend.
9:* @returns A promise that resolves with the login response, including access and refresh tokens.
11:* @evidence This function implements the client-side logic for the `/api/v1/chat/authenticate`
19:const response = await fetch(`${API_BASE_URL}/api/v1/chat/authenticate`, {
29:throw new Error(errorData.message || `Authentication failed: ${response.status}`);
36:* Refreshes an expired access token using a refresh token.
38:* @param token The refresh token.
42:* `refresh_token` in the authentication response implies the existence of a refresh mechanism.
43:* This function implements the standard client-side logic for a `/api/v1/chat/refresh` endpoint,
46:export const refreshToken = async (token: string): Promise<LoginResponse> => {
47:// Note: We use fetch here instead of apiClient to avoid auth interceptors during token refresh
48:const response = await fetch(`${API_BASE_URL}/api/v1/chat/refresh`, {
53:body: JSON.stringify({ refresh_token: token }),
58:throw new Error(errorData.message || `Token refresh failed: ${response.status}`);
65:* Logs out a user and invalidates their refresh token on the server.
67:* @param refreshToken The refresh token to invalidate.
69:* @returns A promise that resolves when logout is complete.
71:export const logout = async (refreshToken: string, accessToken: string): Promise<void> => {
73:// Call the server to invalidate the refresh token
74:const response = await fetch(`${API_BASE_URL}/api/v1/chat/revoke`, {
80:body: JSON.stringify({ refresh_token: refreshToken }),
84:console.warn('Logout request failed, but continuing with local cleanup');
87:console.warn('Logout request error, but continuing with local cleanup:', error);
```

## Backend Auth Evidence

### release/aws: flowise-proxy-service-py/app/api/chat.py
```
5:from app.auth.middleware import authenticate_user
108:class RefreshRequest(BaseModel):
109:refresh_token: str
112:class RevokeTokenRequest(BaseModel):
182:@router.post("/authenticate")
183:async def authenticate(auth_request: AuthRequest, request: Request):
185:Authenticate user via external auth service and return JWT tokens
190:# Authenticate user via external service
191:auth_result = await external_auth_service.authenticate_user(
200:"refresh_token": auth_result["refresh_token"],
212:@router.post("/refresh")
213:async def refresh_token(refresh_request: RefreshRequest, request: Request):
215:Refresh access token using external auth service - NO MIDDLEWARE DEPENDENCY
216:This endpoint does not use authenticate_user middleware to avoid circular dependency.
221:# Refresh tokens via external auth service (no middleware)
222:refresh_result = await external_auth_service.refresh_token(
223:refresh_request.refresh_token
226:if refresh_result is None:
228:status_code=401, detail="Invalid or expired refresh token"
232:"access_token": refresh_result["access_token"],
233:"refresh_token": refresh_result["refresh_token"],
234:"token_type": refresh_result["token_type"],
240:raise HTTPException(status_code=500, detail=f"Token refresh failed: {str(e)}")
243:@router.post("/revoke")
244:async def revoke_tokens(
246:current_user: Dict = Depends(authenticate_user),
247:revoke_request: Optional[RevokeTokenRequest] = None,
250:Revoke refresh tokens (specific token or all user tokens)
271:revoke_all = False
274:if revoke_request:
275:revoke_all = revoke_request.all_tokens or False
276:specific_token_id = revoke_request.token_id
278:revoked_count = 0
280:if revoke_all:
281:# Revoke all user tokens
282:success = await auth_service.revoke_all_user_tokens(user_id)
284:# Count revoked tokens (import RefreshToken if needed)
285:from app.models.refresh_token import RefreshToken
287:revoked_count = await RefreshToken.find(
288:RefreshToken.user_id == user_id, RefreshToken.is_revoked == True
291:"message": "All tokens revoked successfully",
292:"revoked_tokens": revoked_count,
295:raise HTTPException(status_code=500, detail="Failed to revoke tokens")
298:# Revoke specific token
299:success = await auth_service.revoke_refresh_token(specific_token_id)
301:return {"message": "Token revoked successfully", "revoked_tokens": 1}
304:status_code=404, detail="Token not found or already revoked"
308:# Revoke current token (default behavior)
309:success = await auth_service.revoke_refresh_token(current_token_id)
311:return {"message": "Token revoked successfully", "revoked_tokens": 1}
314:status_code=404, detail="Token not found or already revoked"
327:chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
342:if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
431:chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
449:if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
563:chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
579:if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
619:role="user",
965:role="assistant",
1027:request: Request, current_user: Dict = Depends(authenticate_user)
1058:async def get_my_assigned_chatflows(current_user: Dict = Depends(authenticate_user)):
1059:"""Get a list of chatflow IDs the current authenticated user is actively assigned to."""
1063:# This should ideally not happen if authenticate_user works correctly
1089:session_id: str, current_user: Dict = Depends(authenticate_user)
1114:"role": msg.role,
1172:async def get_all_user_sessions(current_user: Dict = Depends(authenticate_user)):
1202:async def delete_user_chat_history(current_user: Dict = Depends(authenticate_user)):
1204:Delete all chat history (sessions and messages) for the authenticated user.
1236:session_id: str, current_user: Dict = Depends(authenticate_user)
1239:Delete a specific chat session and all its messages for the authenticated user.
1287:session_id: str, current_user: Dict = Depends(authenticate_user)
1318:current_user: Dict = Depends(authenticate_user),
1426:current_user: Dict = Depends(authenticate_user),
1541:file_id: str, current_user: Dict = Depends(authenticate_user)
1571:message_id: str, current_user: Dict = Depends(authenticate_user)
```

### fix/remote-login-proxy-url: flowise-proxy-service-py/app/api/chat.py
```
5:from app.auth.middleware import authenticate_user
108:class RefreshRequest(BaseModel):
109:refresh_token: str
112:class RevokeTokenRequest(BaseModel):
182:@router.post("/authenticate")
183:async def authenticate(auth_request: AuthRequest, request: Request):
185:Authenticate user via external auth service and return JWT tokens
190:# Authenticate user via external service
191:auth_result = await external_auth_service.authenticate_user(
200:"refresh_token": auth_result["refresh_token"],
212:@router.post("/refresh")
213:async def refresh_token(refresh_request: RefreshRequest, request: Request):
215:Refresh access token using external auth service - NO MIDDLEWARE DEPENDENCY
216:This endpoint does not use authenticate_user middleware to avoid circular dependency.
221:# Refresh tokens via external auth service (no middleware)
222:refresh_result = await external_auth_service.refresh_token(
223:refresh_request.refresh_token
226:if refresh_result is None:
228:status_code=401, detail="Invalid or expired refresh token"
232:"access_token": refresh_result["access_token"],
233:"refresh_token": refresh_result["refresh_token"],
234:"token_type": refresh_result["token_type"],
240:raise HTTPException(status_code=500, detail=f"Token refresh failed: {str(e)}")
243:@router.post("/revoke")
244:async def revoke_tokens(
246:current_user: Dict = Depends(authenticate_user),
247:revoke_request: Optional[RevokeTokenRequest] = None,
250:Revoke refresh tokens (specific token or all user tokens)
271:revoke_all = False
274:if revoke_request:
275:revoke_all = revoke_request.all_tokens or False
276:specific_token_id = revoke_request.token_id
278:revoked_count = 0
280:if revoke_all:
281:# Revoke all user tokens
282:success = await auth_service.revoke_all_user_tokens(user_id)
284:# Count revoked tokens (import RefreshToken if needed)
285:from app.models.refresh_token import RefreshToken
287:revoked_count = await RefreshToken.find(
288:RefreshToken.user_id == user_id, RefreshToken.is_revoked == True
291:"message": "All tokens revoked successfully",
292:"revoked_tokens": revoked_count,
295:raise HTTPException(status_code=500, detail="Failed to revoke tokens")
298:# Revoke specific token
299:success = await auth_service.revoke_refresh_token(specific_token_id)
301:return {"message": "Token revoked successfully", "revoked_tokens": 1}
304:status_code=404, detail="Token not found or already revoked"
308:# Revoke current token (default behavior)
309:success = await auth_service.revoke_refresh_token(current_token_id)
311:return {"message": "Token revoked successfully", "revoked_tokens": 1}
314:status_code=404, detail="Token not found or already revoked"
327:chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
342:if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
431:chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
449:if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
563:chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
579:if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
619:role="user",
965:role="assistant",
1027:request: Request, current_user: Dict = Depends(authenticate_user)
1058:async def get_my_assigned_chatflows(current_user: Dict = Depends(authenticate_user)):
1059:"""Get a list of chatflow IDs the current authenticated user is actively assigned to."""
1063:# This should ideally not happen if authenticate_user works correctly
1089:session_id: str, current_user: Dict = Depends(authenticate_user)
1114:"role": msg.role,
1172:async def get_all_user_sessions(current_user: Dict = Depends(authenticate_user)):
1202:async def delete_user_chat_history(current_user: Dict = Depends(authenticate_user)):
1204:Delete all chat history (sessions and messages) for the authenticated user.
1236:session_id: str, current_user: Dict = Depends(authenticate_user)
1239:Delete a specific chat session and all its messages for the authenticated user.
1287:session_id: str, current_user: Dict = Depends(authenticate_user)
1318:current_user: Dict = Depends(authenticate_user),
1426:current_user: Dict = Depends(authenticate_user),
1541:file_id: str, current_user: Dict = Depends(authenticate_user)
1571:message_id: str, current_user: Dict = Depends(authenticate_user)
```

## Diff Excerpts

### bridge/src/api/auth.ts
```
diff --git a/bridge/src/api/auth.ts b/bridge/src/api/auth.ts
index 8b96084..7602886 100644
--- a/bridge/src/api/auth.ts
+++ b/bridge/src/api/auth.ts
@@ -1,5 +1,6 @@
 // src/api/auth.ts
 import type { LoginCredentials, LoginResponse } from '../types/auth';
+import { API_BASE_URL } from './config';
 
 /**
  * Authenticates a user against the backend.
@@ -15,7 +16,7 @@ import type { LoginCredentials, LoginResponse } from '../types/auth';
  */
 export const login = async (credentials: LoginCredentials): Promise<LoginResponse> => {
   // Note: We use fetch here instead of apiClient to avoid auth interceptors during login
-  const response = await fetch(`${import.meta.env.VITE_FLOWISE_PROXY_API_URL || 'http://localhost:8000'}/api/v1/chat/authenticate`, {
+  const response = await fetch(`${API_BASE_URL}/api/v1/chat/authenticate`, {
     method: 'POST',
     headers: {
       'Content-Type': 'application/json',
@@ -44,7 +45,7 @@ export const login = async (credentials: LoginCredentials): Promise<LoginRespons
  */
 export const refreshToken = async (token: string): Promise<LoginResponse> => {
   // Note: We use fetch here instead of apiClient to avoid auth interceptors during token refresh
-  const response = await fetch(`${import.meta.env.VITE_FLOWISE_PROXY_API_URL || 'http://localhost:8000'}/api/v1/chat/refresh`, {
+  const response = await fetch(`${API_BASE_URL}/api/v1/chat/refresh`, {
     method: 'POST',
     headers: {
       'Content-Type': 'application/json',
@@ -70,7 +71,7 @@ export const refreshToken = async (token: string): Promise<LoginResponse> => {
 export const logout = async (refreshToken: string, accessToken: string): Promise<void> => {
   try {
     // Call the server to invalidate the refresh token
-    const response = await fetch(`${import.meta.env.VITE_FLOWISE_PROXY_API_URL || 'http://localhost:8000'}/api/v1/chat/revoke`, {
+    const response = await fetch(`${API_BASE_URL}/api/v1/chat/revoke`, {
       method: 'POST',
       headers: {
         'Content-Type': 'application/json',
```

### bridge/src/store/authStore.ts
```
(no diff)
```

### flowise-proxy-service-py/app/api/chat.py
```
(no diff)
```

### flowise-proxy-service-py/app/auth/middleware.py
```
(no diff)
```

### auth-service/src/routes/index.ts
```
(no diff)
```

### auth-service/src/auth/auth.service.ts
```
(no diff)
```

