// Represents the sender of a chat message in the global analysis conversation
// user: the farmer/user typing in the input bar
// assistant: the AI orchestrator's response
enum ChatRole { user, assistant }

// Immutable data model for a single message in the global chat history.
// Used by chatHistoryProvider to store the analysis conversation thread
// displayed alongside the Markdown report in the Report tab.
// Note: for the per-project Chatbot tab thread, plain Map<String, String>
// is used instead (see projectChatHistoryProvider in app_providers.dart).
class ChatMessage {
  // Whether this message was sent by the user or the AI assistant
  final ChatRole role;

  // The message text — may contain Markdown for assistant messages
  final String content;

  // When the message was created — used for ordering and display purposes
  final DateTime timestamp;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });
}