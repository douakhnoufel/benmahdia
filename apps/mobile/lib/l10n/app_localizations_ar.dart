// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'بن مهدية';

  @override
  String get appTagline => 'مرافقة التعافي';

  @override
  String get welcomeTitle => 'كل يوم جديد خطوة نحو التعافي';

  @override
  String get welcomeBody =>
      'رفيقك بين الجلسات: تابع تقدّمك ومواعيدك وأدويتك، واستعد جودة حياتك بمرافقة طبيبك.';

  @override
  String get createAccount => 'إنشاء حساب';

  @override
  String get haveAccount => 'لدي حساب — تسجيل الدخول';

  @override
  String get secureFooter => 'بياناتك مشفّرة ومستضافة في الجزائر';

  @override
  String get langArabic => 'العربية';

  @override
  String get langFrench => 'Français';

  @override
  String get splashLine1 => 'خطوة بخطوة نحو التعافي';

  @override
  String get splashLine2 => 'من أجل جودة الحياة';

  @override
  String get introSkip => 'تخطي';

  @override
  String get introNext => 'التالي';

  @override
  String get introStart => 'ابدأ الآن';

  @override
  String introPageOf(int page, int count) {
    return 'الصفحة $page من $count';
  }

  @override
  String get intro1Title => 'كل يوم يُحسب';

  @override
  String get intro1Body =>
      'تابع أيامك دون تعاطٍ، سجّل حالتك كل يوم في دقيقة، واحتفل بكل خطوة تقطعها.';

  @override
  String get intro2Title => 'لست وحدك، في أي ساعة';

  @override
  String get intro2Body =>
      'مرافق رقمي يردّ عليك ليلاً ونهاراً عند الرغبة أو القلق، وينبّه طبيبك إذا احتجت مساعدة عاجلة.';

  @override
  String get intro3Title => 'طبيبك معك بين المواعيد';

  @override
  String get intro3Body =>
      'احجز موعدك بسهولة، تلقَّ تذكير أدويتك في وقتها، وشارك تقدّمك مع طبيبك.';

  @override
  String ringDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'يوم دون تعاطٍ',
      many: 'يوماً دون تعاطٍ',
      few: 'أيام دون تعاطٍ',
      two: 'يومان دون تعاطٍ',
      one: 'يوم دون تعاطٍ',
      zero: 'يوم دون تعاطٍ',
    );
    return '$_temp0';
  }

  @override
  String ringOfGoal(int days, int goal) {
    return '$days من أصل $goal يوماً';
  }

  @override
  String ringNextGoal(int goal) {
    return 'الهدف التالي: $goal يوماً';
  }

  @override
  String introWeek(int done, int total) {
    return 'هذا الأسبوع: $done أيام من $total';
  }

  @override
  String get companionName => 'المرافق';

  @override
  String get companionOnline => 'متاح الآن · 24/24';

  @override
  String get chatSample => 'الرغبة قوية بزاف الليلة، ما قدرتش نرقد…';

  @override
  String get chatReplySample =>
      'أنا هنا معك. خذ نفساً عميقاً لأربع ثوانٍ، ثم أخرجه ببطء. ماذا حدث اليوم قبل أن تبدأ الرغبة؟';

  @override
  String get chipBreathing => 'تمرين تنفّس';

  @override
  String get chipEmergency => 'أرقام الطوارئ';

  @override
  String get apptNext => 'موعدك القادم';

  @override
  String get apptDoctorSample => 'د. بن مهدية حسين';

  @override
  String get apptWhenSample => 'الاثنين 19 أكتوبر · 10:30';

  @override
  String get apptConfirmed => 'مؤكّد';

  @override
  String get medMorning => 'دواء الصباح';

  @override
  String get medEvening => 'دواء المساء';

  @override
  String get medTaken => 'تم';

  @override
  String get medLater => 'لاحقاً';

  @override
  String get doctorWeeklySummary => 'يصل طبيبك ملخّص أسبوعي عن تقدّمك';

  @override
  String get verifyTitle => 'التحقق من الهوية';

  @override
  String verifyStep(int step, int total) {
    return '$step / $total';
  }

  @override
  String verifyStepSemantics(int step, int total) {
    return 'الخطوة $step من $total';
  }

  @override
  String get verifyContinue => 'متابعة';

  @override
  String get selfieTitle => 'ضع وجهك داخل الإطار';

  @override
  String get selfieHint => 'إضاءة جيدة، بدون نظارات شمسية أو قبعة';

  @override
  String get livenessLook => 'انظر إلى الكاميرا';

  @override
  String get livenessTurn => 'أدر رأسك ببطء';

  @override
  String get livenessBlink => 'ارمش مرتين';

  @override
  String get selfieCaptured => 'تم التقاط الصورة';

  @override
  String get selfieAuto => 'تُلتقط الصورة تلقائياً عند اكتمال الخطوات';

  @override
  String get selfiePrivacy => 'تُقارن صورتك بصورة البطاقة فقط، ولا تُنشر';

  @override
  String get idTitle => 'بطاقة التعريف الوطنية';

  @override
  String get idFront => 'الوجه الأمامي';

  @override
  String get idBack => 'الوجه الخلفي';

  @override
  String get idPlaceFront => 'ضع الوجه الأمامي داخل الإطار';

  @override
  String get idPlaceBack => 'اقلب البطاقة وضع الوجه الخلفي داخل الإطار';

  @override
  String get idSearching => 'نبحث عن البطاقة…';

  @override
  String get idDetected => 'تم رصد البطاقة، ثبّت الهاتف';

  @override
  String get idTipSurface => 'ضع البطاقة على سطح داكن ومستوٍ';

  @override
  String get idTipGlare => 'تجنّب الانعكاس والضوء المباشر';

  @override
  String get idTipCorners => 'يجب أن تظهر الزوايا الأربع داخل الإطار';

  @override
  String get idCaptureFront => 'التقاط الوجه الأمامي';

  @override
  String get idCaptureBack => 'التقاط الوجه الخلفي';

  @override
  String get idPrivacy => 'تُستخدم صورة البطاقة للتحقق فقط';

  @override
  String get reviewTitle => 'راجع وأرسل';

  @override
  String get reviewBody => 'تأكّد أن كل شيء جاهز قبل إرسال ملفك إلى العيادة.';

  @override
  String get reviewSelfie => 'صورة شخصية حيّة';

  @override
  String get reviewIdSides => 'الوجهان الأمامي والخلفي للبطاقة';

  @override
  String get reviewSharp => 'صورة البطاقة واضحة';

  @override
  String get reviewNoGlare => 'دون انعكاس للضوء';

  @override
  String get reviewCorners => 'الزوايا الأربع ظاهرة';

  @override
  String get reviewPrivacy =>
      'لا يرى صورك إلا فريق المراجعة في العيادة وطبيبك.';

  @override
  String get reviewSubmit => 'إرسال الملف';

  @override
  String get reviewRetake => 'إعادة تصوير البطاقة';

  @override
  String get pendingTitle => 'تم إرسال ملفك';

  @override
  String get pendingBody =>
      'ستراجع العيادة ملفك، وسنُعلمك فور الموافقة لتحجز موعدك الأول.';

  @override
  String get pendingStatus => 'قيد المراجعة';

  @override
  String get bookTitle => 'حجز موعد';

  @override
  String get bookDoctorTitle => 'اختر طبيبك';

  @override
  String get bookDoctorBody =>
      'أول طبيب تحجز معه يصبح طبيبك المتابع في العيادة.';

  @override
  String get bookClinic => 'عيادة بن مهدية';

  @override
  String bookMinutes(int minutes) {
    return '$minutes دقيقة';
  }

  @override
  String bookPrice(int amount) {
    return '$amount دج';
  }

  @override
  String bookNextFree(String when) {
    return 'أقرب موعد: $when';
  }

  @override
  String bookNoFree(int days) {
    return 'لا مواعيد متاحة خلال $days يوماً القادمة';
  }

  @override
  String bookNotice(int hours) {
    return 'الحجز قبل $hours ساعة على الأقل من الموعد';
  }

  @override
  String get bookChooseTime => 'اختيار اليوم والوقت';

  @override
  String get bookSlotTitle => 'اليوم والوقت';

  @override
  String get bookChange => 'تغيير';

  @override
  String get bookMorning => 'صباحاً';

  @override
  String get bookAfternoon => 'مساءً';

  @override
  String get bookLegendFree => 'متاح';

  @override
  String get bookLegendTaken => 'غير متاح';

  @override
  String get bookLegendYours => 'اختيارك';

  @override
  String get bookNoSlots => 'لا مواعيد في هذا اليوم';

  @override
  String bookTooSoon(int hours) {
    return 'يكون الحجز قبل $hours ساعة على الأقل من الموعد.';
  }

  @override
  String get bookClosed => 'لا يستقبل الطبيب المرضى في هذا اليوم.';

  @override
  String get bookPickTime => 'اختر وقتاً للمتابعة';

  @override
  String get bookContinue => 'متابعة';

  @override
  String get bookSlotGone => 'حجز شخص آخر هذا الوقت للتو. اختر وقتاً آخر.';

  @override
  String get bookConfirmTitle => 'التأكيد والدفع';

  @override
  String bookHeldFor(String time) {
    return 'محجوز لك لمدة $time';
  }

  @override
  String get bookHeldBody => 'إذا لم يكتمل الدفع، يُتاح الموعد لغيرك.';

  @override
  String get bookDate => 'التاريخ';

  @override
  String get bookTime => 'الوقت';

  @override
  String get bookAmount => 'المبلغ';

  @override
  String get bookPayMethod => 'طريقة الدفع';

  @override
  String get bookEdahabia => 'البطاقة الذهبية';

  @override
  String get bookCib => 'بطاقة CIB';

  @override
  String get bookViaChargily => 'عبر Chargily Pay';

  @override
  String get bookClinicPay => 'الدفع في العيادة';

  @override
  String get bookClinicPaySub => 'خلال فترة التجربة، يؤكّده الطبيب';

  @override
  String bookCancelRule(int hours) {
    return 'الإلغاء ممكن حتى $hours ساعة قبل الموعد.';
  }

  @override
  String bookPay(int amount) {
    return 'ادفع $amount دج';
  }

  @override
  String get bookPayNote =>
      'دفع آمن عبر Chargily Pay. لا نحتفظ ببيانات بطاقتك.';

  @override
  String get bookConfirmClinic => 'تأكيد الحجز';

  @override
  String get bookClinicNote => 'تدفع في العيادة يوم الموعد.';

  @override
  String get bookExpiredTitle => 'انتهت مدة الحجز';

  @override
  String get bookExpiredBody => 'أُتيح هذا الموعد لغيرك. يمكنك اختيار وقت آخر.';

  @override
  String get bookPickAnother => 'اختر وقتاً آخر';

  @override
  String get bookDoneTitle => 'تم تأكيد موعدك';

  @override
  String get bookDoneBodyPaid => 'وصلنا دفعك. سنذكّرك قبل الموعد.';

  @override
  String get bookDoneTitleClinic => 'تم حجز موعدك';

  @override
  String get bookDoneBodyClinic => 'ادفع في العيادة يوم الموعد. سنذكّرك قبله.';

  @override
  String bookPaid(int amount) {
    return 'المبلغ المدفوع: $amount دج';
  }

  @override
  String bookToPay(int amount) {
    return 'يُدفع في العيادة: $amount دج';
  }

  @override
  String get bookRemind => 'سنذكّرك بإشعار';

  @override
  String get bookRemind24 => 'قبل 24 ساعة';

  @override
  String get bookRemind1 => 'قبل ساعة';

  @override
  String bookChangeHint(int hours) {
    return 'يمكنك إلغاء الموعد من «مواعيدي» حتى $hours ساعة قبله.';
  }

  @override
  String get bookMyAppointments => 'مواعيدي';

  @override
  String get bookHome => 'العودة إلى الرئيسية';

  @override
  String get bookLoadError => 'تعذّر التحميل. تحقّق من الاتصال وحاول مجدداً.';

  @override
  String get bookErrNotVerified =>
      'لم تتم الموافقة على هويتك بعد. يُفتح الحجز بعد الموافقة.';

  @override
  String get bookErrSignedOut => 'انتهت جلستك. سجّل الدخول من جديد.';

  @override
  String get bookErrForbidden => 'هذا الإجراء غير متاح لحسابك.';

  @override
  String get bookErrDoctorGone => 'هذا الطبيب لم يعد متاحاً. اختر طبيباً آخر.';

  @override
  String get bookErrMethod => 'طريقة الدفع هذه غير متاحة. اختر طريقة أخرى.';

  @override
  String get bookErrPayments =>
      'الدفع بالبطاقة غير متاح حالياً. حاول لاحقاً أو ادفع في العيادة.';

  @override
  String get bookErrNotCancellable => 'لم يعد بالإمكان إلغاء هذا الموعد.';

  @override
  String get bookRetry => 'إعادة المحاولة';

  @override
  String bookWeekday(String day) {
    String _temp0 = intl.Intl.selectLogic(day, {
      'mon': 'الاثنين',
      'tue': 'الثلاثاء',
      'wed': 'الأربعاء',
      'thu': 'الخميس',
      'fri': 'الجمعة',
      'sat': 'السبت',
      'sun': 'الأحد',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String bookWeekdayShort(String day) {
    String _temp0 = intl.Intl.selectLogic(day, {
      'mon': 'اثنين',
      'tue': 'ثلاثاء',
      'wed': 'أربعاء',
      'thu': 'خميس',
      'fri': 'جمعة',
      'sat': 'سبت',
      'sun': 'أحد',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String bookMonth(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'm1': 'جانفي',
      'm2': 'فيفري',
      'm3': 'مارس',
      'm4': 'أفريل',
      'm5': 'ماي',
      'm6': 'جوان',
      'm7': 'جويلية',
      'm8': 'أوت',
      'm9': 'سبتمبر',
      'm10': 'أكتوبر',
      'm11': 'نوفمبر',
      'm12': 'ديسمبر',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String bookDateLong(String weekday, int day, String month) {
    return '$weekday $day $month';
  }

  @override
  String get apptAwaitingPayment => 'بانتظار الدفع';

  @override
  String get apptCompleted => 'تمّ';

  @override
  String get apptCancelledStatus => 'ملغى';

  @override
  String get apptNoShow => 'فائت';

  @override
  String apptUpcoming(int count) {
    return 'القادمة · $count';
  }

  @override
  String get apptPast => 'السابقة';

  @override
  String get apptNew => 'حجز موعد جديد';

  @override
  String get apptCancel => 'إلغاء الموعد';

  @override
  String get apptCancelAsk => 'إلغاء هذا الموعد؟';

  @override
  String get apptCancelBody => 'سيُتاح هذا الوقت لمريض آخر.';

  @override
  String get apptKeep => 'الإبقاء عليه';

  @override
  String get apptCancelled => 'تم إلغاء الموعد';

  @override
  String apptLocked(int hours) {
    return 'بقي أقل من $hours ساعة، لذا لا يمكن الإلغاء من التطبيق. اتصل بالعيادة إذا تعذّر حضورك.';
  }

  @override
  String get apptGone => 'هذا الموعد لم يعد موجوداً. تم تحديث القائمة.';

  @override
  String get apptCode => 'الرمز الذي تقدّمه في الاستقبال';

  @override
  String get apptNoUpcoming => 'لا مواعيد قادمة';

  @override
  String get apptNoPast => 'لا مواعيد سابقة';

  @override
  String get apptPrivateNotes => 'ملاحظات الطبيب خاصة ولا تظهر هنا.';

  @override
  String bookDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يوماً',
      few: '$count أيام',
      two: 'يومين',
      one: 'يوم واحد',
    );
    return '$_temp0';
  }

  @override
  String bookFollowUpTitle(String date) {
    return 'المتابعة المقترحة: حوالي $date';
  }

  @override
  String bookFollowUpBody(String span, String date) {
    return 'بعد $span من موعدك يوم $date. يمكنك اختيار يوم قبله أو بعده.';
  }

  @override
  String get bookFollowUpOverdueTitle => 'حان وقت موعد المتابعة';

  @override
  String bookFollowUpOverdueBody(String span, String date) {
    return 'مرّ أكثر من $span على موعدك يوم $date. اختر الوقت الذي يناسبك.';
  }

  @override
  String get bookFollowUpShow => 'عرض اليوم المقترح';

  @override
  String bookFollowUpDay(String date) {
    return '$date، اليوم المقترح للمتابعة';
  }

  @override
  String get apptFollowUp => 'المتابعة القادمة';

  @override
  String apptFollowUpWhen(String date) {
    return 'حوالي $date';
  }

  @override
  String get apptFollowUpBook => 'احجز موعد المتابعة';

  @override
  String get authSignUpTitle => 'إنشاء حساب';

  @override
  String get authSignUpBody => 'أدخل رقم هاتفك وسنرسل لك رمزاً للتأكيد.';

  @override
  String get authPhoneLabel => 'رقم الهاتف';

  @override
  String get authPhoneInvalid =>
      'أدخل رقم هاتف نقّال جزائرياً صحيحاً (يبدأ بـ 05 أو 06 أو 07).';

  @override
  String get authContinue => 'متابعة';

  @override
  String get authOr => 'أو';

  @override
  String get authGoogle => 'المتابعة باستخدام Google';

  @override
  String get authApple => 'المتابعة باستخدام Apple';

  @override
  String get authSocialNote =>
      'حتى مع Google أو Apple، تتحقق العيادة من هويتك قبل أي حجز.';

  @override
  String get authHaveAccount => 'لديك حساب؟';

  @override
  String get authLoginLink => 'تسجيل الدخول';

  @override
  String get authNoAccount => 'ليس لديك حساب؟';

  @override
  String get authCreateLink => 'إنشاء حساب';

  @override
  String get authTerms =>
      'بإنشاء حساب، فإنك توافق على شروط الاستخدام وسياسة الخصوصية.';

  @override
  String get authPhoneTaken =>
      'هذا الرقم مسجّل في حساب آخر. سجّل الدخول بدلاً من ذلك.';

  @override
  String get authOtpTitle => 'رمز التأكيد';

  @override
  String authOtpBody(String phone) {
    return 'أدخل الرمز المكوّن من 6 أرقام الذي أرسلناه إلى $phone.';
  }

  @override
  String get authOtpChangeNumber => 'تغيير الرقم';

  @override
  String authOtpResendIn(String time) {
    return 'يمكنك طلب رمز جديد بعد $time';
  }

  @override
  String get authOtpResend => 'إعادة إرسال الرمز';

  @override
  String get authOtpResent => 'أرسلنا رمزاً جديداً';

  @override
  String get authOtpWrong => 'الرمز غير صحيح. حاول مجدداً.';

  @override
  String get authOtpExpired => 'انتهت صلاحية هذا الرمز. اطلب رمزاً جديداً.';

  @override
  String get authOtpTooMany => 'محاولات كثيرة. اطلب رمزاً جديداً.';

  @override
  String get authOtpSemantics => 'رمز التأكيد، 6 أرقام';

  @override
  String get authPasswordTitle => 'اختر كلمة مرور';

  @override
  String get authPasswordCreateBody => 'ستستعملها مع رقم هاتفك لتسجيل الدخول.';

  @override
  String get authPasswordResetTitle => 'كلمة مرور جديدة';

  @override
  String get authPasswordResetBody => 'اختر كلمة مرور جديدة لحسابك.';

  @override
  String get authPasswordLabel => 'كلمة المرور';

  @override
  String get authPasswordConfirmLabel => 'تأكيد كلمة المرور';

  @override
  String get authPasswordShow => 'إظهار كلمة المرور';

  @override
  String get authPasswordHide => 'إخفاء كلمة المرور';

  @override
  String get authRuleLength => '8 أحرف على الأقل';

  @override
  String get authRuleLetter => 'حرف واحد على الأقل';

  @override
  String get authRuleDigit => 'رقم واحد على الأقل';

  @override
  String get authRuleMatch => 'كلمتا المرور متطابقتان';

  @override
  String authRuleOk(String rule) {
    return 'تم: $rule';
  }

  @override
  String authRuleTodo(String rule) {
    return 'لم يتحقق بعد: $rule';
  }

  @override
  String get authCreateAccountButton => 'إنشاء الحساب';

  @override
  String get authSavePassword => 'حفظ كلمة المرور';

  @override
  String get authLoginTitle => 'تسجيل الدخول';

  @override
  String get authLoginBody => 'مرحباً بعودتك.';

  @override
  String get authLoginButton => 'تسجيل الدخول';

  @override
  String get authForgot => 'نسيت كلمة المرور؟';

  @override
  String get authWrongCredentials => 'رقم الهاتف أو كلمة المرور غير صحيحة.';

  @override
  String authLocked(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes دقيقة',
      many: '$minutes دقيقة',
      few: '$minutes دقائق',
      two: 'دقيقتين',
      one: 'دقيقة',
    );
    return 'أوقفنا الدخول مؤقتاً بعد عدة محاولات خاطئة. حاول مجدداً بعد $_temp0.';
  }

  @override
  String authRateLimited(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds ثانية',
      many: '$seconds ثانية',
      few: '$seconds ثوانٍ',
      two: 'ثانيتين',
      one: 'ثانية',
    );
    return 'طلبات كثيرة. حاول مجدداً بعد $_temp0.';
  }

  @override
  String get authNetwork => 'تعذّر الاتصال. تحقق من الإنترنت وحاول مجدداً.';

  @override
  String get authSocialUnavailable =>
      'هذه الطريقة غير متاحة بعد. استعمل رقم هاتفك.';

  @override
  String get authForgotTitle => 'استعادة كلمة المرور';

  @override
  String get authForgotBody =>
      'أدخل رقم هاتفك وسنرسل لك رمزاً لاختيار كلمة مرور جديدة.';

  @override
  String get authAttachTitle => 'رقم هاتفك';

  @override
  String get authAttachBody =>
      'تستعمله العيادة للتواصل معك بشأن مواعيدك. سنرسل لك رمزاً للتأكيد.';

  @override
  String get authSendCode => 'إرسال الرمز';

  @override
  String get profileTitle => 'أكمل ملفك';

  @override
  String get profilePromptBody =>
      'نحتاج بطاقة هويتك وصورة سيلفي لتأكيد حجزك مع الطبيب. يمكنك فعل ذلك الآن أو لاحقاً.';

  @override
  String get profileWhatId =>
      'نقرأ رقم بطاقتك واسمك وتاريخ ميلادك من هاتفك. لا نحفظ صورة البطاقة ولا نرسلها.';

  @override
  String get profileWhatSelfie =>
      'نرسل صورة السيلفي مشفّرة إلى طبيبك ليتعرّف عليك عند الاستقبال.';

  @override
  String get profileWhatApproval =>
      'تراجع العيادة ما صرّحتَ به، ثم يُفتح لك الحجز.';

  @override
  String get profileConsent =>
      'أوافق على أن تحفظ العيادة صورتي وبياناتي لهذا الغرض.';

  @override
  String get profileStart => 'ابدأ';

  @override
  String get profileFormTitle => 'بياناتك';

  @override
  String get profileFormBody =>
      'اختر بطاقة التعريف أو جواز السفر، امسحها ثم تأكد من الحقول الثلاثة.';

  @override
  String get profileScan => 'مسح بطاقة الهوية';

  @override
  String get profileScanAgain => 'مسح من جديد';

  @override
  String get profileScanFailed => 'تعذّر فتح الكاميرا. اكتب البيانات بنفسك.';

  @override
  String get profileIdNumber => 'رقم بطاقة الهوية';

  @override
  String get profileFullName => 'الاسم الكامل';

  @override
  String get profileBirthDate => 'تاريخ الميلاد (سنة-شهر-يوم)';

  @override
  String get profileSelfie => 'التقط صورة سيلفي';

  @override
  String get profileSelfieRetake => 'أعد الصورة';

  @override
  String get profileSelfieReady => 'الصورة جاهزة';

  @override
  String get profileSubmit => 'أرسل إلى العيادة';

  @override
  String get profileErrIdNumber => 'رقم الهوية غير صالح.';

  @override
  String get profileErrName => 'اكتب اسمك الكامل.';

  @override
  String get profileErrBirth =>
      'تاريخ الميلاد غير صالح. اكتبه هكذا: 1990-05-17.';

  @override
  String get profileErrSelfie => 'التقط صورة سيلفي أولاً.';

  @override
  String get profileErrLinked =>
      'هذه الهوية مرتبطة بحساب آخر. تواصل مع العيادة.';

  @override
  String get profileErrTooMany =>
      'تجاوزت عدد المحاولات المسموح به. تواصل مع العيادة.';

  @override
  String get profileErrSelfieInvalid => 'تعذّر استعمال الصورة. التقط أخرى.';

  @override
  String get profileErrInvalid =>
      'لم تقبل العيادة هذه البيانات. تحقق منها وحاول مجدداً.';

  @override
  String get profileCardNoneBody => 'أضف هويتك وصورة سيلفي لتتمكن من الحجز.';

  @override
  String get profileCardAction => 'أكمل';

  @override
  String get profileIdDeclared => 'هوية مصرّح بها';

  @override
  String get profileIdDeclaredApproved => 'هوية مصرّح بها · مقبولة';

  @override
  String get profileCardDeclaredTitle => 'في انتظار العيادة';

  @override
  String get profileCardDeclaredBody =>
      'تراجع العيادة بياناتك. يُفتح الحجز بعد الموافقة.';

  @override
  String get profileCardRefresh => 'تحقق مجدداً';

  @override
  String get profileCardRejectedTitle => 'لم تُقبل البيانات';

  @override
  String get profileCardRejectedBody => 'تحقق من بياناتك وأرسلها من جديد.';

  @override
  String profileCardReason(String reason) {
    return 'السبب: $reason';
  }

  @override
  String get profileCardRetry => 'أرسل من جديد';

  @override
  String get profileDoneTitle => 'أُرسلت إلى العيادة';

  @override
  String get profileDoneBody =>
      'ستراجع العيادة بياناتك. يمكنك استعمال التطبيق الآن، ويُفتح الحجز بعد الموافقة.';

  @override
  String get profileDoneAction => 'متابعة';

  @override
  String get navAppointments => 'مواعيدي';

  @override
  String get navRecovery => 'تعافيّ';

  @override
  String get navCompanion => 'المرافق';

  @override
  String get recoveryTitle => 'تعافيّ';

  @override
  String get recoveryTagline => 'خطوة بخطوة نحو التعافي';

  @override
  String recoveryNextGoal(String goal) {
    return 'الهدف التالي: $goal';
  }

  @override
  String recoveryToGo(String days) {
    return 'بقي $days على هدفك';
  }

  @override
  String get recoveryLongest => 'أطول مدة';

  @override
  String get recoveryTotal => 'مجموع الأيام';

  @override
  String get recoveryRelapse => 'مررت بانتكاسة';

  @override
  String get recoveryRelapseTitle => 'لا بأس، هذا جزء من الطريق';

  @override
  String get recoveryRelapseBody =>
      'سيبدأ عدّادك من جديد، لكن أطول مدة ومجموع أيامك يبقيان محفوظين. سيُعلَم طبيبك ليساندك.';

  @override
  String get recoveryRelapseNote => 'ملاحظة أو سبب (اختياري)';

  @override
  String get recoveryRelapseConfirm => 'أعد بدء العدّاد';

  @override
  String get recoveryRelapseCancel => 'تراجع';

  @override
  String get recoveryRelapseDone => 'بداية جديدة. أيامك السابقة محفوظة.';

  @override
  String get recoveryQuoteTitle => 'اقتباس اليوم';

  @override
  String get recoveryMedsTitle => 'أدويتي اليوم';

  @override
  String recoveryMedsCount(int taken, int total) {
    return '$taken من $total';
  }

  @override
  String get recoveryNoMeds => 'لا أدوية لليوم.';

  @override
  String get recoveryDoseTake => 'أخذته';

  @override
  String get recoveryDoseSkip => 'لم آخذه';

  @override
  String get recoveryDoseTaken => 'أُخذ';

  @override
  String get recoveryDoseSkipped => 'لم يُؤخذ';

  @override
  String get recoveryNextAppt => 'موعدك القادم';

  @override
  String get clinicTitle => 'عيادتك';

  @override
  String get clinicOpenToday => 'مفتوحة اليوم';

  @override
  String get clinicClosedToday => 'مغلقة اليوم';

  @override
  String get clinicHoursToday => 'مواعيد العمل اليوم';

  @override
  String get clinicMaps => 'افتح في خرائط Google';

  @override
  String get clinicCall => 'اتصل بالعيادة';

  @override
  String clinicCallNumber(String phone) {
    return 'اتصل بالرقم $phone';
  }

  @override
  String get companionTitle => 'المرافق';

  @override
  String get companionSubtitle => 'مساعد ذكي، ولست طبيباً';

  @override
  String get companionIntroTitle => 'قبل أن نبدأ';

  @override
  String get companionIntroAi =>
      'أنا مساعد ذكي يستمع إليك بين المواعيد، ولست طبيباً.';

  @override
  String get companionIntroNoDiagnosis =>
      'لا أقدّم تشخيصاً ولا أغيّر دواءك. طبيبك هو المرجع دائماً.';

  @override
  String get companionIntroPrivacy =>
      'لا يرى طبيبك إلا الرسائل التي تُنبَّه لسلامتك، وملخّصاً قصيراً إن وافقت.';

  @override
  String get companionIntroAgree => 'فهمت، لنبدأ';

  @override
  String get companionGreeting =>
      'مرحباً، أنا المرافق. أنا هنا لأستمع إليك. كيف تشعر الآن؟';

  @override
  String get companionHint => 'اكتب رسالتك…';

  @override
  String get companionSend => 'إرسال';

  @override
  String get companionTyping => 'المرافق يكتب…';

  @override
  String get companionDisclaimer => 'لا يقدّم المرافق تشخيصاً ولا يغيّر دواءك.';

  @override
  String get companionUrgent => 'مساعدة عاجلة';

  @override
  String get companionQuickCraving => 'أشعر برغبة قوية';

  @override
  String get companionQuickBreath => 'تمرين التنفّس';

  @override
  String get companionQuickDoctor => 'أريد التحدّث مع الطبيب';

  @override
  String get companionBook => 'احجز موعداً';

  @override
  String get crisisTitle => 'أنت لست وحدك';

  @override
  String get crisisBody => 'إذا كنت في خطر أو تفكّر في إيذاء نفسك، اتصل الآن.';

  @override
  String get crisisEmergency => 'أرقام الطوارئ: [تؤكّدها العيادة]';

  @override
  String get crisisClose => 'إغلاق';

  @override
  String addictionType(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'opioids': 'المواد الأفيونية',
      'cannabis': 'القنب',
      'alcohol': 'الكحول',
      'tobacco': 'التبغ',
      'pills': 'الأقراص المهلوسة',
      'gambling': 'القمار',
      'other': 'أخرى',
    });
    return '$_temp0';
  }

  @override
  String recoveryCleanSince(String date) {
    return 'دون تعاطٍ منذ $date';
  }

  @override
  String get checkInTitle => 'هذا الأسبوع';

  @override
  String checkInCount(int count) {
    return '$count من 7';
  }

  @override
  String get checkInAction => 'مرّ اليوم دون تعاطٍ';

  @override
  String get checkInDone => 'سُجّل يومك. أحسنت.';

  @override
  String checkInDayDone(String day) {
    return '$day: سُجّل';
  }

  @override
  String checkInDayOpen(String day) {
    return '$day: لم يُسجّل';
  }

  @override
  String get checkInReminder => 'التذكير اليومي';

  @override
  String get checkInReminderOff => 'متوقف';

  @override
  String get checkInReminderPick => 'اختر وقت التذكير';

  @override
  String get checkInReminderStop => 'إيقاف التذكير';

  @override
  String get relapseWhen => 'متى حدث ذلك؟';

  @override
  String get relapseToday => 'اليوم';

  @override
  String get relapseYesterday => 'أمس';

  @override
  String get relapseTime => 'الوقت';

  @override
  String get addictionFormTitle => 'ممّ تتعافى؟';

  @override
  String get addictionFormBody =>
      'اختر النوع وتاريخ آخر تعاطٍ. سيراجع طبيبك هذه المعلومات.';

  @override
  String get addictionTypeLabel => 'النوع';

  @override
  String get addictionSubstance => 'المادة بالتحديد (اختياري)';

  @override
  String get addictionSubstanceHint => 'مثال: اسم الدواء أو المادة';

  @override
  String get addictionCleanSince => 'دون تعاطٍ منذ';

  @override
  String get addictionPickDate => 'اختر التاريخ';

  @override
  String get addictionSave => 'حفظ';

  @override
  String get addictionAdd => 'أضف ما تتعافى منه';

  @override
  String get addictionAddAnother => 'أضف إدماناً آخر';

  @override
  String get addictionEmpty => 'أضف ما تتعافى منه ليبدأ عدّادك.';

  @override
  String get addictionPending => 'في انتظار مراجعة الطبيب';

  @override
  String get addictionSaved => 'حُفظ. سيراجعه طبيبك.';

  @override
  String get recoverySaveError => 'تعذّر الحفظ. تحقّق من الاتصال وحاول مجدداً.';

  @override
  String get profileDocNationalId => 'بطاقة التعريف الجزائرية';

  @override
  String get profileDocPassport => 'جواز السفر الجزائري';

  @override
  String get profileScanPassport => 'مسح جواز السفر';

  @override
  String get profilePassportNumber => 'رقم جواز السفر';

  @override
  String get scanPlaceCard => 'ضع البطاقة داخل الإطار';

  @override
  String get scanPlacePassport =>
      'ضع صفحة الصورة داخل الإطار مع السطرين في الأسفل';

  @override
  String get scanHold => 'ثبّت الهاتف…';

  @override
  String get scanSlow =>
      'القراءة صعبة. جرّب إضاءة أفضل، أو اكتب المعلومات بنفسك.';

  @override
  String get scanPrivacy => 'تُقرأ الوثيقة على هاتفك، ولا تُحفظ أي صورة.';

  @override
  String get scanTorchOn => 'تشغيل الإضاءة';

  @override
  String get scanTorchOff => 'إطفاء الإضاءة';

  @override
  String get scanTypeInstead => 'اكتبها بنفسي';

  @override
  String get cameraClose => 'إغلاق';

  @override
  String get cameraDenied =>
      'لا يمكن استعمال الكاميرا. اسمح للتطبيق باستعمالها من إعدادات الهاتف، أو اكتب المعلومات بنفسك.';

  @override
  String get cameraRetry => 'حاول مجدداً';

  @override
  String get selfieCamTitle => 'صورتك الشخصية';

  @override
  String get selfieNoFace => 'انظر إلى الكاميرا';

  @override
  String get selfieOneFace => 'وجه واحد فقط من فضلك';

  @override
  String get selfieCloser => 'اقترب قليلاً';

  @override
  String get selfieCenter => 'ضع وجهك وسط الإطار';

  @override
  String get selfieReady => 'ممتاز، التقط الصورة';

  @override
  String get selfieTake => 'التقاط الصورة';

  @override
  String get selfieCheck => 'هل الصورة واضحة؟';

  @override
  String get selfieUse => 'استعمل هذه الصورة';

  @override
  String get selfieCamPrivacy => 'تُرسل الصورة مشفّرة إلى طبيبك فقط.';

  @override
  String get scanNotAlgerian => 'نقبل جواز السفر الجزائري فقط.';
}
