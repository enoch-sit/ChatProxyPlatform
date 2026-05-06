# Logout Branch Evidence

> Historical evidence note: branch names in this snapshot refer to the legacy `main` and `release/aws` workflow, not the current promotion model.

Date: 2026-04-15 11:00:52
Base branch: main (324e23d14307a90b410ad5071833521f90c62cc4)
Target branch: release/aws (35dc12cce1d1e8e397bf97951cc98e3a18b1e67d)
Current branch: release/aws

## Changed Critical Files
- auth-service/docker-compose.dev.yml
- auth-service/src/auth/auth.service.ts
- auth-service/src/routes/index.ts
- bridge/src/api/auth.ts
- bridge/src/store/authStore.ts
- flowise-proxy-service-py/app/api/chat.py
- flowise-proxy-service-py/app/auth/middleware.py

## Frontend Auth Evidence

### main: bridge/src/api/auth.ts
```
5:* Authenticates a user against the backend.
8:* @returns A promise that resolves with the login response, including access and refresh tokens.
10:* @evidence This function implements the client-side logic for the `/api/v1/chat/authenticate`
18:const response = await fetch(`${import.meta.env.VITE_FLOWISE_PROXY_API_URL || 'http://localhost:8000'}/api/v1/chat/authenticate`, {
28:throw new Error(errorData.message || `Authentication failed: ${response.status}`);
35:* Refreshes an expired access token using a refresh token.
37:* @param token The refresh token.
41:* `refresh_token` in the authentication response implies the existence of a refresh mechanism.
42:* This function implements the standard client-side logic for a `/api/v1/chat/refresh` endpoint,
45:export const refreshToken = async (token: string): Promise<LoginResponse> => {
46:// Note: We use fetch here instead of apiClient to avoid auth interceptors during token refresh
47:const response = await fetch(`${import.meta.env.VITE_FLOWISE_PROXY_API_URL || 'http://localhost:8000'}/api/v1/chat/refresh`, {
52:body: JSON.stringify({ refresh_token: token }),
57:throw new Error(errorData.message || `Token refresh failed: ${response.status}`);
64:* Logs out a user and invalidates their refresh token on the server.
66:* @param refreshToken The refresh token to invalidate.
68:* @returns A promise that resolves when logout is complete.
70:export const logout = async (refreshToken: string, accessToken: string): Promise<void> => {
72:// Call the server to invalidate the refresh token
73:const response = await fetch(`${import.meta.env.VITE_FLOWISE_PROXY_API_URL || 'http://localhost:8000'}/api/v1/chat/revoke`, {
79:body: JSON.stringify({ refresh_token: refreshToken }),
83:console.warn('Logout request failed, but continuing with local cleanup');
86:console.warn('Logout request error, but continuing with local cleanup:', error);
```

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

## Backend Auth Evidence

### main: flowise-proxy-service-py/app/api/chat.py
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
342:if not await auth_service.validate_user_permissions(user_id, chatflow_id):
431:chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
449:if not await auth_service.validate_user_permissions(user_id, chatflow_id):
563:chat_request: ChatRequest, current_user: Dict = Depends(authenticate_user)
579:if not await auth_service.validate_user_permissions(user_id, chatflow_id):
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

## Diff Excerpts

