
/**
 * Represents a single chatflow instance.
 * This type is used throughout the admin panel to display and manage chatflows.
 */
// src/types/chatflow.ts - 創建新的統一類型文件
export interface Chatflow {
  _id: string;
  id: string;           // 添加這個屬性以兼容舊代碼
  flowise_id: string;   // 保留這個屬性用於 API 調用
  name: string;
  description: string;
  deployed: boolean;
  is_public: boolean;
  category: string | null;
  type: "CHATFLOW" | "AGENTFLOW";
  api_key_id?: string;
  flow_data?: {
    nodes: Array<{
      id: string;
      type: string;
      position: { x: number; y: number };
      data: any;
    }>;
    edges: Array<{
      source: string;
      target: string;
      data?: any;
    }>;
    viewport?: {
      x: number;
      y: number;
      zoom: number;
    };
  };
  chatbot_config?: any;
  api_config?: any;
  analytic_config?: any;
  speech_to_text_config?: any;
  created_date: string;
  updated_date: string;
  synced_at?: string;
  sync_status: "active" | "inactive" | "error";
  sync_error?: string | null;
  session_id?: string | null; // specify a session
}

export interface ChatflowUser {
  _id?: string;
  username: string;
  email: string;
  role?: string;
  assigned_at: string;
  external_user_id?: string;
}
/**
 * Defines the structure for chatflow statistics.
 * This is used on the admin dashboard to provide a high-level overview.
 */
export interface ChatflowStats {
  total: number;
  active: number;
  deleted: number;
  error: number;
  last_sync?: string;
}

export interface ChatflowSyncResult {
  total_fetched: number;
  created: number;
  updated: number;
  deleted: number;
  errors: number;
  error_details?: Array<Record<string, string>>;
}
