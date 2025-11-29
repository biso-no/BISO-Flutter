import 'package:appwrite/appwrite.dart';
import '../../core/constants/app_constants.dart';

// Simple global instances following Appwrite's recommended pattern
final Client client = Client()
    .setEndpoint(AppConstants.appwriteEndpoint)
    .setProject(AppConstants.appwriteProjectId);

final Account account = Account(client);
final TablesDB db = TablesDB(client);
final Storage storage = Storage(client);
final Realtime realtime = Realtime(client);
final Functions functions = Functions(client);
final Teams teams = Teams(client);
final Messaging messaging = Messaging(client);