### bridge/src/api/auth.ts
```
diff --git a/bridge/src/api/auth.ts b/bridge/src/api/auth.ts
index 8b96084..581a1ae 100644
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
@@ -25,7 +26,8 @@ export const login = async (credentials: LoginCredentials): Promise<LoginRespons
 
   if (!response.ok) {
     const errorData = await response.json().catch(() => ({}));
-    throw new Error(errorData.message || `Authentication failed: ${response.status}`);
+    // FastAPI returns errors in "detail" field, but also check "message" for compatibility
+    throw new Error(errorData.detail || errorData.message || `Authentication failed: ${response.status}`);
   }
 
   return response.json();
@@ -44,7 +46,7 @@ export const login = async (credentials: LoginCredentials): Promise<LoginRespons
  */
 export const refreshToken = async (token: string): Promise<LoginResponse> => {
   // Note: We use fetch here instead of apiClient to avoid auth interceptors during token refresh
-  const response = await fetch(`${import.meta.env.VITE_FLOWISE_PROXY_API_URL || 'http://localhost:8000'}/api/v1/chat/refresh`, {
+  const response = await fetch(`${API_BASE_URL}/api/v1/chat/refresh`, {
     method: 'POST',
     headers: {
       'Content-Type': 'application/json',
@@ -54,7 +56,7 @@ export const refreshToken = async (token: string): Promise<LoginResponse> => {
 
   if (!response.ok) {
     const errorData = await response.json().catch(() => ({}));
-    throw new Error(errorData.message || `Token refresh failed: ${response.status}`);
+    throw new Error(errorData.detail || errorData.message || `Token refresh failed: ${response.status}`);
   }
 
   return response.json();
@@ -70,7 +72,7 @@ export const refreshToken = async (token: string): Promise<LoginResponse> => {
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
diff --git a/bridge/src/store/authStore.ts b/bridge/src/store/authStore.ts
index 2618765..84d7c67 100644
--- a/bridge/src/store/authStore.ts
+++ b/bridge/src/store/authStore.ts
@@ -49,6 +49,14 @@ const ROLE_PERMISSIONS: Record<User['role'], string[]> = {
     'view_all_sessions',
     'view_all_messages',
   ],
+  teacher: [
+    'manage_users',
+    'manage_chatflows',
+    'view_analytics',
+    'access_admin_panel',
+    'view_all_sessions',
+    'view_all_messages',
+  ],
   enduser: [
     'create_sessions',
     'send_messages',
```

### flowise-proxy-service-py/app/api/chat.py
```
diff --git a/flowise-proxy-service-py/app/api/chat.py b/flowise-proxy-service-py/app/api/chat.py
index 4b133d5..41d5b92 100644
--- a/flowise-proxy-service-py/app/api/chat.py
+++ b/flowise-proxy-service-py/app/api/chat.py
@@ -339,7 +339,7 @@ async def chat_predict(
         chatflow_id = chat_request.chatflow_id
 
         # 1. Validate user has access to chatflow
-        if not await auth_service.validate_user_permissions(user_id, chatflow_id):
+        if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
             raise HTTPException(
                 status_code=403, detail="Access denied to this chatflow"
             )
@@ -446,7 +446,7 @@ async def chat_predict_stream(
         chatflow_id = chat_request.chatflow_id
 
         # 1. Validate user has access to chatflow
-        if not await auth_service.validate_user_permissions(user_id, chatflow_id):
+        if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
             raise HTTPException(
                 status_code=403, detail="Access denied to this chatflow"
             )
@@ -576,7 +576,7 @@ async def chat_predict_stream_store(
         chatflow_id = chat_request.chatflow_id
 
         # 1. Validate user has access to chatflow
-        if not await auth_service.validate_user_permissions(user_id, chatflow_id):
+        if not await auth_service.validate_user_permissions(user_id, chatflow_id, current_user.get("role")):
             raise HTTPException(
                 status_code=403, detail="Access denied to this chatflow"
             )
```

