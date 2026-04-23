class AppConstants {
  static const String appName = 'BISO';

  // Appwrite Configuration
  static const String appwriteEndpoint = 'https://appwrite.biso.no/v1';
  static const String appwriteProjectId = 'dev';
  static const String databaseId = 'app';
  static const String appwriteWebsocket = 'wss://appwrite.biso.no/v1/realtime';
  // Storage Buckets
  static const String productsBucketId = 'products';
  static const String expensesBucketId = 'expenses';

  // Collections
  static const String expensesCollectionId = 'expense';
  static const String expenseAttachmentsCollectionId = 'expense_attachments';
  static const String campusesCollectionId = 'campus';
  static const String departmentsCollectionId = 'departments';
  static const String contentTranslationsCollectionId = 'content_translations';
  static const String usersCollectionId = 'user';
  static const String featureFlagsCollectionId = 'feature_flags';
  static const String chatMessagesCollectionId = 'chat_messages';
  static const String chatParticipantsCollectionId = 'chat_participants';
  static const String chatRoomsCollectionId = 'chat_rooms';

  // API Service
  static const String apiBaseUrl = 'https://api.biso.no';
  static const String apiUrl = 'https://api.biso.no/api'; // For backward compatibility
  static const String publicAssistantEndpoint = '/api/public-assistant';
  // Appwrite Functions (IDs)
  static const String fnParseReceiptId = 'fn_parse_receipt';
  static const String fnSummarizeExpenseId = 'fn_summarize_expense';
  static const String fnFetchEventsId = 'fetch_events';
  static const String fnFetchJobsId = 'fetch_jobs';
  static const String fnSyncWebshopProductsId = 'sync_webshop_products';

  // External APIs
  static const String wordPressEventsApi =
      'https://biso.no/wp-json/biso/v1/events';

  // Email Domains
  static const List<String> allowedEmailDomains = ['bi.no', 'biso.no'];

  // Norwegian Bank Account
  static const int bankAccountLength = 11;

  // Pagination
  static const int defaultPageSize = 20;

  // File Upload
  static const List<String> supportedImageFormats = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
  ];
  static const List<String> supportedDocumentFormats = ['pdf'];
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB

  // OTP
  static const int otpLength = 6;
  static const Duration otpTimeout = Duration(minutes: 10);

  // Campus IDs
  static const String osloId = '1';
  static const String bergenId = '2';
  static const String trondheimId = '3';
  static const String stavangerId = '4';
}
