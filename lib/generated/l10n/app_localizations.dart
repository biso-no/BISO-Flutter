import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_no.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('no'),
  ];

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'BISO'**
  String get appName;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'About BISO'**
  String get aboutMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'About this role'**
  String get aboutThisRoleMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Academic Calendar'**
  String get academicCalendarMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Access to member-only discussion groups'**
  String get accessToMemberOnlyDiscussionGroupsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Account Holder'**
  String get accountHolderMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Account number is required'**
  String get accountNumberIsRequiredMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Account Type'**
  String get accountTypeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Add context (optional)'**
  String get addContextOptionalMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Add your bank account information to receive expense reimbursements from BISO.'**
  String
  get addYourBankAccountInformationToReceiveExpenseReimbursementsFromBISOMessage;

  /// Auto-extracted string (used in 4 files)
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get addedToFavoritesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Address Information'**
  String get addressInformationMessage;

  /// Auto-extracted string (used in 4 files)
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Advanced app features and tools'**
  String get advancedAppFeaturesAndToolsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistantMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'All-Access Pass'**
  String get allAccessPassMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'All departments'**
  String get allDepartmentsMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Amount (NOK)'**
  String get amountNOKMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get appLanguageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'App Version'**
  String get appVersionMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Apply Now'**
  String get applyNowMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approvedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this chat? This action cannot be undone.'**
  String get areYouSureYouWantToDeleteThisChatThisActionCannotBeUndone;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove your student ID? This will remove your verified status and access to student benefits.'**
  String
  get areYouSureYouWantToRemoveYourStudentIDThisWillRemoveYourVerifiedStatusAndAccessToStudentBenefitsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get areYouSureYouWantToSignOutMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Ask AI Assistant'**
  String get askAIMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Attached Files'**
  String get attachedFilesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachmentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Authentication required. Please log in again.'**
  String get authenticationRequiredPleaseLogInAgainMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Auto-delete Messages'**
  String get autoDeleteMessagesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Auto-delete options coming soon'**
  String get autoDeleteOptionsComingSoonMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Auto-download Media'**
  String get autoDownloadMediaMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Auto-download options coming soon'**
  String get autoDownloadOptionsComingSoonMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Auto-fill date, amount and description from receipts'**
  String get autoFillDateAmountAndDescriptionFromReceiptsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Automatically delete old messages'**
  String get automaticallyDeleteOldMessagesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Bank Account'**
  String get bankAccountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Bank account number is required'**
  String get bankAccountNumberIsRequiredMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Bank Account Number'**
  String get bankAccountNumberMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'BI {selectedCampus}'**
  String biSelectedCampusNameMessage(String selectedCampus);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'BISO {widget}'**
  String bisoCampusNameMessage(String widget);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'BISO Member'**
  String get bisoMemberMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'BISO Membership'**
  String get bisoMembershipMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'BISO Shop'**
  String get bisoShopMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'BISO Webshop'**
  String get bisoWebshopMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Book rooms & resources'**
  String get bookRoomsResourcesMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get booksMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Brand New'**
  String get brandNewMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Browse as Guest'**
  String get browseAsGuestMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'1.0.0 (Build 1)'**
  String get build1Message;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get busMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Buy & sell items'**
  String get buyAndSellItemsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Buy Membership'**
  String get buyMembershipMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Buy Pass'**
  String get buyPassMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Buy & sell items'**
  String get buySellItemsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'by {event}'**
  String byOrganizerNameMessage(String event);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'By submitting, you confirm that all information is accurate and you have appropriate receipts.'**
  String
  get bySubmittingYouConfirmThatAllInformationIsAccurateAndYouHaveAppropriateReceiptsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Cache cleared successfully'**
  String get cacheClearedSuccessfullyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Campus & Department'**
  String get campusAndDepartmentMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Campus & Interests'**
  String get campusAndInterestsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Campus events & activities'**
  String get campusEventsActivitiesMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Campus Information'**
  String get campusInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Campus Leadership'**
  String get campusLeadershipMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Campus'**
  String get campusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Auto-extracted string (used in 6 files)
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelledMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Card Payment'**
  String get cardPaymentMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Career Advantages'**
  String get careerAdvantagesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat Behavior'**
  String get chatBehaviorMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat deleted successfully'**
  String get chatDeletedSuccessfully;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat Info'**
  String get chatInfo;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat Messages'**
  String get chatMessagesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat muted'**
  String get chatMuted;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat Notifications'**
  String get chatNotificationsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat Privacy'**
  String get chatPrivacyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat Privacy Settings'**
  String get chatPrivacySettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat settings apply to all conversations. Individual chat settings can be changed from the chat info screen.'**
  String
  get chatSettingsApplyToAllConversationsIndividualChatSettingsCanBeChangedFromTheChatInfoScreenMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat Settings'**
  String get chatSettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat Storage'**
  String get chatStorageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Chat unmuted'**
  String get chatUnmuted;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Check back later or switch campus'**
  String get checkBackLaterOrSwitchCampusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'• Check membership status\\n• Purchase BISO membership\\n• Access exclusive features\\n• Expense reimbursements'**
  String
  get checkMembershipStatusPurchaseBISOmembershipAccessExclusiveFeaturesExpenseReimbursementsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Checking permissions...'**
  String get checkingPermissionsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Choose how others can find and contact you:'**
  String get chooseHowOthersCanFindAndContactYouMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Choose what notifications you want to receive'**
  String get chooseWhatNotificationsYouWantToReceiveMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Choose your BI campus location'**
  String get chooseYourBICampusLocationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Choose your campus and the department responsible for this expense'**
  String get chooseYourCampusAndTheDepartmentResponsibleForThisExpenseMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Choose your membership plan'**
  String get chooseYourMembershipPlanMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get cityMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get clearCacheMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Clear Session & Try Again'**
  String get clearSessionAndTryAgainMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Clear session'**
  String get clearSessionMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Clothes'**
  String get clothesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Clubs'**
  String get clubsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Clubs & Units'**
  String get clubsUnitsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Compensation'**
  String get compensationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Complete Profile'**
  String get completeProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Complete Setup'**
  String get completeSetupMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Complete Your Profile'**
  String get completeYourProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get conditionMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Connect BI Account'**
  String get connectBIAccountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Connect with your BI student account for instant verification and access to exclusive member features.'**
  String
  get connectWithYourBIStudentAccountForInstantVerificationAndAccessToExclusiveMemberFeaturesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Contact info (optional)'**
  String get contactInfoOptionalMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Contact Information'**
  String get contactInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contactMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Contact Seller'**
  String get contactSellerMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButtonMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Continue to login'**
  String get continueToLoginMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Copy token for testing'**
  String get copyTokenForTestingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Could not open mail app. Please check your email manually.'**
  String get couldNotOpenMailAppMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createdMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Currency is automatically set to NOK for BI students'**
  String get currencyIsAutomaticallySetToNOKForBIStudentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'{event}/{event} registered'**
  String currentAttendeesMaxAttendeesRegisteredMessage(String event);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Current Campus'**
  String get currentCampusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkModeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Data & Storage'**
  String get dataAndStorageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Date Format'**
  String get dateFormatMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Date format options coming soon'**
  String get dateFormatOptionsComingSoonMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'{date}/{date}/{date}'**
  String dateMessage(String date);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'DD/MM/YYYY (Norwegian)'**
  String get ddMMyyyyNorwegianMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get deadlineMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Delayed +{deltaMinutes}m'**
  String delayedMinutesMessage(String deltaMinutes);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Delete Chat'**
  String get deleteChat;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Departed \$minutesTo min ago'**
  String get departedMinutesAgoMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Department chat • {chat} members'**
  String departmentChatMembers(String chat);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get departmentMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Departments'**
  String get departments;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Departures'**
  String get departuresMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Describe briefly what the expense is for'**
  String get describeBrieflyWhatTheExpenseIsForMessage;

  /// Auto-extracted string (used in 4 files)
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Details & Summary'**
  String get detailsAndSummaryMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'DEUTDEFF'**
  String get deutdeffMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get direct;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Direct message'**
  String get directMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Directions'**
  String get directionsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Discover events and opportunities'**
  String get discoverEventsAndOpportunitiesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Discover happenings'**
  String get discoverHappeningsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Discover student-driven organizations at {campus}'**
  String discoverStudentDrivenOrganizationsAtMessage(String campus);

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Document Stats'**
  String get documentStatsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Download photos and files automatically'**
  String get downloadPhotosAndFilesAutomaticallyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draftMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Draft saved'**
  String get draftSavedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'• Draft: Your local draft before submission.\\n'**
  String get draftYourLocalDraftBeforeSubmissionMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Early {deltaMinutes}m'**
  String earlyMinutesMessage(String deltaMinutes);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Early registration for popular events'**
  String get earlyRegistrationForPopularEventsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'e.g., MacBook Pro 13\"'**
  String get egMacBookPro13Message;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get electronicsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// Auto-extracted string (used in 4 files)
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enableMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Enable Notifications'**
  String get enableNotificationsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Enable system notifications first'**
  String get enableSystemNotificationsFirstMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get endedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get enterAValidAmountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Enter email'**
  String get enterEmail;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Enter valid email'**
  String get enterValidEmail;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Enter your international account number'**
  String get enterYourInternationalAccountNumberMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Error enabling notifications: \$e'**
  String get errorEnablingNotificationsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Error loading board members'**
  String get errorLoadingBoardMembersMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Error loading expenses'**
  String get errorLoadingExpensesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Error loading notification settings'**
  String get errorLoadingNotificationSettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Error loading privacy settings'**
  String get errorLoadingPrivacySettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Error occurred'**
  String get errorMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Error picking image: \$e'**
  String get errorPickingImageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Error updating profile: \$e'**
  String get errorUpdatingProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Event access • Expense reimbursements • Marketplace discounts • Priority support'**
  String
  get eventAccessExpenseReimbursementsMarketplaceDiscountsPrioritySupportMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get eventMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Events & Tickets'**
  String get eventsAndTicketsMessage;

  /// Auto-extracted string (used in 8 files)
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get eventsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Exclusive Chat Channels'**
  String get exclusiveChatChannelsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Exclusive deals on marketplace items'**
  String get exclusiveDealsOnMarketplaceItemsMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Expense Details'**
  String get expenseDetailsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Expense History'**
  String get expenseHistoryMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Expense Reimbursement'**
  String get expenseReimbursementMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Expense reimbursement status updates'**
  String get expenseReimbursementStatusUpdatesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Expense reimbursements'**
  String get expenseReimbursementsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Expense Statuses'**
  String get expenseStatusesMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Expense submitted'**
  String get expenseSubmittedMessage;

  /// Auto-extracted string (used in 5 files)
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Expires in {remainingSeconds}s'**
  String expiresInRemainingSecondsMessage(String remainingSeconds);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Explore Campus'**
  String get exploreCampusMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get exploreMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get facebookMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to delete chat: \$e'**
  String get failedToDeleteChat;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to generate verification token.'**
  String get failedToGenerateVerificationTokenMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to load board members'**
  String get failedToLoadBoardMembersMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to load campuses'**
  String get failedToLoadCampusesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to load chats'**
  String get failedToLoadChats;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to load content'**
  String get failedToLoadContentMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to load membership options: {e}'**
  String failedToLoadMembershipOptionsMessage(String e);

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Failed to load'**
  String get failedToLoadMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to load product: \$e'**
  String get failedToLoadProductMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to load socials: \$e'**
  String get failedToLoadSocialsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to load stop places'**
  String get failedToLoadStopPlacesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to publish: \$e'**
  String get failedToPublishMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to resend code: \$e'**
  String get failedToResendCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to save draft: \$e'**
  String get failedToSaveDraftMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to save payment information: \$e'**
  String get failedToSavePaymentInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to send message: \$e'**
  String get failedToSendMessageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to submit: \$e'**
  String get failedToSubmitMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Failed to update favorite: \$e'**
  String get failedToUpdateFavoriteMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to update privacy setting: \$e'**
  String get failedToUpdatePrivacySetting;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to update privacy setting: \$e'**
  String get failedToUpdatePrivacySettingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Failed to update setting: \$e'**
  String get failedToUpdateSettingMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get fairMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Featured Event'**
  String get featuredEventMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Featured Opportunity'**
  String get featuredOpportunityMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Featured Product'**
  String get featuredProductMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'{attachedFiles} file(s) attached'**
  String fileSAttachedMessage(String attachedFiles);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get filesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Find opportunities'**
  String get findOpportunitiesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Find us online'**
  String get findUsOnlineMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'For Business'**
  String get forBusinessMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'For faster Vipps processing'**
  String get forFasterVippsProcessingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'For prepayments, you can upload quotes or estimates'**
  String get forPrepaymentsYouCanUploadQuotesOrEstimatesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'For Students'**
  String get forStudentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Free up storage space'**
  String get freeUpStorageSpaceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'From Gallery'**
  String get fromGalleryMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Furniture'**
  String get furnitureMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get galleryMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Generating...'**
  String get generatingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Get a Code Instead'**
  String get getACodeInsteadMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Get access to exclusive events, discounts, and more'**
  String get getAccessToExclusiveEventsDiscountsAndMoreMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Get help & guidance'**
  String get getHelpGuidanceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Get help & information'**
  String get getHelpInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Get notified about new campus events'**
  String get getNotifiedAboutNewCampusEventsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Get notified when you receive new messages in chat.'**
  String get getNotifiedWhenYouReceiveNewMessagesInChatMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Get the most out of BISO by completing your profile with campus and contact information.'**
  String
  get getTheMostOutOfBISOByCompletingYourProfileWithCampusAndContactInformationMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get goodMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Guidelines'**
  String get guidelinesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Happening at {campus}'**
  String happeningAtMessage(String campus);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Heart items you like to see them here!'**
  String get heartItemsYouLikeToSeeThemHereMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'ID: \$verificationCode'**
  String get idVerificationCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'If you leave now, your changes will not be saved.'**
  String get ifYouLeaveNowYourChangesWillNotBeSavedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'📷 Image'**
  String get image;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Important Announcement'**
  String get importantAnnouncementMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'In-app message'**
  String get inAppMessageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'In {diff} min'**
  String inMinutesMessage(String diff);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Instagram'**
  String get instagramMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Interests & Departments'**
  String get interestsDepartmentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get interestsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'International Account Number'**
  String get internationalAccountNumberMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'International Bank Account'**
  String get internationalBankAccountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Invalid Norwegian bank account number'**
  String get invalidNorwegianBankAccountNumberMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Invalid OTP code'**
  String get invalidOtpCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Invalid zip code'**
  String get invalidZipCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Job Opportunities'**
  String get jobOpportunitiesMessage;

  /// Auto-extracted string (used in 4 files)
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get jobsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Keep Editing'**
  String get keepEditingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Keep Private'**
  String get keepPrivateMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Language changes will take effect after restarting the app.'**
  String get languageChangesWillTakeEffectAfterRestartingTheAppMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Language Settings'**
  String get languageSettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Last Seen'**
  String get lastSeenMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Learn More'**
  String get learnMoreMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Library Services'**
  String get libraryServicesMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Like New'**
  String get likeNewMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'LinkedIn'**
  String get linkedInMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get liveMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Loading board members...'**
  String get loadingBoardMembersMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Loading notification settings...'**
  String get loadingNotificationSettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Loading privacy settings...'**
  String get loadingPrivacySettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Loading student information...'**
  String get loadingStudentInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Loading your profile...'**
  String get loadingYourProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Magic link sent! Check your email and click the link to sign in.'**
  String get magicLinkSentMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Make Public'**
  String get makePublicMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Manage your account and preferences'**
  String get manageAccountAndPreferences;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Manage downloaded content'**
  String get manageDownloadedContentMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Manage reimbursements'**
  String get manageReimbursementsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Manage your account and preferences'**
  String get manageYourAccountAndPreferencesMessage;

  /// Auto-extracted string (used in 4 files)
  ///
  /// In en, this message translates to:
  /// **'Marketplace'**
  String get marketplaceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Member Benefits Active'**
  String get memberBenefitsActiveMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Member Discounts'**
  String get memberDiscountsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get memberMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Member Since'**
  String get memberSinceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'{chat} members'**
  String members(String chat);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Membership Expired'**
  String get membershipExpiredMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Membership purchase initiated! Complete payment to activate.'**
  String get membershipPurchaseInitiatedCompletePaymentToActivateMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Message copied to clipboard'**
  String get messageCopiedToClipboardMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Message {product}'**
  String messageSellerMessage(String product);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Message sent successfully!'**
  String get messageSentSuccessfullyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Metro'**
  String get metroMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'{difference}m'**
  String minutes(String difference);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'+ {sources} more documents'**
  String moreDocumentsMessage(String sources);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Mute notifications during specific hours'**
  String get muteNotificationsDuringSpecificHoursMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'\$name (\$count stops)'**
  String get nameCountStopsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameIsRequiredMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get nameMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Negotiable'**
  String get negotiableMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Network error: {e}'**
  String networkErrorMessage(String e);

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'New Expense'**
  String get newExpenseMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'New items and deals in the marketplace'**
  String get newItemsAndDealsInTheMarketplaceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'New messages in your chats'**
  String get newMessagesInYourChatsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No active membership found. Please purchase a BISO membership first.'**
  String get noActiveMembershipFoundPleasePurchaseABISOMembershipFirstMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No active units here yet'**
  String get noActiveUnitsHereYetMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No board members found'**
  String get noBoardMembersFoundMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No chats found'**
  String get noChatsFound;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get noConversationsYet;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No departures'**
  String get noDeparturesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No event selected'**
  String get noEventSelectedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No Events Found'**
  String get noEventsFoundMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No expenses found'**
  String get noExpensesFoundMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No expenses match your current filter'**
  String get noExpensesMatchYourCurrentFilterMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get noExpiryMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavoritesYetMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No files uploaded yet'**
  String get noFilesUploadedYetMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No items found'**
  String get noItemsFoundMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No members found for \$departmentName'**
  String get noMembersFoundForDepartmentNameMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No memberships available'**
  String get noMembershipsAvailableMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No recent expenses'**
  String get noRecentExpensesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No social links yet'**
  String get noSocialLinksYetMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'No stop places configured for this campus'**
  String get noStopPlacesConfiguredForThisCampusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'NOK {amount}'**
  String nokMessage(String amount);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'NOK (Norwegian Krone)'**
  String get nokNorwegianKroneMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noneMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Norwegian Account Number'**
  String get norwegianAccountNumberMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Norwegian Bank Account'**
  String get norwegianBankAccountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Norwegian bank account must be 11 digits'**
  String get norwegianBankAccountMustBe11DigitsMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'BI Student Organisation'**
  String get norwegianBusinessSchoolMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Not authenticated'**
  String get notAuthenticatedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFoundMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Not Now'**
  String get notNowMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet. Check back soon!'**
  String get nothingHereYetCheckBackSoonMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Notification Preferences'**
  String get notificationPreferencesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Notification Schedule'**
  String get notificationScheduleMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Notifications enabled successfully!'**
  String get notificationsEnabledSuccessfullyMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get now;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get nowMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Official merchandise and campus gear'**
  String get officialMerchandiseAndCampusGearMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Offline data management coming soon'**
  String get offlineDataManagementComingSoonMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Offline Data'**
  String get offlineDataMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'One ticket grants access to all events on this campus.'**
  String get oneTicketGrantsAccessToAllEventsOnThisCampusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Open mail app'**
  String get openMailApp;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Open Positions'**
  String get openPositionsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Open Ticket Portal'**
  String get openTicketPortalMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Open Validator Mode'**
  String get openValidatorModeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Oslo Campus'**
  String get osloCampusMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get otherMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Others can find and message you'**
  String get othersCanFindAndMessageYouMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Others cannot find you in search'**
  String get othersCannotFindYouInSearchMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'OTP sent to \$widget.email'**
  String get otpSentTo;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Overall description (AI-generated, editable)'**
  String get overallDescriptionAIGeneratedEditableMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Overall description'**
  String get overallDescriptionMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paidMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Pay {selectedOption} NOK'**
  String paySelectedOptionPriceNokNOKMessage(String selectedOption);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Pay with '**
  String get payWithMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Payment Information'**
  String get paymentInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Payment information saved successfully'**
  String get paymentInformationSavedSuccessfullyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethodMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Personal Info'**
  String get personalInfoMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInformationMessage;

  /// Auto-extracted string (used in 4 files)
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Phone Number (Optional)'**
  String get phoneNumberOptionalMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photosMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Play sound for new messages'**
  String get playSoundForNewMessagesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please add a bit more detail'**
  String get pleaseAddABitMoreDetailMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please add at least one photo'**
  String get pleaseAddAtLeastOnePhotoMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please check your email manually.'**
  String get pleaseCheckYourEmailManuallyMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Please enable notifications in system settings'**
  String get pleaseEnableNotificationsInSystemSettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid Norwegian phone number'**
  String get pleaseEnterAValidNorwegianPhoneNumberMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please register your student ID first.'**
  String get pleaseRegisterYourStudentIDFirstMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please review all information before submitting'**
  String get pleaseReviewAllInformationBeforeSubmittingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please sign in to access \$feature and other personalized features.'**
  String get pleaseSignInToAccessAndOtherPersonalizedFeaturesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please sign in to contact seller'**
  String get pleaseSignInToContactSellerMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Please sign in to save favorites'**
  String get pleaseSignInToSaveFavoritesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please sign in to sell items'**
  String get pleaseSignInToSellItemsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Please wait while we verify your magic link...'**
  String get pleaseWaitWhileWeVerifyYourMagicLinkMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'+47 xxx xx xxx'**
  String get plus47xxxxxxxMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get poorMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'POPULAR'**
  String get popularMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Preferred contact (optional)'**
  String get preferredContactOptionalMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Prefers: {contactMethodLabel}'**
  String prefersMessage(String contactMethodLabel);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Premium Features'**
  String get premiumFeaturesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Prepayment'**
  String get prepaymentMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Prepayment Request'**
  String get prepaymentRequestMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Price is negotiable'**
  String get priceIsNegotiableMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Price (NOK)'**
  String get priceNOKMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Priority Event Access'**
  String get priorityEventAccessMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Privacy Information'**
  String get privacyInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Private Profile'**
  String get privateProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Product Details'**
  String get productDetailsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Product information not available'**
  String get productInformationNotAvailableMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'🛍️ \$productName: {message}'**
  String productMessage(String message);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Product not found'**
  String get productNotFoundMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get productsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Profile Information'**
  String get profileInformationMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Profile set to private - others cannot find you in search'**
  String get profileSetToPrivate;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Profile set to public - others can find and message you'**
  String get profileSetToPublic;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdatedSuccessfullyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Public profile created - others can find you in search'**
  String get publicProfileCreatedOthersCanFindYouInSearchMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Public Profile'**
  String get publicProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publishMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Purchase failed: {e}'**
  String purchaseFailedMessage(String e);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Purchase Membership'**
  String get purchaseMembershipMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotificationsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'QR data copied to clipboard: {qrData}...'**
  String qrDataCopiedToClipboardMessage(String qrData);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'QR Error'**
  String get qrErrorMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'• \"{response}\"'**
  String queryMessage(String response);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Quick Links'**
  String get quickLinksMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Quiet hours feature coming soon'**
  String get quietHoursFeatureComingSoonMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Quiet Hours'**
  String get quietHoursMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Re-run AI'**
  String get reRunAIMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Read Receipts'**
  String get readReceiptsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Ready to help'**
  String get readyToHelpMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Realtime bus & metro'**
  String get realtimeBusMetroMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Receipts are required for reimbursement'**
  String get receiptsAreRequiredForReimbursementMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Receipts & Documents'**
  String get receiptsDocumentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get receiptsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Receive notifications for new messages'**
  String get receiveNotificationsForNewMessagesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Recent Expenses'**
  String get recentExpensesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Refresh Status'**
  String get refreshStatusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Regional Settings'**
  String get regionalSettingsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Registration Required'**
  String get registrationRequiredMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejectedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Related Event'**
  String get relatedEventMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Relates to an event'**
  String get relatesToAnEventMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'{remainingSeconds}s'**
  String remainingSecondsMessage(String remainingSeconds);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Remove Student ID'**
  String get removeStudentIDMessage;

  /// Auto-extracted string (used in 4 files)
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get removedFromFavoritesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Renew Membership'**
  String get renewMembershipMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Request Prepayment'**
  String get requestPrepaymentMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Required Skills'**
  String get requiredSkillsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Requires SWIFT code for international transfers'**
  String get requiresSWIFTCodeForInternationalTransfersMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Resend code in {resendCountdown}s'**
  String resendCodeInMessage(String resendCountdown);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Review & Submit'**
  String get reviewAndSubmitMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Review your expense'**
  String get reviewYourExpenseMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Save as Draft'**
  String get saveAsDraftMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Save Payment Information'**
  String get savePaymentInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Scan student QR codes to verify membership'**
  String get scanStudentQRCodesToVerifyMembershipMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get scheduleMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Scheduled {formatTime}'**
  String scheduledTimeMessage(String formatTime);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search Chats'**
  String get searchChats;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search disabled in favorites'**
  String get searchDisabledInFavoritesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search events'**
  String get searchEventsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search marketplace'**
  String get searchMarketplaceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search Messages'**
  String get searchMessages;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search messages and chat names...'**
  String get searchMessagesAndChatNames;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search must be at least 2 characters'**
  String get searchMustBeAtLeast2CharactersMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Search webshop'**
  String get searchWebshopMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Secure payment powered by Vipps MobilePay'**
  String get securePaymentPoweredByVippsMobilePayMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Secure Storage'**
  String get secureStorageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Secure Verification'**
  String get secureVerificationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Select campus and department to save draft'**
  String get selectCampusAndDepartmentToSaveDraftMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Select Campus'**
  String get selectCampusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Select Image Source'**
  String get selectImageSourceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Select Interests'**
  String get selectInterestsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Select your home campus'**
  String get selectYourHomeCampusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Selected Plan'**
  String get selectedPlanMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Sell Item'**
  String get sellItemMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Seller Information'**
  String get sellerInformationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Send Magic Link'**
  String get sendMagicLinkMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Send a message to {product}:'**
  String sendMessageToSellerMessage(String product);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Session cleared - OTP flow should work now'**
  String get sessionClearedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'SharePoint Search'**
  String get sharePointSearchMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'🛍️ Shared \$productName'**
  String get sharedProduct;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Shop on BISO.no'**
  String get shopOnBISOnoMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Show all products'**
  String get showAllProductsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Show favorites only'**
  String get showFavoritesOnlyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Show Less'**
  String get showLessMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Show {widget} More'**
  String showMoreMessage(String widget);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Show this to validators'**
  String get showThisToValidatorsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Show your last seen status'**
  String get showYourLastSeenStatusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Sign In Failed'**
  String get signInFailedMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signInMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Sign In Required'**
  String get signInRequiredMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Sign in to view your profile'**
  String get signInToViewYourProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Sign In with BI Account'**
  String get signInWithBIAccountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOutMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Signing You In...'**
  String get signingYouInMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Site Listing'**
  String get siteListingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Sites'**
  String get sitesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrongMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while signing you in. Please try again.'**
  String get somethingWentWrongWhileSigningYouInMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get soundMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Special Event'**
  String get specialEventMessage;

  /// Auto-extracted string (used in 3 files)
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get sportsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Standard Norwegian bank account with MOD11 validation'**
  String get standardNorwegianBankAccountWithMOD11ValidationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Start Chat'**
  String get startChat;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Start a conversation with your team'**
  String get startConversationWithYourTeam;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Status History'**
  String get statusHistoryMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Stop Place'**
  String get stopPlaceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Student ID not found. Please verify your student status first.'**
  String get studentIDNotFoundPleaseVerifyYourStudentStatusFirstMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Student ID'**
  String get studentIdMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Student organizations'**
  String get studentOrganizationsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Student Support'**
  String get studentSupportMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Student Verification'**
  String get studentVerificationMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get studentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Submit and track your expense claims'**
  String get submitAndTrackYourExpenseClaimsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Submit for Approval'**
  String get submitForApprovalMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submitMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get submittedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get successMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'SWIFT/BIC Code'**
  String get swiftBICCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'SWIFT code can only contain letters and numbers'**
  String get swiftCodeCanOnlyContainLettersAndNumbersMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'SWIFT code is required for international accounts'**
  String get swiftCodeIsRequiredForInternationalAccountsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'SWIFT Code'**
  String get swiftCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'SWIFT code must be 8 or 11 characters'**
  String get swiftCodeMustBe8Or11CharactersMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhotoMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Tap to Generate'**
  String get tapToGenerateMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Team chat • {chat} members'**
  String teamChatMembers(String chat);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Teams'**
  String get teams;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfServiceMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'There are currently no active membership plans for your campus. This may be because membership sales are temporarily disabled or undergoing maintenance. Please check back later.'**
  String
  get thereAreCurrentlyNoActiveMembershipPlansForYourCampusThisMayBeBecauseMembershipSalesAreTemporarilyDisabledOrUndergoingMaintenancePleaseCheckBackLaterMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'There are no events matching your criteria.'**
  String get thereAreNoEventsMatchingYourCriteriaMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get thinkingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'This magic link has expired or is invalid. Please request a new one.'**
  String get thisMagicLinkHasExpiredOrIsInvalidMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get thisMessageWasDeleted;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'This will clear all cached images and data. The app may take longer to load content after clearing cache.'**
  String
  get thisWillClearAllCachedImagesAndDataTheAppMayTakeLongerToLoadContentAfterClearingCacheMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get ticketsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'TikTok'**
  String get tikTokMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get titleIsRequiredMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Token expires in'**
  String get tokenExpiresInMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get totalAmountMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgainMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Try changing your filter or check back later'**
  String get tryChangingYourFilterOrCheckBackLaterMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Try a different search term'**
  String get tryDifferentSearchTerm;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Type at least 2 characters'**
  String get typeAtLeast2CharactersMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Type your message...'**
  String get typeYourMessageMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Typing Indicators'**
  String get typingIndicatorsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Unable to verify membership status. Please try again.'**
  String get unableToVerifyMembershipStatusPleaseTryAgainMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Units & Departments'**
  String get unitsDepartmentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get unitsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Unknown User'**
  String get unknownUserMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Unlock After Verification'**
  String get unlockAfterVerificationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Unlock These Benefits'**
  String get unlockTheseBenefitsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcomingMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Upload Document (PDF)'**
  String get uploadDocumentPDFMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Upload photos or scans of your receipts'**
  String get uploadPhotosOrScansOfYourReceiptsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Upload receipts and documents'**
  String get uploadReceiptsAndDocumentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'URGENT'**
  String get urgentMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Use AI to extract details'**
  String get useAIToExtractDetailsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Use dark theme throughout the app'**
  String get useDarkThemeThroughoutTheAppMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Use magic link instead'**
  String get useMagicLinkInsteadMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Use the campus switcher on the home screen to change campus'**
  String get useTheCampusSwitcherOnTheHomeScreenToChangeCampusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Use verification code instead'**
  String get useVerificationCodeInsteadMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Use your @bi.no email for secure, instant verification. This ensures your student ID belongs to you.'**
  String
  get useYourbiNoEmailForSecureInstantVerificationThisEnsuresYourStudentIDBelongsToYouMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Using {runningTools}...'**
  String usingToolMessage(String runningTools);

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Valid Until'**
  String get validUntilMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Validator Mode'**
  String get validatorModeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Verification code copied'**
  String get verificationCodeCopiedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Verification Code'**
  String get verificationCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Verification code sent successfully'**
  String get verificationCodeSentSuccessfullyMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Verification QR Code'**
  String get verificationQRCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verifiedMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Verify OTP'**
  String get verifyOtp;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Verify your BI \$campusName student status and unlock exclusive features, membership benefits, and campus-wide access.'**
  String
  get verifyYourBIcampusNameStudentStatusAndUnlockExclusiveFeaturesMembershipBenefitsAndCampusWideAccessMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Verify Your Student Status'**
  String get verifyYourStudentStatusMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Vibrate for new messages'**
  String get vibrateForNewMessagesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Vibrate for notifications'**
  String get vibrateForNotificationsMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get vibrationMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Vibration settings coming soon'**
  String get vibrationSettingsComingSoonMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetailsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'View History'**
  String get viewHistoryMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'View important dates'**
  String get viewImportantDatesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'View on Biso.no'**
  String get viewOnBisoNoMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Vipps'**
  String get vippsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Vipps/MobilePay'**
  String get vippsMobilePayMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Visit our website'**
  String get visitOurWebsiteMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Volunteer and job opportunities'**
  String get volunteerAndJobOpportunitiesMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Volunteer'**
  String get volunteerMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Volunteer opportunities'**
  String get volunteerOpportunitiesMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Volunteer opportunities with BISO'**
  String get volunteerOpportunitiesWithBISOMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get weatherMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Webshop'**
  String get webshopMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get websiteMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Welcome Back!'**
  String get welcomeBackMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Welcome to BISO'**
  String get welcomeToBISOMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Welcome to BISO'**
  String get welcomeToBiso;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Welcome to'**
  String get welcomeToMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'What was this expense for? (you can edit)'**
  String get whatWasThisExpenseForYouCanEditMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'What you get'**
  String get whatYouGetMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'X'**
  String get xMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'You can change this setting anytime in your profile.'**
  String get youCanChangeThisSettingAnytimeInYourProfileMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'You cannot message yourself'**
  String get youCannotMessageYourselfMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'You may already be signed in. Try clearing your session and signing in again.'**
  String get youMayAlreadyBeSignedInMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Your item is now live!'**
  String get yourItemIsNowLiveMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Your Member Benefits'**
  String get yourMemberBenefitsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Your payment information is encrypted and stored securely. Only BISO administrators can access this information for reimbursement processing.'**
  String
  get yourPaymentInformationIsEncryptedAndStoredSecurelyOnlyBISOAdministratorsCanAccessThisInformationForReimbursementProcessingMessage;

  /// Auto-extracted string (used in 2 files)
  ///
  /// In en, this message translates to:
  /// **'Zip Code'**
  String get zipCodeMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Connecting students across Norway\'s leading business school'**
  String get connectingStudentsMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'Volunteer opportunities with BISO'**
  String get volunteerOpportunitiesWithBISO;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAllMessage;

  /// Auto-extracted string
  ///
  /// In en, this message translates to:
  /// **'BISO.no'**
  String get bisoWebsiteMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'no'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'no':
      return AppLocalizationsNo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