### flowise-proxy-service-py/app/auth/middleware.py
```
diff --git a/flowise-proxy-service-py/app/auth/middleware.py b/flowise-proxy-service-py/app/auth/middleware.py
index a734868..766e646 100644
--- a/flowise-proxy-service-py/app/auth/middleware.py
+++ b/flowise-proxy-service-py/app/auth/middleware.py
@@ -14,8 +14,12 @@ security = HTTPBearer()
 ADMIN_ROLE = 'admin'
 USER_ROLE = 'user' # This seems to be used as a general 'non-admin' identifier in some places
 SUPERVISOR_ROLE = 'supervisor' # Added for the new function
+TEACHER_ROLE = 'teacher'  # Teacher role - elevated privileges for managing students
 ENDUSER_ROLE = 'enduser' # Assuming this is the most basic role
 
+# Roles with elevated (admin-level) access
+ELEVATED_ROLES = {ADMIN_ROLE, SUPERVISOR_ROLE, TEACHER_ROLE}
+
 # Role hierarchy constants (optional, but good for clarity if you have more complex rules
 #   ADMIN_ROLE = 'admin',        // Highest privilege level - full system access
 #   SUPERVISOR_ROLE = 'supervisor', // Mid-level privilege - user management
@@ -201,13 +205,27 @@ async def require_admin_role(current_user: Dict = Depends(authenticate_user)) ->
 
 async def require_admin_or_supervisor_role(current_user: Dict = Depends(authenticate_user)) -> Dict:
     """
-    Dependency to enforce that the current user has either 'admin' or 'supervisor' role.
+    Dependency to enforce that the current user has either 'admin', 'supervisor', or 'teacher' role.
+    """
+    user_role = current_user.get('role')
+    if user_role not in [ADMIN_ROLE, SUPERVISOR_ROLE, TEACHER_ROLE]:
+        raise HTTPException(
+            status_code=403,
+            detail="Access denied. Administrator, Supervisor, or Teacher privileges required."
+        )
+    return current_user
+
+
+async def require_elevated_role(current_user: Dict = Depends(authenticate_user)) -> Dict:
+    """
+    Dependency that allows admin, supervisor, or teacher roles.
+    Use this for management endpoints that teachers should also access.
     """
     user_role = current_user.get('role')
-    if user_role not in [ADMIN_ROLE, SUPERVISOR_ROLE]:
+    if user_role not in ELEVATED_ROLES:
         raise HTTPException(
             status_code=403,
-            detail="Access denied. Administrator or Supervisor privileges required."
+            detail="Access denied. Elevated privileges (admin, supervisor, or teacher) required."
         )
     return current_user
 
```

