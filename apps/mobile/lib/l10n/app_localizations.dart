import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_fr.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('ar'),
    Locale('fr'),
  ];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'بن مهدية'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In ar, this message translates to:
  /// **'مرافقة التعافي'**
  String get appTagline;

  /// No description provided for @welcomeTitle.
  ///
  /// In ar, this message translates to:
  /// **'كل يوم جديد خطوة نحو التعافي'**
  String get welcomeTitle;

  /// No description provided for @welcomeBody.
  ///
  /// In ar, this message translates to:
  /// **'رفيقك بين الجلسات: تابع تقدّمك ومواعيدك وأدويتك، واستعد جودة حياتك بمرافقة طبيبك.'**
  String get welcomeBody;

  /// No description provided for @createAccount.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء حساب'**
  String get createAccount;

  /// No description provided for @haveAccount.
  ///
  /// In ar, this message translates to:
  /// **'لدي حساب — تسجيل الدخول'**
  String get haveAccount;

  /// No description provided for @secureFooter.
  ///
  /// In ar, this message translates to:
  /// **'بياناتك مشفّرة ومستضافة في الجزائر'**
  String get secureFooter;

  /// No description provided for @langArabic.
  ///
  /// In ar, this message translates to:
  /// **'العربية'**
  String get langArabic;

  /// No description provided for @langFrench.
  ///
  /// In ar, this message translates to:
  /// **'Français'**
  String get langFrench;

  /// No description provided for @splashLine1.
  ///
  /// In ar, this message translates to:
  /// **'خطوة بخطوة نحو التعافي'**
  String get splashLine1;

  /// No description provided for @splashLine2.
  ///
  /// In ar, this message translates to:
  /// **'من أجل جودة الحياة'**
  String get splashLine2;

  /// No description provided for @introSkip.
  ///
  /// In ar, this message translates to:
  /// **'تخطي'**
  String get introSkip;

  /// No description provided for @introNext.
  ///
  /// In ar, this message translates to:
  /// **'التالي'**
  String get introNext;

  /// No description provided for @introStart.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ الآن'**
  String get introStart;

  /// No description provided for @introPageOf.
  ///
  /// In ar, this message translates to:
  /// **'الصفحة {page} من {count}'**
  String introPageOf(int page, int count);

  /// No description provided for @intro1Title.
  ///
  /// In ar, this message translates to:
  /// **'كل يوم يُحسب'**
  String get intro1Title;

  /// No description provided for @intro1Body.
  ///
  /// In ar, this message translates to:
  /// **'تابع أيامك دون تعاطٍ، سجّل حالتك كل يوم في دقيقة، واحتفل بكل خطوة تقطعها.'**
  String get intro1Body;

  /// No description provided for @intro2Title.
  ///
  /// In ar, this message translates to:
  /// **'لست وحدك، في أي ساعة'**
  String get intro2Title;

  /// No description provided for @intro2Body.
  ///
  /// In ar, this message translates to:
  /// **'مرافق رقمي يردّ عليك ليلاً ونهاراً عند الرغبة أو القلق، وينبّه طبيبك إذا احتجت مساعدة عاجلة.'**
  String get intro2Body;

  /// No description provided for @intro3Title.
  ///
  /// In ar, this message translates to:
  /// **'طبيبك معك بين المواعيد'**
  String get intro3Title;

  /// No description provided for @intro3Body.
  ///
  /// In ar, this message translates to:
  /// **'احجز موعدك بسهولة، تلقَّ تذكير أدويتك في وقتها، وشارك تقدّمك مع طبيبك.'**
  String get intro3Body;

  /// No description provided for @ringDaysLabel.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{يوم دون تعاطٍ} =1{يوم دون تعاطٍ} =2{يومان دون تعاطٍ} few{أيام دون تعاطٍ} many{يوماً دون تعاطٍ} other{يوم دون تعاطٍ}}'**
  String ringDaysLabel(int count);

  /// No description provided for @ringOfGoal.
  ///
  /// In ar, this message translates to:
  /// **'{days} من أصل {goal} يوماً'**
  String ringOfGoal(int days, int goal);

  /// No description provided for @ringNextGoal.
  ///
  /// In ar, this message translates to:
  /// **'الهدف التالي: {goal} يوماً'**
  String ringNextGoal(int goal);

  /// No description provided for @introWeek.
  ///
  /// In ar, this message translates to:
  /// **'هذا الأسبوع: {done} أيام من {total}'**
  String introWeek(int done, int total);

  /// No description provided for @companionName.
  ///
  /// In ar, this message translates to:
  /// **'المرافق'**
  String get companionName;

  /// No description provided for @companionOnline.
  ///
  /// In ar, this message translates to:
  /// **'متاح الآن · 24/24'**
  String get companionOnline;

  /// No description provided for @chatSample.
  ///
  /// In ar, this message translates to:
  /// **'الرغبة قوية بزاف الليلة، ما قدرتش نرقد…'**
  String get chatSample;

  /// No description provided for @chatReplySample.
  ///
  /// In ar, this message translates to:
  /// **'أنا هنا معك. خذ نفساً عميقاً لأربع ثوانٍ، ثم أخرجه ببطء. ماذا حدث اليوم قبل أن تبدأ الرغبة؟'**
  String get chatReplySample;

  /// No description provided for @chipBreathing.
  ///
  /// In ar, this message translates to:
  /// **'تمرين تنفّس'**
  String get chipBreathing;

  /// No description provided for @chipEmergency.
  ///
  /// In ar, this message translates to:
  /// **'أرقام الطوارئ'**
  String get chipEmergency;

  /// No description provided for @apptNext.
  ///
  /// In ar, this message translates to:
  /// **'موعدك القادم'**
  String get apptNext;

  /// No description provided for @apptDoctorSample.
  ///
  /// In ar, this message translates to:
  /// **'د. بن مهدية حسين'**
  String get apptDoctorSample;

  /// No description provided for @apptWhenSample.
  ///
  /// In ar, this message translates to:
  /// **'الاثنين 19 أكتوبر · 10:30'**
  String get apptWhenSample;

  /// No description provided for @apptConfirmed.
  ///
  /// In ar, this message translates to:
  /// **'مؤكّد'**
  String get apptConfirmed;

  /// No description provided for @medMorning.
  ///
  /// In ar, this message translates to:
  /// **'دواء الصباح'**
  String get medMorning;

  /// No description provided for @medEvening.
  ///
  /// In ar, this message translates to:
  /// **'دواء المساء'**
  String get medEvening;

  /// No description provided for @medTaken.
  ///
  /// In ar, this message translates to:
  /// **'تم'**
  String get medTaken;

  /// No description provided for @medLater.
  ///
  /// In ar, this message translates to:
  /// **'لاحقاً'**
  String get medLater;

  /// No description provided for @doctorWeeklySummary.
  ///
  /// In ar, this message translates to:
  /// **'يصل طبيبك ملخّص أسبوعي عن تقدّمك'**
  String get doctorWeeklySummary;

  /// No description provided for @verifyTitle.
  ///
  /// In ar, this message translates to:
  /// **'التحقق من الهوية'**
  String get verifyTitle;

  /// No description provided for @verifyStep.
  ///
  /// In ar, this message translates to:
  /// **'{step} / {total}'**
  String verifyStep(int step, int total);

  /// No description provided for @verifyStepSemantics.
  ///
  /// In ar, this message translates to:
  /// **'الخطوة {step} من {total}'**
  String verifyStepSemantics(int step, int total);

  /// No description provided for @verifyContinue.
  ///
  /// In ar, this message translates to:
  /// **'متابعة'**
  String get verifyContinue;

  /// No description provided for @selfieTitle.
  ///
  /// In ar, this message translates to:
  /// **'ضع وجهك داخل الإطار'**
  String get selfieTitle;

  /// No description provided for @selfieHint.
  ///
  /// In ar, this message translates to:
  /// **'إضاءة جيدة، بدون نظارات شمسية أو قبعة'**
  String get selfieHint;

  /// No description provided for @livenessLook.
  ///
  /// In ar, this message translates to:
  /// **'انظر إلى الكاميرا'**
  String get livenessLook;

  /// No description provided for @livenessTurn.
  ///
  /// In ar, this message translates to:
  /// **'أدر رأسك ببطء'**
  String get livenessTurn;

  /// No description provided for @livenessBlink.
  ///
  /// In ar, this message translates to:
  /// **'ارمش مرتين'**
  String get livenessBlink;

  /// No description provided for @selfieCaptured.
  ///
  /// In ar, this message translates to:
  /// **'تم التقاط الصورة'**
  String get selfieCaptured;

  /// No description provided for @selfieAuto.
  ///
  /// In ar, this message translates to:
  /// **'تُلتقط الصورة تلقائياً عند اكتمال الخطوات'**
  String get selfieAuto;

  /// No description provided for @selfiePrivacy.
  ///
  /// In ar, this message translates to:
  /// **'تُقارن صورتك بصورة البطاقة فقط، ولا تُنشر'**
  String get selfiePrivacy;

  /// No description provided for @idTitle.
  ///
  /// In ar, this message translates to:
  /// **'بطاقة التعريف الوطنية'**
  String get idTitle;

  /// No description provided for @idFront.
  ///
  /// In ar, this message translates to:
  /// **'الوجه الأمامي'**
  String get idFront;

  /// No description provided for @idBack.
  ///
  /// In ar, this message translates to:
  /// **'الوجه الخلفي'**
  String get idBack;

  /// No description provided for @idPlaceFront.
  ///
  /// In ar, this message translates to:
  /// **'ضع الوجه الأمامي داخل الإطار'**
  String get idPlaceFront;

  /// No description provided for @idPlaceBack.
  ///
  /// In ar, this message translates to:
  /// **'اقلب البطاقة وضع الوجه الخلفي داخل الإطار'**
  String get idPlaceBack;

  /// No description provided for @idSearching.
  ///
  /// In ar, this message translates to:
  /// **'نبحث عن البطاقة…'**
  String get idSearching;

  /// No description provided for @idDetected.
  ///
  /// In ar, this message translates to:
  /// **'تم رصد البطاقة، ثبّت الهاتف'**
  String get idDetected;

  /// No description provided for @idTipSurface.
  ///
  /// In ar, this message translates to:
  /// **'ضع البطاقة على سطح داكن ومستوٍ'**
  String get idTipSurface;

  /// No description provided for @idTipGlare.
  ///
  /// In ar, this message translates to:
  /// **'تجنّب الانعكاس والضوء المباشر'**
  String get idTipGlare;

  /// No description provided for @idTipCorners.
  ///
  /// In ar, this message translates to:
  /// **'يجب أن تظهر الزوايا الأربع داخل الإطار'**
  String get idTipCorners;

  /// No description provided for @idCaptureFront.
  ///
  /// In ar, this message translates to:
  /// **'التقاط الوجه الأمامي'**
  String get idCaptureFront;

  /// No description provided for @idCaptureBack.
  ///
  /// In ar, this message translates to:
  /// **'التقاط الوجه الخلفي'**
  String get idCaptureBack;

  /// No description provided for @idPrivacy.
  ///
  /// In ar, this message translates to:
  /// **'تُستخدم صورة البطاقة للتحقق فقط'**
  String get idPrivacy;

  /// No description provided for @reviewTitle.
  ///
  /// In ar, this message translates to:
  /// **'راجع وأرسل'**
  String get reviewTitle;

  /// No description provided for @reviewBody.
  ///
  /// In ar, this message translates to:
  /// **'تأكّد أن كل شيء جاهز قبل إرسال ملفك إلى العيادة.'**
  String get reviewBody;

  /// No description provided for @reviewSelfie.
  ///
  /// In ar, this message translates to:
  /// **'صورة شخصية حيّة'**
  String get reviewSelfie;

  /// No description provided for @reviewIdSides.
  ///
  /// In ar, this message translates to:
  /// **'الوجهان الأمامي والخلفي للبطاقة'**
  String get reviewIdSides;

  /// No description provided for @reviewSharp.
  ///
  /// In ar, this message translates to:
  /// **'صورة البطاقة واضحة'**
  String get reviewSharp;

  /// No description provided for @reviewNoGlare.
  ///
  /// In ar, this message translates to:
  /// **'دون انعكاس للضوء'**
  String get reviewNoGlare;

  /// No description provided for @reviewCorners.
  ///
  /// In ar, this message translates to:
  /// **'الزوايا الأربع ظاهرة'**
  String get reviewCorners;

  /// No description provided for @reviewPrivacy.
  ///
  /// In ar, this message translates to:
  /// **'لا يرى صورك إلا فريق المراجعة في العيادة وطبيبك.'**
  String get reviewPrivacy;

  /// No description provided for @reviewSubmit.
  ///
  /// In ar, this message translates to:
  /// **'إرسال الملف'**
  String get reviewSubmit;

  /// No description provided for @reviewRetake.
  ///
  /// In ar, this message translates to:
  /// **'إعادة تصوير البطاقة'**
  String get reviewRetake;

  /// No description provided for @pendingTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال ملفك'**
  String get pendingTitle;

  /// No description provided for @pendingBody.
  ///
  /// In ar, this message translates to:
  /// **'ستراجع العيادة ملفك، وسنُعلمك فور الموافقة لتحجز موعدك الأول.'**
  String get pendingBody;

  /// No description provided for @pendingStatus.
  ///
  /// In ar, this message translates to:
  /// **'قيد المراجعة'**
  String get pendingStatus;

  /// No description provided for @bookTitle.
  ///
  /// In ar, this message translates to:
  /// **'حجز موعد'**
  String get bookTitle;

  /// No description provided for @bookDoctorTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر طبيبك'**
  String get bookDoctorTitle;

  /// No description provided for @bookDoctorBody.
  ///
  /// In ar, this message translates to:
  /// **'أول طبيب تحجز معه يصبح طبيبك المتابع في العيادة.'**
  String get bookDoctorBody;

  /// No description provided for @bookClinic.
  ///
  /// In ar, this message translates to:
  /// **'عيادة بن مهدية'**
  String get bookClinic;

  /// No description provided for @bookMinutes.
  ///
  /// In ar, this message translates to:
  /// **'{minutes} دقيقة'**
  String bookMinutes(int minutes);

  /// No description provided for @bookPrice.
  ///
  /// In ar, this message translates to:
  /// **'{amount} دج'**
  String bookPrice(int amount);

  /// No description provided for @bookNextFree.
  ///
  /// In ar, this message translates to:
  /// **'أقرب موعد: {when}'**
  String bookNextFree(String when);

  /// No description provided for @bookNoFree.
  ///
  /// In ar, this message translates to:
  /// **'لا مواعيد متاحة خلال الشهرين القادمين'**
  String get bookNoFree;

  /// No description provided for @bookNotice.
  ///
  /// In ar, this message translates to:
  /// **'الحجز قبل 24 ساعة على الأقل من الموعد'**
  String get bookNotice;

  /// No description provided for @bookChooseTime.
  ///
  /// In ar, this message translates to:
  /// **'اختيار اليوم والوقت'**
  String get bookChooseTime;

  /// No description provided for @bookSlotTitle.
  ///
  /// In ar, this message translates to:
  /// **'اليوم والوقت'**
  String get bookSlotTitle;

  /// No description provided for @bookChange.
  ///
  /// In ar, this message translates to:
  /// **'تغيير'**
  String get bookChange;

  /// No description provided for @bookMorning.
  ///
  /// In ar, this message translates to:
  /// **'صباحاً'**
  String get bookMorning;

  /// No description provided for @bookAfternoon.
  ///
  /// In ar, this message translates to:
  /// **'مساءً'**
  String get bookAfternoon;

  /// No description provided for @bookLegendFree.
  ///
  /// In ar, this message translates to:
  /// **'متاح'**
  String get bookLegendFree;

  /// No description provided for @bookLegendTaken.
  ///
  /// In ar, this message translates to:
  /// **'غير متاح'**
  String get bookLegendTaken;

  /// No description provided for @bookLegendYours.
  ///
  /// In ar, this message translates to:
  /// **'اختيارك'**
  String get bookLegendYours;

  /// No description provided for @bookNoSlots.
  ///
  /// In ar, this message translates to:
  /// **'لا مواعيد في هذا اليوم'**
  String get bookNoSlots;

  /// No description provided for @bookTooSoon.
  ///
  /// In ar, this message translates to:
  /// **'يكون الحجز قبل 24 ساعة على الأقل من الموعد.'**
  String get bookTooSoon;

  /// No description provided for @bookClosed.
  ///
  /// In ar, this message translates to:
  /// **'لا يستقبل الطبيب المرضى في هذا اليوم.'**
  String get bookClosed;

  /// No description provided for @bookPickTime.
  ///
  /// In ar, this message translates to:
  /// **'اختر وقتاً للمتابعة'**
  String get bookPickTime;

  /// No description provided for @bookContinue.
  ///
  /// In ar, this message translates to:
  /// **'متابعة'**
  String get bookContinue;

  /// No description provided for @bookSlotGone.
  ///
  /// In ar, this message translates to:
  /// **'حجز شخص آخر هذا الوقت للتو. اختر وقتاً آخر.'**
  String get bookSlotGone;

  /// No description provided for @bookConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'التأكيد والدفع'**
  String get bookConfirmTitle;

  /// No description provided for @bookHeldFor.
  ///
  /// In ar, this message translates to:
  /// **'محجوز لك لمدة {time}'**
  String bookHeldFor(String time);

  /// No description provided for @bookHeldBody.
  ///
  /// In ar, this message translates to:
  /// **'إذا لم يكتمل الدفع، يُتاح الموعد لغيرك.'**
  String get bookHeldBody;

  /// No description provided for @bookDate.
  ///
  /// In ar, this message translates to:
  /// **'التاريخ'**
  String get bookDate;

  /// No description provided for @bookTime.
  ///
  /// In ar, this message translates to:
  /// **'الوقت'**
  String get bookTime;

  /// No description provided for @bookAmount.
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get bookAmount;

  /// No description provided for @bookPayMethod.
  ///
  /// In ar, this message translates to:
  /// **'طريقة الدفع'**
  String get bookPayMethod;

  /// No description provided for @bookEdahabia.
  ///
  /// In ar, this message translates to:
  /// **'البطاقة الذهبية'**
  String get bookEdahabia;

  /// No description provided for @bookCib.
  ///
  /// In ar, this message translates to:
  /// **'بطاقة CIB'**
  String get bookCib;

  /// No description provided for @bookViaChargily.
  ///
  /// In ar, this message translates to:
  /// **'عبر Chargily Pay'**
  String get bookViaChargily;

  /// No description provided for @bookClinicPay.
  ///
  /// In ar, this message translates to:
  /// **'الدفع في العيادة'**
  String get bookClinicPay;

  /// No description provided for @bookClinicPaySub.
  ///
  /// In ar, this message translates to:
  /// **'خلال فترة التجربة، يؤكّده الطبيب'**
  String get bookClinicPaySub;

  /// No description provided for @bookCancelRule.
  ///
  /// In ar, this message translates to:
  /// **'الإلغاء ممكن حتى 24 ساعة قبل الموعد.'**
  String get bookCancelRule;

  /// No description provided for @bookPay.
  ///
  /// In ar, this message translates to:
  /// **'ادفع {amount} دج'**
  String bookPay(int amount);

  /// No description provided for @bookPayNote.
  ///
  /// In ar, this message translates to:
  /// **'دفع آمن عبر Chargily Pay. لا نحتفظ ببيانات بطاقتك.'**
  String get bookPayNote;

  /// No description provided for @bookConfirmClinic.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الحجز'**
  String get bookConfirmClinic;

  /// No description provided for @bookClinicNote.
  ///
  /// In ar, this message translates to:
  /// **'تدفع في العيادة يوم الموعد.'**
  String get bookClinicNote;

  /// No description provided for @bookExpiredTitle.
  ///
  /// In ar, this message translates to:
  /// **'انتهت مدة الحجز'**
  String get bookExpiredTitle;

  /// No description provided for @bookExpiredBody.
  ///
  /// In ar, this message translates to:
  /// **'أُتيح هذا الموعد لغيرك. يمكنك اختيار وقت آخر.'**
  String get bookExpiredBody;

  /// No description provided for @bookPickAnother.
  ///
  /// In ar, this message translates to:
  /// **'اختر وقتاً آخر'**
  String get bookPickAnother;

  /// No description provided for @bookDoneTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم تأكيد موعدك'**
  String get bookDoneTitle;

  /// No description provided for @bookDoneBodyPaid.
  ///
  /// In ar, this message translates to:
  /// **'وصلنا دفعك. سنذكّرك قبل الموعد.'**
  String get bookDoneBodyPaid;

  /// No description provided for @bookDoneTitleClinic.
  ///
  /// In ar, this message translates to:
  /// **'تم حجز موعدك'**
  String get bookDoneTitleClinic;

  /// No description provided for @bookDoneBodyClinic.
  ///
  /// In ar, this message translates to:
  /// **'ادفع في العيادة يوم الموعد. سنذكّرك قبله.'**
  String get bookDoneBodyClinic;

  /// No description provided for @bookPaid.
  ///
  /// In ar, this message translates to:
  /// **'المبلغ المدفوع: {amount} دج'**
  String bookPaid(int amount);

  /// No description provided for @bookToPay.
  ///
  /// In ar, this message translates to:
  /// **'يُدفع في العيادة: {amount} دج'**
  String bookToPay(int amount);

  /// No description provided for @bookRemind.
  ///
  /// In ar, this message translates to:
  /// **'سنذكّرك بإشعار'**
  String get bookRemind;

  /// No description provided for @bookRemind24.
  ///
  /// In ar, this message translates to:
  /// **'قبل 24 ساعة'**
  String get bookRemind24;

  /// No description provided for @bookRemind1.
  ///
  /// In ar, this message translates to:
  /// **'قبل ساعة'**
  String get bookRemind1;

  /// No description provided for @bookChangeHint.
  ///
  /// In ar, this message translates to:
  /// **'يمكنك إلغاء الموعد من «مواعيدي» حتى 24 ساعة قبله.'**
  String get bookChangeHint;

  /// No description provided for @bookMyAppointments.
  ///
  /// In ar, this message translates to:
  /// **'مواعيدي'**
  String get bookMyAppointments;

  /// No description provided for @bookHome.
  ///
  /// In ar, this message translates to:
  /// **'العودة إلى الرئيسية'**
  String get bookHome;

  /// No description provided for @bookLoadError.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر التحميل. تحقّق من الاتصال وحاول مجدداً.'**
  String get bookLoadError;

  /// No description provided for @bookRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get bookRetry;

  /// No description provided for @bookWeekday.
  ///
  /// In ar, this message translates to:
  /// **'{day, select, mon{الاثنين} tue{الثلاثاء} wed{الأربعاء} thu{الخميس} fri{الجمعة} sat{السبت} sun{الأحد} other{}}'**
  String bookWeekday(String day);

  /// No description provided for @bookWeekdayShort.
  ///
  /// In ar, this message translates to:
  /// **'{day, select, mon{اثنين} tue{ثلاثاء} wed{أربعاء} thu{خميس} fri{جمعة} sat{سبت} sun{أحد} other{}}'**
  String bookWeekdayShort(String day);

  /// No description provided for @bookMonth.
  ///
  /// In ar, this message translates to:
  /// **'{month, select, m1{جانفي} m2{فيفري} m3{مارس} m4{أفريل} m5{ماي} m6{جوان} m7{جويلية} m8{أوت} m9{سبتمبر} m10{أكتوبر} m11{نوفمبر} m12{ديسمبر} other{}}'**
  String bookMonth(String month);

  /// No description provided for @bookDateLong.
  ///
  /// In ar, this message translates to:
  /// **'{weekday} {day} {month}'**
  String bookDateLong(String weekday, int day, String month);

  /// No description provided for @apptAwaitingPayment.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار الدفع'**
  String get apptAwaitingPayment;

  /// No description provided for @apptCompleted.
  ///
  /// In ar, this message translates to:
  /// **'تمّ'**
  String get apptCompleted;

  /// No description provided for @apptCancelledStatus.
  ///
  /// In ar, this message translates to:
  /// **'ملغى'**
  String get apptCancelledStatus;

  /// No description provided for @apptNoShow.
  ///
  /// In ar, this message translates to:
  /// **'فائت'**
  String get apptNoShow;

  /// No description provided for @apptUpcoming.
  ///
  /// In ar, this message translates to:
  /// **'القادمة · {count}'**
  String apptUpcoming(int count);

  /// No description provided for @apptPast.
  ///
  /// In ar, this message translates to:
  /// **'السابقة'**
  String get apptPast;

  /// No description provided for @apptNew.
  ///
  /// In ar, this message translates to:
  /// **'حجز موعد جديد'**
  String get apptNew;

  /// No description provided for @apptCancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الموعد'**
  String get apptCancel;

  /// No description provided for @apptCancelAsk.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء هذا الموعد؟'**
  String get apptCancelAsk;

  /// No description provided for @apptCancelBody.
  ///
  /// In ar, this message translates to:
  /// **'سيُتاح هذا الوقت لمريض آخر.'**
  String get apptCancelBody;

  /// No description provided for @apptKeep.
  ///
  /// In ar, this message translates to:
  /// **'الإبقاء عليه'**
  String get apptKeep;

  /// No description provided for @apptCancelled.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء الموعد'**
  String get apptCancelled;

  /// No description provided for @apptLocked.
  ///
  /// In ar, this message translates to:
  /// **'بقي أقل من 24 ساعة، لذا لا يمكن الإلغاء من التطبيق. اتصل بالعيادة إذا تعذّر حضورك.'**
  String get apptLocked;

  /// No description provided for @apptNoUpcoming.
  ///
  /// In ar, this message translates to:
  /// **'لا مواعيد قادمة'**
  String get apptNoUpcoming;

  /// No description provided for @apptNoPast.
  ///
  /// In ar, this message translates to:
  /// **'لا مواعيد سابقة'**
  String get apptNoPast;

  /// No description provided for @apptPrivateNotes.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات الطبيب خاصة ولا تظهر هنا.'**
  String get apptPrivateNotes;

  /// No description provided for @bookDays.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{يوم واحد} =2{يومين} few{{count} أيام} many{{count} يوماً} other{{count} يوم}}'**
  String bookDays(int count);

  /// No description provided for @bookFollowUpTitle.
  ///
  /// In ar, this message translates to:
  /// **'المتابعة المقترحة: حوالي {date}'**
  String bookFollowUpTitle(String date);

  /// No description provided for @bookFollowUpBody.
  ///
  /// In ar, this message translates to:
  /// **'بعد {span} من موعدك يوم {date}. يمكنك اختيار يوم قبله أو بعده.'**
  String bookFollowUpBody(String span, String date);

  /// No description provided for @bookFollowUpOverdueTitle.
  ///
  /// In ar, this message translates to:
  /// **'حان وقت موعد المتابعة'**
  String get bookFollowUpOverdueTitle;

  /// No description provided for @bookFollowUpOverdueBody.
  ///
  /// In ar, this message translates to:
  /// **'مرّ أكثر من {span} على موعدك يوم {date}. اختر الوقت الذي يناسبك.'**
  String bookFollowUpOverdueBody(String span, String date);

  /// No description provided for @bookFollowUpShow.
  ///
  /// In ar, this message translates to:
  /// **'عرض اليوم المقترح'**
  String get bookFollowUpShow;

  /// No description provided for @bookFollowUpDay.
  ///
  /// In ar, this message translates to:
  /// **'{date}، اليوم المقترح للمتابعة'**
  String bookFollowUpDay(String date);

  /// No description provided for @apptFollowUp.
  ///
  /// In ar, this message translates to:
  /// **'المتابعة القادمة'**
  String get apptFollowUp;

  /// No description provided for @apptFollowUpWhen.
  ///
  /// In ar, this message translates to:
  /// **'حوالي {date}'**
  String apptFollowUpWhen(String date);

  /// No description provided for @apptFollowUpBook.
  ///
  /// In ar, this message translates to:
  /// **'احجز موعد المتابعة'**
  String get apptFollowUpBook;

  /// No description provided for @authSignUpTitle.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء حساب'**
  String get authSignUpTitle;

  /// No description provided for @authSignUpBody.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رقم هاتفك وسنرسل لك رمزاً للتأكيد.'**
  String get authSignUpBody;

  /// No description provided for @authPhoneLabel.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف'**
  String get authPhoneLabel;

  /// No description provided for @authPhoneInvalid.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رقم هاتف نقّال جزائرياً صحيحاً (يبدأ بـ 05 أو 06 أو 07).'**
  String get authPhoneInvalid;

  /// No description provided for @authContinue.
  ///
  /// In ar, this message translates to:
  /// **'متابعة'**
  String get authContinue;

  /// No description provided for @authOr.
  ///
  /// In ar, this message translates to:
  /// **'أو'**
  String get authOr;

  /// No description provided for @authGoogle.
  ///
  /// In ar, this message translates to:
  /// **'المتابعة باستخدام Google'**
  String get authGoogle;

  /// No description provided for @authApple.
  ///
  /// In ar, this message translates to:
  /// **'المتابعة باستخدام Apple'**
  String get authApple;

  /// No description provided for @authSocialNote.
  ///
  /// In ar, this message translates to:
  /// **'حتى مع Google أو Apple، تتحقق العيادة من هويتك قبل أي حجز.'**
  String get authSocialNote;

  /// No description provided for @authHaveAccount.
  ///
  /// In ar, this message translates to:
  /// **'لديك حساب؟'**
  String get authHaveAccount;

  /// No description provided for @authLoginLink.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get authLoginLink;

  /// No description provided for @authNoAccount.
  ///
  /// In ar, this message translates to:
  /// **'ليس لديك حساب؟'**
  String get authNoAccount;

  /// No description provided for @authCreateLink.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء حساب'**
  String get authCreateLink;

  /// No description provided for @authTerms.
  ///
  /// In ar, this message translates to:
  /// **'بإنشاء حساب، فإنك توافق على شروط الاستخدام وسياسة الخصوصية.'**
  String get authTerms;

  /// No description provided for @authPhoneTaken.
  ///
  /// In ar, this message translates to:
  /// **'هذا الرقم مسجّل في حساب آخر. سجّل الدخول بدلاً من ذلك.'**
  String get authPhoneTaken;

  /// No description provided for @authOtpTitle.
  ///
  /// In ar, this message translates to:
  /// **'رمز التأكيد'**
  String get authOtpTitle;

  /// No description provided for @authOtpBody.
  ///
  /// In ar, this message translates to:
  /// **'أدخل الرمز المكوّن من 6 أرقام الذي أرسلناه إلى {phone}.'**
  String authOtpBody(String phone);

  /// No description provided for @authOtpChangeNumber.
  ///
  /// In ar, this message translates to:
  /// **'تغيير الرقم'**
  String get authOtpChangeNumber;

  /// No description provided for @authOtpResendIn.
  ///
  /// In ar, this message translates to:
  /// **'يمكنك طلب رمز جديد بعد {time}'**
  String authOtpResendIn(String time);

  /// No description provided for @authOtpResend.
  ///
  /// In ar, this message translates to:
  /// **'إعادة إرسال الرمز'**
  String get authOtpResend;

  /// No description provided for @authOtpResent.
  ///
  /// In ar, this message translates to:
  /// **'أرسلنا رمزاً جديداً'**
  String get authOtpResent;

  /// No description provided for @authOtpWrong.
  ///
  /// In ar, this message translates to:
  /// **'الرمز غير صحيح. حاول مجدداً.'**
  String get authOtpWrong;

  /// No description provided for @authOtpExpired.
  ///
  /// In ar, this message translates to:
  /// **'انتهت صلاحية هذا الرمز. اطلب رمزاً جديداً.'**
  String get authOtpExpired;

  /// No description provided for @authOtpTooMany.
  ///
  /// In ar, this message translates to:
  /// **'محاولات كثيرة. اطلب رمزاً جديداً.'**
  String get authOtpTooMany;

  /// No description provided for @authOtpSemantics.
  ///
  /// In ar, this message translates to:
  /// **'رمز التأكيد، 6 أرقام'**
  String get authOtpSemantics;

  /// No description provided for @authPasswordTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر كلمة مرور'**
  String get authPasswordTitle;

  /// No description provided for @authPasswordCreateBody.
  ///
  /// In ar, this message translates to:
  /// **'ستستعملها مع رقم هاتفك لتسجيل الدخول.'**
  String get authPasswordCreateBody;

  /// No description provided for @authPasswordResetTitle.
  ///
  /// In ar, this message translates to:
  /// **'كلمة مرور جديدة'**
  String get authPasswordResetTitle;

  /// No description provided for @authPasswordResetBody.
  ///
  /// In ar, this message translates to:
  /// **'اختر كلمة مرور جديدة لحسابك.'**
  String get authPasswordResetBody;

  /// No description provided for @authPasswordLabel.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordConfirmLabel.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد كلمة المرور'**
  String get authPasswordConfirmLabel;

  /// No description provided for @authPasswordShow.
  ///
  /// In ar, this message translates to:
  /// **'إظهار كلمة المرور'**
  String get authPasswordShow;

  /// No description provided for @authPasswordHide.
  ///
  /// In ar, this message translates to:
  /// **'إخفاء كلمة المرور'**
  String get authPasswordHide;

  /// No description provided for @authRuleLength.
  ///
  /// In ar, this message translates to:
  /// **'8 أحرف على الأقل'**
  String get authRuleLength;

  /// No description provided for @authRuleLetter.
  ///
  /// In ar, this message translates to:
  /// **'حرف واحد على الأقل'**
  String get authRuleLetter;

  /// No description provided for @authRuleDigit.
  ///
  /// In ar, this message translates to:
  /// **'رقم واحد على الأقل'**
  String get authRuleDigit;

  /// No description provided for @authRuleMatch.
  ///
  /// In ar, this message translates to:
  /// **'كلمتا المرور متطابقتان'**
  String get authRuleMatch;

  /// No description provided for @authRuleOk.
  ///
  /// In ar, this message translates to:
  /// **'تم: {rule}'**
  String authRuleOk(String rule);

  /// No description provided for @authRuleTodo.
  ///
  /// In ar, this message translates to:
  /// **'لم يتحقق بعد: {rule}'**
  String authRuleTodo(String rule);

  /// No description provided for @authCreateAccountButton.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء الحساب'**
  String get authCreateAccountButton;

  /// No description provided for @authSavePassword.
  ///
  /// In ar, this message translates to:
  /// **'حفظ كلمة المرور'**
  String get authSavePassword;

  /// No description provided for @authLoginTitle.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get authLoginTitle;

  /// No description provided for @authLoginBody.
  ///
  /// In ar, this message translates to:
  /// **'مرحباً بعودتك.'**
  String get authLoginBody;

  /// No description provided for @authLoginButton.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get authLoginButton;

  /// No description provided for @authForgot.
  ///
  /// In ar, this message translates to:
  /// **'نسيت كلمة المرور؟'**
  String get authForgot;

  /// No description provided for @authWrongCredentials.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف أو كلمة المرور غير صحيحة.'**
  String get authWrongCredentials;

  /// No description provided for @authLocked.
  ///
  /// In ar, this message translates to:
  /// **'أوقفنا الدخول مؤقتاً بعد عدة محاولات خاطئة. حاول مجدداً بعد {minutes, plural, =1{دقيقة} =2{دقيقتين} few{{minutes} دقائق} many{{minutes} دقيقة} other{{minutes} دقيقة}}.'**
  String authLocked(int minutes);

  /// No description provided for @authRateLimited.
  ///
  /// In ar, this message translates to:
  /// **'طلبات كثيرة. حاول مجدداً بعد {seconds, plural, =1{ثانية} =2{ثانيتين} few{{seconds} ثوانٍ} many{{seconds} ثانية} other{{seconds} ثانية}}.'**
  String authRateLimited(int seconds);

  /// No description provided for @authNetwork.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الاتصال. تحقق من الإنترنت وحاول مجدداً.'**
  String get authNetwork;

  /// No description provided for @authSocialUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'هذه الطريقة غير متاحة بعد. استعمل رقم هاتفك.'**
  String get authSocialUnavailable;

  /// No description provided for @authForgotTitle.
  ///
  /// In ar, this message translates to:
  /// **'استعادة كلمة المرور'**
  String get authForgotTitle;

  /// No description provided for @authForgotBody.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رقم هاتفك وسنرسل لك رمزاً لاختيار كلمة مرور جديدة.'**
  String get authForgotBody;

  /// No description provided for @authAttachTitle.
  ///
  /// In ar, this message translates to:
  /// **'رقم هاتفك'**
  String get authAttachTitle;

  /// No description provided for @authAttachBody.
  ///
  /// In ar, this message translates to:
  /// **'تستعمله العيادة للتواصل معك بشأن مواعيدك. سنرسل لك رمزاً للتأكيد.'**
  String get authAttachBody;

  /// No description provided for @authSendCode.
  ///
  /// In ar, this message translates to:
  /// **'إرسال الرمز'**
  String get authSendCode;
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
      <String>['ar', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
