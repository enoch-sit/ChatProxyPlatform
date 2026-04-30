import type {Message} from "../types/chat";

export function mapHistoryToMessages(history: any[]): Message[] {
  console.log('📜 Mapping history to messages, raw history:', history);
  
  const mappedMessages = history.map((item, index) => {
    console.log('📜 Processing history item:', item);
    
    // Use uploads if available (from enhanced history API), otherwise convert file_ids
    let uploads = [];
    if (item.uploads && Array.isArray(item.uploads)) {
      // Enhanced history API provides complete file metadata
      uploads = item.uploads.map((upload: any) => ({
        id: upload.file_id || upload.id,
        name: upload.name,
        size: upload.size || 0,
        type: upload.mime || upload.type || 'unknown',
        url: upload.url || `/api/v1/chat/files/${upload.file_id || upload.id}`,
        thumbnail_small: upload.thumbnail_small || `/api/v1/chat/files/${upload.file_id || upload.id}/thumbnail?size=100`,
        thumbnail_medium: upload.thumbnail_medium || `/api/v1/chat/files/${upload.file_id || upload.id}/thumbnail?size=300`,
        thumbnail_large: upload.thumbnail_large || `/api/v1/chat/files/${upload.file_id || upload.id}/thumbnail?size=500`,
        is_image: upload.is_image || upload.mime?.startsWith('image/') || false,
        created_at: upload.uploaded_at || upload.created_at || new Date().toISOString(),
        session_id: item.session_id
      }));
    } else if (item.file_ids && Array.isArray(item.file_ids)) {
      // Fallback: convert file_ids to basic upload structure
      uploads = item.file_ids.map((fileId: string) => ({
        id: fileId,
        name: `file_${fileId}`,
        size: 0,
        type: 'unknown',
        url: `/api/v1/chat/files/${fileId}`,
        thumbnail_small: `/api/v1/chat/files/${fileId}/thumbnail?size=100`,
        thumbnail_medium: `/api/v1/chat/files/${fileId}/thumbnail?size=300`,
        thumbnail_large: `/api/v1/chat/files/${fileId}/thumbnail?size=500`,
        is_image: true, // Assume images for now
        created_at: new Date().toISOString(),
        session_id: item.session_id
      }));
    }
    
    const baseMessage = {
      id: item.id || `history-${index}-${Date.now()}`, // Ensure every message has an ID
      session_id: item.session_id,
      timestamp: item.created_at,
      uploads: uploads,
    };

    if (item.role === "assistant" && typeof item.content === "string" && item.content.trim().startsWith("[")) {
      try {
        const events = JSON.parse(item.content);
        // Filter to only include token events in history
        const tokenEvents = Array.isArray(events)
          ? events.filter((event: any) => event && event.event === 'token')
          : [];
        // Reconstruct plain text from the token stream so consumers that
        // only render `content` (e.g. AdminChatHistoryPanel) can show the
        // AI response. Keep streamEvents for richer renderers.
        const reconstructed = tokenEvents
          .map((event: any) => (typeof event.data === 'string' ? event.data : ''))
          .join('');
        return {
          ...baseMessage,
          role: item.role,
          content: reconstructed,
          sender: "bot",
          streamEvents: tokenEvents,
        };
      } catch {
        // fallback
        return {
          ...baseMessage,
          role: item.role,
          content: item.content,
          sender: "bot",
        };
      }
    }
    return {
      ...baseMessage,
      role: item.role,
      content: item.content,
      sender: item.role === "user" ? "user" : "bot",
    };
  });
  
  console.log('📜 Mapped messages:', mappedMessages);
  return mappedMessages;
}