### auth-service/src/routes/index.ts
```
diff --git a/auth-service/src/routes/index.ts b/auth-service/src/routes/index.ts
index b498fb6..d0594a1 100644
--- a/auth-service/src/routes/index.ts
+++ b/auth-service/src/routes/index.ts
@@ -1,6 +1,6 @@
 // src/routes/index.ts
-import { Router, Request, Response } from 'express';
-import { authenticate, isAdmin, requireAdmin, requireSupervisor, optionalAuth } from '../auth/auth.middleware'; // Added isAdmin
+import { Router, Request, Response, NextFunction } from 'express';
+import { authenticate, isAdmin, requireAdmin, requireAdminOrTeacher, requireSupervisor, optionalAuth } from '../auth/auth.middleware';
 import { User, UserRole } from '../models/user.model';
 import { authService } from '../auth/auth.service';
 import { passwordService } from '../services/password.service';
@@ -436,7 +436,7 @@ protectedRouter.get('/dashboard', authenticate, (req: Request, res: Response) =>
 // =============================================================================
 
 // Get all users (admin only)
-adminRouter.get('/users', authenticate, requireAdmin, async (req: Request, res: Response) => {
+adminRouter.get('/users', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
   try {
     const users = await User.find().select('-password');
     res.status(200).json({ users });
@@ -446,8 +446,8 @@ adminRouter.get('/users', authenticate, requireAdmin, async (req: Request, res:
   }
 });
 
-// Get user by ID (Admin only)
-adminRouter.get('/users/:userId', authenticate, isAdmin, async (req: Request, res: Response) => {
+// Get user by ID (Admin or teacher)
+adminRouter.get('/users/:userId', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
   try {
     const { userId } = req.params;
 
@@ -480,8 +480,8 @@ adminRouter.get('/users/:userId', authenticate, isAdmin, async (req: Request, re
   }
 });
 
-// Get user by email (admin only)
-adminRouter.get('/users/by-email/:email', authenticate, requireAdmin, async (req: Request, res: Response) => {
+// Get user by email (admin or teacher)
+adminRouter.get('/users/by-email/:email', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
   // GET /api/admin/users/by-email/:email
   try {
     const { email } = req.params;
@@ -504,10 +504,10 @@ adminRouter.get('/users/by-email/:email', authenticate, requireAdmin, async (req
 });
 
 
-// Create a new user (admin only)
-adminRouter.post('/users', authenticate, requireAdmin, async (req: Request, res: Response) => {
+// Create a new user (admin or teacher)
+adminRouter.post('/users', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
   try {
-    const { username, email, password, role, skipVerification } = req.body;
+    const { username, email, password, role, skipVerification = true } = req.body;
     
     // Validate required fields
     if (!username || !email || !password) {
@@ -531,7 +531,7 @@ adminRouter.post('/users', authenticate, requireAdmin, async (req: Request, res:
       email,
       password,
       role || UserRole.ENDUSER,
-      skipVerification === true
+      skipVerification !== false
     );
     
     if (!result.success) {
@@ -549,8 +549,8 @@ adminRouter.post('/users', authenticate, requireAdmin, async (req: Request, res:
   }
 });
 
-// Create multiple users at once (admin only)
-adminRouter.post('/users/batch', authenticate, requireAdmin, async (req: Request, res: Response) => {
+// Create multiple users at once (admin or teacher)
+adminRouter.post('/users/batch', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
   try {
     const { users, skipVerification = true } = req.body;
     
@@ -589,7 +589,7 @@ adminRouter.post('/users/batch', authenticate, requireAdmin, async (req: Request
     // Create the users in batch
     const result = await authService.adminCreateBatchUsers(
       users,
-      skipVerification === true
+      skipVerification !== false
     );
     
     logger.info(`Batch user creation by admin ${req.user?.username}. Created: ${result.summary.successful}, Failed: ${result.summary.failed}, Total: ${result.summary.total}`);
@@ -634,8 +634,8 @@ adminRouter.put('/users/:userId/role', authenticate, requireAdmin, async (req: R
   }
 });
 
-// Delete a specific user (admin only)
-adminRouter.delete('/users/:userId', authenticate, requireAdmin, async (req: Request, res: Response) => {
+// Delete a specific user (admin or teacher)
+adminRouter.delete('/users/:userId', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
   try {
     const { userId } = req.params;
     
@@ -731,10 +731,101 @@ adminRouter.get('/reports', authenticate, requireSupervisor, (req: Request, res:
   });
 });
 
+// Admin/teacher password reset - set a user's password directly
+adminRouter.put('/users/:userId/password', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
+  try {
+    const { userId } = req.params;
+    const { newPassword } = req.body;
+
+    if (!mongoose.Types.ObjectId.isValid(userId)) {
+      return res.status(400).json({ error: 'Invalid user ID format' });
+    }
+    if (!newPassword || typeof newPassword !== 'string' || newPassword.length < 8) {
+      return res.status(400).json({ error: 'New password must be at least 8 characters' });
+    }
+
+    const user = await User.findById(userId);
+    if (!user) {
+      return res.status(404).json({ error: 'User not found' });
+    }
+
... (truncated)
```

### auth-service/src/auth/auth.service.ts
```
diff --git a/auth-service/src/auth/auth.service.ts b/auth-service/src/auth/auth.service.ts
index 8885f02..94a584e 100644
--- a/auth-service/src/auth/auth.service.ts
+++ b/auth-service/src/auth/auth.service.ts
@@ -370,7 +370,7 @@ export class AuthService {
    * @param email - The email address of the new user.
    * @param password - The password for the new user (will be hashed before storage).
    * @param role - The role to assign to the new user.
-   * @param skipVerification - Whether to mark the user as verified immediately (optional).
+   * @param skipVerification - Whether to mark the user as verified immediately (defaults to true for immediate login).
    * @returns A Promise that resolves to a SignupResult object indicating the success or failure of the user creation.
    */
   async adminCreateUser(
@@ -378,7 +378,7 @@ export class AuthService {
     email: string, 
     password: string, 
     role: UserRole = UserRole.USER,
-    skipVerification: boolean = false
+    skipVerification: boolean = true
   ): Promise<SignupResult> {
     try {
       // Check if the provided username already exists in the database
```

