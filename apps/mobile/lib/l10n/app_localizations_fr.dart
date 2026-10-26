// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'BenMahdia';

  @override
  String get appTagline => 'Accompagnement du rétablissement';

  @override
  String get welcomeTitle =>
      'Chaque nouveau jour est un pas vers le rétablissement';

  @override
  String get welcomeBody =>
      'Votre compagnon entre les séances : suivez vos progrès, vos rendez-vous et vos médicaments, et retrouvez une meilleure qualité de vie avec votre médecin à vos côtés.';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get haveAccount => 'J\'ai un compte — Se connecter';

  @override
  String get secureFooter =>
      'Vos données sont chiffrées et hébergées en Algérie';

  @override
  String get langArabic => 'العربية';

  @override
  String get langFrench => 'Français';

  @override
  String get splashLine1 => 'Pas à pas vers le rétablissement';

  @override
  String get splashLine2 => 'Pour une meilleure qualité de vie';

  @override
  String get introSkip => 'Passer';

  @override
  String get introNext => 'Suivant';

  @override
  String get introStart => 'Commencer';

  @override
  String introPageOf(int page, int count) {
    return 'Page $page sur $count';
  }

  @override
  String get intro1Title => 'Chaque jour compte';

  @override
  String get intro1Body =>
      'Suivez vos jours sans consommer, notez votre état en une minute chaque jour, et célébrez chaque étape franchie.';

  @override
  String get intro2Title => 'Jamais seul, à toute heure';

  @override
  String get intro2Body =>
      'Un compagnon numérique vous répond jour et nuit en cas d\'envie ou d\'angoisse, et alerte votre médecin si vous avez besoin d\'aide rapidement.';

  @override
  String get intro3Title => 'Votre médecin, même entre les rendez-vous';

  @override
  String get intro3Body =>
      'Réservez en quelques secondes, recevez vos rappels de traitement à l\'heure, et partagez vos progrès avec votre médecin.';

  @override
  String ringDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'jours sans consommer',
      one: 'jour sans consommer',
      zero: 'jour sans consommer',
    );
    return '$_temp0';
  }

  @override
  String ringOfGoal(int days, int goal) {
    return '$days jours sur $goal';
  }

  @override
  String ringNextGoal(int goal) {
    return 'Prochain cap : $goal jours';
  }

  @override
  String introWeek(int done, int total) {
    return 'Cette semaine : $done jours sur $total';
  }

  @override
  String get companionName => 'Compagnon';

  @override
  String get companionOnline => 'Disponible · 24h/24';

  @override
  String get chatSample =>
      'L\'envie est très forte ce soir, je n\'arrive pas à dormir…';

  @override
  String get chatReplySample =>
      'Je suis là. Inspirez 4 secondes, puis expirez lentement. Que s\'est-il passé avant cette envie ?';

  @override
  String get chipBreathing => 'Respiration guidée';

  @override
  String get chipEmergency => 'Numéros d\'urgence';

  @override
  String get apptNext => 'Prochain rendez-vous';

  @override
  String get apptDoctorSample => 'Dr Benmahdia Hocine';

  @override
  String get apptWhenSample => 'Lun. 19 oct. · 10h30';

  @override
  String get apptConfirmed => 'Confirmé';

  @override
  String get medMorning => 'Traitement du matin';

  @override
  String get medEvening => 'Traitement du soir';

  @override
  String get medTaken => 'Pris';

  @override
  String get medLater => 'À venir';

  @override
  String get doctorWeeklySummary =>
      'Votre médecin reçoit un résumé chaque semaine';

  @override
  String get verifyTitle => 'Vérification d\'identité';

  @override
  String verifyStep(int step, int total) {
    return '$step / $total';
  }

  @override
  String verifyStepSemantics(int step, int total) {
    return 'Étape $step sur $total';
  }

  @override
  String get verifyContinue => 'Continuer';

  @override
  String get selfieTitle => 'Placez votre visage dans le cadre';

  @override
  String get selfieHint =>
      'Bonne lumière, sans lunettes de soleil ni casquette';

  @override
  String get livenessLook => 'Regardez la caméra';

  @override
  String get livenessTurn => 'Tournez lentement la tête';

  @override
  String get livenessBlink => 'Clignez des yeux deux fois';

  @override
  String get selfieCaptured => 'Photo prise';

  @override
  String get selfieAuto =>
      'La photo est prise automatiquement à la fin des étapes';

  @override
  String get selfiePrivacy =>
      'Votre photo sert uniquement à la comparer à votre carte';

  @override
  String get idTitle => 'Carte nationale d\'identité';

  @override
  String get idFront => 'Recto';

  @override
  String get idBack => 'Verso';

  @override
  String get idPlaceFront => 'Placez le recto dans le cadre';

  @override
  String get idPlaceBack =>
      'Retournez la carte et placez le verso dans le cadre';

  @override
  String get idSearching => 'Recherche de la carte…';

  @override
  String get idDetected => 'Carte détectée, ne bougez plus';

  @override
  String get idTipSurface => 'Posez la carte sur une surface sombre et plane';

  @override
  String get idTipGlare => 'Évitez les reflets et la lumière directe';

  @override
  String get idTipCorners => 'Les quatre coins doivent être dans le cadre';

  @override
  String get idCaptureFront => 'Prendre le recto en photo';

  @override
  String get idCaptureBack => 'Prendre le verso en photo';

  @override
  String get idPrivacy =>
      'La photo de la carte sert uniquement à la vérification';

  @override
  String get reviewTitle => 'Vérifiez et envoyez';

  @override
  String get reviewBody =>
      'Vérifiez que tout est prêt avant d\'envoyer votre dossier à la clinique.';

  @override
  String get reviewSelfie => 'Selfie pris en direct';

  @override
  String get reviewIdSides => 'Recto et verso de la carte';

  @override
  String get reviewSharp => 'Photo de la carte nette';

  @override
  String get reviewNoGlare => 'Sans reflet';

  @override
  String get reviewCorners => 'Les quatre coins sont visibles';

  @override
  String get reviewPrivacy =>
      'Seuls l\'équipe de vérification de la clinique et votre médecin voient vos photos.';

  @override
  String get reviewSubmit => 'Envoyer le dossier';

  @override
  String get reviewRetake => 'Reprendre la carte en photo';

  @override
  String get pendingTitle => 'Dossier envoyé';

  @override
  String get pendingBody =>
      'La clinique va examiner votre dossier. Nous vous préviendrons dès sa validation pour réserver votre premier rendez-vous.';

  @override
  String get pendingStatus => 'En cours d\'examen';

  @override
  String get bookTitle => 'Prendre rendez-vous';

  @override
  String get bookDoctorTitle => 'Choisissez votre médecin';

  @override
  String get bookDoctorBody =>
      'Le premier médecin avec qui vous réservez devient votre médecin traitant à la clinique.';

  @override
  String get bookClinic => 'Clinique Benmahdia';

  @override
  String bookMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String bookPrice(int amount) {
    return '$amount DA';
  }

  @override
  String bookNextFree(String when) {
    return 'Prochain créneau : $when';
  }

  @override
  String bookNoFree(int days) {
    return 'Aucun créneau libre dans les $days prochains jours';
  }

  @override
  String bookNotice(int hours) {
    return 'Réservez au moins $hours h à l\'avance';
  }

  @override
  String get bookChooseTime => 'Choisir le jour et l\'heure';

  @override
  String get bookSlotTitle => 'Jour et heure';

  @override
  String get bookChange => 'Modifier';

  @override
  String get bookMorning => 'Matin';

  @override
  String get bookAfternoon => 'Après-midi';

  @override
  String get bookLegendFree => 'Libre';

  @override
  String get bookLegendTaken => 'Indisponible';

  @override
  String get bookLegendYours => 'Votre choix';

  @override
  String get bookNoSlots => 'Aucun créneau ce jour-là';

  @override
  String bookTooSoon(int hours) {
    return 'La réservation se fait au moins $hours h à l\'avance.';
  }

  @override
  String get bookClosed => 'Le médecin ne consulte pas ce jour-là.';

  @override
  String get bookPickTime => 'Choisissez une heure pour continuer';

  @override
  String get bookContinue => 'Continuer';

  @override
  String get bookSlotGone =>
      'Ce créneau vient d\'être pris. Choisissez-en un autre.';

  @override
  String get bookConfirmTitle => 'Confirmation et paiement';

  @override
  String bookHeldFor(String time) {
    return 'Réservé pour vous pendant $time';
  }

  @override
  String get bookHeldBody => 'Sans paiement, le créneau sera libéré.';

  @override
  String get bookDate => 'Date';

  @override
  String get bookTime => 'Heure';

  @override
  String get bookAmount => 'Montant';

  @override
  String get bookPayMethod => 'Moyen de paiement';

  @override
  String get bookEdahabia => 'Carte Edahabia';

  @override
  String get bookCib => 'Carte CIB';

  @override
  String get bookViaChargily => 'Via Chargily Pay';

  @override
  String get bookClinicPay => 'Payer à la clinique';

  @override
  String get bookClinicPaySub =>
      'Pendant la phase pilote, confirmé par le médecin';

  @override
  String bookCancelRule(int hours) {
    return 'Annulation possible jusqu\'à $hours h avant le rendez-vous.';
  }

  @override
  String bookPay(int amount) {
    return 'Payer $amount DA';
  }

  @override
  String get bookPayNote =>
      'Paiement sécurisé via Chargily Pay. Nous ne gardons pas les données de votre carte.';

  @override
  String get bookConfirmClinic => 'Confirmer la réservation';

  @override
  String get bookClinicNote =>
      'Vous payez à la clinique le jour du rendez-vous.';

  @override
  String get bookExpiredTitle => 'Le délai est écoulé';

  @override
  String get bookExpiredBody =>
      'Ce créneau a été libéré. Vous pouvez en choisir un autre.';

  @override
  String get bookPickAnother => 'Choisir une autre heure';

  @override
  String get bookDoneTitle => 'Rendez-vous confirmé';

  @override
  String get bookDoneBodyPaid => 'Paiement reçu. Nous vous le rappellerons.';

  @override
  String get bookDoneTitleClinic => 'Rendez-vous réservé';

  @override
  String get bookDoneBodyClinic =>
      'Payez à la clinique le jour même. Nous vous le rappellerons.';

  @override
  String bookPaid(int amount) {
    return 'Montant payé : $amount DA';
  }

  @override
  String bookToPay(int amount) {
    return 'À payer à la clinique : $amount DA';
  }

  @override
  String get bookRemind => 'Nous vous enverrons un rappel';

  @override
  String get bookRemind24 => '24 h avant';

  @override
  String get bookRemind1 => '1 h avant';

  @override
  String bookChangeHint(int hours) {
    return 'Vous pouvez l\'annuler dans « Mes rendez-vous » jusqu\'à $hours h avant.';
  }

  @override
  String get bookMyAppointments => 'Mes rendez-vous';

  @override
  String get bookHome => 'Retour à l\'accueil';

  @override
  String get bookLoadError =>
      'Chargement impossible. Vérifiez la connexion et réessayez.';

  @override
  String get bookErrNotVerified =>
      'Votre identité n\'est pas encore approuvée. La réservation s\'ouvre après l\'accord.';

  @override
  String get bookErrSignedOut => 'Votre session a expiré. Reconnectez-vous.';

  @override
  String get bookErrForbidden =>
      'Cette action n\'est pas possible avec votre compte.';

  @override
  String get bookErrDoctorGone =>
      'Ce médecin n\'est plus disponible. Choisissez-en un autre.';

  @override
  String get bookErrMethod =>
      'Ce mode de paiement n\'est pas disponible. Choisissez-en un autre.';

  @override
  String get bookErrPayments =>
      'Le paiement par carte est indisponible pour le moment. Réessayez plus tard ou payez à la clinique.';

  @override
  String get bookErrNotCancellable =>
      'Ce rendez-vous ne peut plus être annulé.';

  @override
  String get bookRetry => 'Réessayer';

  @override
  String bookWeekday(String day) {
    String _temp0 = intl.Intl.selectLogic(day, {
      'mon': 'lundi',
      'tue': 'mardi',
      'wed': 'mercredi',
      'thu': 'jeudi',
      'fri': 'vendredi',
      'sat': 'samedi',
      'sun': 'dimanche',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String bookWeekdayShort(String day) {
    String _temp0 = intl.Intl.selectLogic(day, {
      'mon': 'lun.',
      'tue': 'mar.',
      'wed': 'mer.',
      'thu': 'jeu.',
      'fri': 'ven.',
      'sat': 'sam.',
      'sun': 'dim.',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String bookMonth(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'm1': 'janvier',
      'm2': 'février',
      'm3': 'mars',
      'm4': 'avril',
      'm5': 'mai',
      'm6': 'juin',
      'm7': 'juillet',
      'm8': 'août',
      'm9': 'septembre',
      'm10': 'octobre',
      'm11': 'novembre',
      'm12': 'décembre',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String bookDateLong(String weekday, int day, String month) {
    return '$weekday $day $month';
  }

  @override
  String get apptAwaitingPayment => 'En attente de paiement';

  @override
  String get apptCompleted => 'Terminé';

  @override
  String get apptCancelledStatus => 'Annulé';

  @override
  String get apptNoShow => 'Manqué';

  @override
  String apptUpcoming(int count) {
    return 'À venir · $count';
  }

  @override
  String get apptPast => 'Passés';

  @override
  String get apptNew => 'Nouveau rendez-vous';

  @override
  String get apptCancel => 'Annuler le rendez-vous';

  @override
  String get apptCancelAsk => 'Annuler ce rendez-vous ?';

  @override
  String get apptCancelBody => 'Le créneau sera proposé à un autre patient.';

  @override
  String get apptKeep => 'Le garder';

  @override
  String get apptCancelled => 'Rendez-vous annulé';

  @override
  String apptLocked(int hours) {
    return 'Moins de $hours h avant le rendez-vous : l\'annulation n\'est plus possible dans l\'application. Appelez la clinique si vous ne pouvez pas venir.';
  }

  @override
  String get apptGone =>
      'Ce rendez-vous n\'existe plus. La liste a été mise à jour.';

  @override
  String get apptCode => 'Code à donner à l\'accueil';

  @override
  String get apptNoUpcoming => 'Aucun rendez-vous à venir';

  @override
  String get apptNoPast => 'Aucun rendez-vous passé';

  @override
  String get apptPrivateNotes =>
      'Les notes du médecin sont privées et n\'apparaissent pas ici.';

  @override
  String bookDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '1 jour',
    );
    return '$_temp0';
  }

  @override
  String bookFollowUpTitle(String date) {
    return 'Suivi conseillé : vers le $date';
  }

  @override
  String bookFollowUpBody(String span, String date) {
    return '$span après votre rendez-vous du $date. Vous pouvez choisir un jour avant ou après.';
  }

  @override
  String get bookFollowUpOverdueTitle => 'C\'est le moment de votre suivi';

  @override
  String bookFollowUpOverdueBody(String span, String date) {
    return 'Plus de $span depuis votre rendez-vous du $date. Choisissez le moment qui vous convient.';
  }

  @override
  String get bookFollowUpShow => 'Voir le jour conseillé';

  @override
  String bookFollowUpDay(String date) {
    return '$date, jour de suivi conseillé';
  }

  @override
  String get apptFollowUp => 'Prochain suivi';

  @override
  String apptFollowUpWhen(String date) {
    return 'Vers le $date';
  }

  @override
  String get apptFollowUpBook => 'Réserver le suivi';

  @override
  String get authSignUpTitle => 'Créer un compte';

  @override
  String get authSignUpBody =>
      'Entrez votre numéro de téléphone, nous vous enverrons un code de confirmation.';

  @override
  String get authPhoneLabel => 'Numéro de téléphone';

  @override
  String get authPhoneInvalid =>
      'Entrez un numéro de mobile algérien valide (commençant par 05, 06 ou 07).';

  @override
  String get authContinue => 'Continuer';

  @override
  String get authOr => 'ou';

  @override
  String get authGoogle => 'Continuer avec Google';

  @override
  String get authApple => 'Continuer avec Apple';

  @override
  String get authSocialNote =>
      'Même avec Google ou Apple, la clinique vérifie votre identité avant toute réservation.';

  @override
  String get authHaveAccount => 'Vous avez déjà un compte ?';

  @override
  String get authLoginLink => 'Se connecter';

  @override
  String get authNoAccount => 'Pas encore de compte ?';

  @override
  String get authCreateLink => 'Créer un compte';

  @override
  String get authTerms =>
      'En créant un compte, vous acceptez les conditions d\'utilisation et la politique de confidentialité.';

  @override
  String get authPhoneTaken =>
      'Ce numéro a déjà un compte. Connectez-vous plutôt.';

  @override
  String get authOtpTitle => 'Code de confirmation';

  @override
  String authOtpBody(String phone) {
    return 'Entrez le code à 6 chiffres envoyé au $phone.';
  }

  @override
  String get authOtpChangeNumber => 'Modifier le numéro';

  @override
  String authOtpResendIn(String time) {
    return 'Nouveau code possible dans $time';
  }

  @override
  String get authOtpResend => 'Renvoyer le code';

  @override
  String get authOtpResent => 'Nouveau code envoyé';

  @override
  String get authOtpWrong => 'Code incorrect. Réessayez.';

  @override
  String get authOtpExpired => 'Ce code a expiré. Demandez-en un nouveau.';

  @override
  String get authOtpTooMany => 'Trop d\'essais. Demandez un nouveau code.';

  @override
  String get authOtpSemantics => 'Code de confirmation, 6 chiffres';

  @override
  String get authPasswordTitle => 'Choisissez un mot de passe';

  @override
  String get authPasswordCreateBody =>
      'Vous l\'utiliserez avec votre numéro pour vous connecter.';

  @override
  String get authPasswordResetTitle => 'Nouveau mot de passe';

  @override
  String get authPasswordResetBody =>
      'Choisissez un nouveau mot de passe pour votre compte.';

  @override
  String get authPasswordLabel => 'Mot de passe';

  @override
  String get authPasswordConfirmLabel => 'Confirmer le mot de passe';

  @override
  String get authPasswordShow => 'Afficher le mot de passe';

  @override
  String get authPasswordHide => 'Masquer le mot de passe';

  @override
  String get authRuleLength => 'Au moins 8 caractères';

  @override
  String get authRuleLetter => 'Au moins une lettre';

  @override
  String get authRuleDigit => 'Au moins un chiffre';

  @override
  String get authRuleMatch => 'Les deux mots de passe correspondent';

  @override
  String authRuleOk(String rule) {
    return 'Validé : $rule';
  }

  @override
  String authRuleTodo(String rule) {
    return 'Pas encore : $rule';
  }

  @override
  String get authCreateAccountButton => 'Créer le compte';

  @override
  String get authSavePassword => 'Enregistrer le mot de passe';

  @override
  String get authLoginTitle => 'Connexion';

  @override
  String get authLoginBody => 'Bon retour parmi nous.';

  @override
  String get authLoginButton => 'Se connecter';

  @override
  String get authForgot => 'Mot de passe oublié ?';

  @override
  String get authWrongCredentials => 'Numéro ou mot de passe incorrect.';

  @override
  String authLocked(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return 'Connexion suspendue après plusieurs essais. Réessayez dans $_temp0.';
  }

  @override
  String authRateLimited(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondes',
      one: '1 seconde',
    );
    return 'Trop de demandes. Réessayez dans $_temp0.';
  }

  @override
  String get authNetwork =>
      'Connexion impossible. Vérifiez internet et réessayez.';

  @override
  String get authSocialUnavailable =>
      'Cette option n\'est pas encore disponible. Utilisez votre numéro.';

  @override
  String get authForgotTitle => 'Mot de passe oublié';

  @override
  String get authForgotBody =>
      'Entrez votre numéro, nous vous enverrons un code pour choisir un nouveau mot de passe.';

  @override
  String get authAttachTitle => 'Votre numéro';

  @override
  String get authAttachBody =>
      'La clinique l\'utilise pour vous joindre au sujet de vos rendez-vous. Nous vous enverrons un code de confirmation.';

  @override
  String get authSendCode => 'Envoyer le code';

  @override
  String get profileTitle => 'Complétez votre profil';

  @override
  String get profilePromptBody =>
      'Nous avons besoin de votre carte d\'identité et d\'un selfie pour confirmer vos rendez-vous avec le médecin. Vous pouvez le faire maintenant ou plus tard.';

  @override
  String get profileWhatId =>
      'Votre numéro, votre nom et votre date de naissance sont lus sur votre téléphone. La photo de la carte n\'est ni conservée ni envoyée.';

  @override
  String get profileWhatSelfie =>
      'Le selfie est envoyé chiffré à votre médecin pour vous reconnaître à l\'accueil.';

  @override
  String get profileWhatApproval =>
      'La clinique vérifie ce que vous avez déclaré, puis la réservation s\'ouvre.';

  @override
  String get profileConsent =>
      'J\'accepte que la clinique conserve mon selfie et mes informations pour cet usage.';

  @override
  String get profileStart => 'Commencer';

  @override
  String get profileFormTitle => 'Vos informations';

  @override
  String get profileFormBody =>
      'Choisissez la carte d\'identité ou le passeport, scannez-le, puis vérifiez les trois champs.';

  @override
  String get profileScan => 'Scanner ma carte d\'identité';

  @override
  String get profileScanAgain => 'Scanner à nouveau';

  @override
  String get profileScanFailed =>
      'Impossible d\'ouvrir la caméra. Saisissez les informations vous-même.';

  @override
  String get profileIdNumber => 'Numéro de la carte';

  @override
  String get profileFullName => 'Nom complet';

  @override
  String get profileBirthDate => 'Date de naissance (AAAA-MM-JJ)';

  @override
  String get profileSelfie => 'Prendre un selfie';

  @override
  String get profileSelfieRetake => 'Refaire le selfie';

  @override
  String get profileSelfieReady => 'Selfie prêt';

  @override
  String get profileSubmit => 'Envoyer à la clinique';

  @override
  String get profileErrIdNumber => 'Numéro de carte invalide.';

  @override
  String get profileErrName => 'Saisissez votre nom complet.';

  @override
  String get profileErrBirth =>
      'Date de naissance invalide. Exemple : 1990-05-17.';

  @override
  String get profileErrSelfie => 'Prenez d\'abord un selfie.';

  @override
  String get profileErrLinked =>
      'Cette carte est déjà liée à un autre compte. Contactez la clinique.';

  @override
  String get profileErrTooMany =>
      'Nombre d\'essais dépassé. Contactez la clinique.';

  @override
  String get profileErrSelfieInvalid =>
      'Le selfie n\'a pas pu être utilisé. Reprenez-en un.';

  @override
  String get profileErrInvalid =>
      'La clinique n\'a pas pu accepter ces informations. Vérifiez-les et réessayez.';

  @override
  String get profileCardNoneBody =>
      'Ajoutez votre carte d\'identité et un selfie pour pouvoir réserver.';

  @override
  String get profileCardAction => 'Compléter';

  @override
  String get profileIdDeclared => 'Identité déclarée';

  @override
  String get profileIdDeclaredApproved => 'Identité déclarée · approuvée';

  @override
  String get profileCardDeclaredTitle => 'En attente de la clinique';

  @override
  String get profileCardDeclaredBody =>
      'La clinique examine vos informations. La réservation s\'ouvre après son accord.';

  @override
  String get profileCardRefresh => 'Vérifier à nouveau';

  @override
  String get profileCardRejectedTitle => 'Informations refusées';

  @override
  String get profileCardRejectedBody =>
      'Vérifiez vos informations et envoyez-les à nouveau.';

  @override
  String profileCardReason(String reason) {
    return 'Motif : $reason';
  }

  @override
  String get profileCardRetry => 'Renvoyer';

  @override
  String get profileDoneTitle => 'Envoyé à la clinique';

  @override
  String get profileDoneBody =>
      'La clinique va examiner vos informations. Vous pouvez utiliser l\'application ; la réservation s\'ouvre après son accord.';

  @override
  String get profileDoneAction => 'Continuer';

  @override
  String get navAppointments => 'Rendez-vous';

  @override
  String get navRecovery => 'Mon parcours';

  @override
  String get navCompanion => 'Compagnon';

  @override
  String get recoveryTitle => 'Mon parcours';

  @override
  String get recoveryTagline => 'Pas à pas vers le rétablissement';

  @override
  String recoveryNextGoal(String goal) {
    return 'Prochain objectif : $goal';
  }

  @override
  String recoveryToGo(String days) {
    return 'Encore $days avant votre objectif';
  }

  @override
  String get recoveryLongest => 'Plus longue série';

  @override
  String get recoveryTotal => 'Total des jours';

  @override
  String get recoveryRelapse => 'J\'ai rechuté';

  @override
  String get recoveryRelapseTitle => 'Ce n\'est pas un échec';

  @override
  String get recoveryRelapseBody =>
      'Votre compteur repart de zéro, mais votre plus longue série et le total de vos jours restent enregistrés. Votre médecin sera prévenu pour vous soutenir.';

  @override
  String get recoveryRelapseNote => 'Une note ou un déclencheur (facultatif)';

  @override
  String get recoveryRelapseConfirm => 'Redémarrer mon compteur';

  @override
  String get recoveryRelapseCancel => 'Annuler';

  @override
  String get recoveryRelapseDone =>
      'Un nouveau départ. Vos jours précédents restent enregistrés.';

  @override
  String get recoveryQuoteTitle => 'Citation du jour';

  @override
  String get recoveryMedsTitle => 'Mes médicaments du jour';

  @override
  String recoveryMedsCount(int taken, int total) {
    return '$taken sur $total';
  }

  @override
  String get recoveryNoMeds => 'Aucun médicament aujourd\'hui.';

  @override
  String get recoveryDoseTake => 'Pris';

  @override
  String get recoveryDoseSkip => 'Pas pris';

  @override
  String get recoveryDoseTaken => 'Pris';

  @override
  String get recoveryDoseSkipped => 'Non pris';

  @override
  String get recoveryNextAppt => 'Votre prochain rendez-vous';

  @override
  String get clinicTitle => 'Votre cabinet';

  @override
  String get clinicOpenToday => 'Ouvert aujourd\'hui';

  @override
  String get clinicClosedToday => 'Fermé aujourd\'hui';

  @override
  String get clinicHoursToday => 'Horaires aujourd\'hui';

  @override
  String get clinicMaps => 'Ouvrir dans Google Maps';

  @override
  String get clinicCall => 'Appeler le cabinet';

  @override
  String clinicCallNumber(String phone) {
    return 'Appeler le $phone';
  }

  @override
  String get companionTitle => 'Compagnon';

  @override
  String get companionSubtitle => 'Assistant IA, pas un médecin';

  @override
  String get companionIntroTitle => 'Avant de commencer';

  @override
  String get companionIntroAi =>
      'Je suis un assistant IA qui vous écoute entre les rendez-vous. Je ne suis pas médecin.';

  @override
  String get companionIntroNoDiagnosis =>
      'Je ne pose pas de diagnostic et ne modifie pas votre traitement. Votre médecin reste votre référent.';

  @override
  String get companionIntroPrivacy =>
      'Votre médecin ne voit que les messages signalés pour votre sécurité, et un court résumé si vous l\'acceptez.';

  @override
  String get companionIntroAgree => 'J\'ai compris, commencer';

  @override
  String get companionGreeting =>
      'Bonjour, je suis le Compagnon. Je suis là pour vous écouter. Comment vous sentez-vous en ce moment ?';

  @override
  String get companionHint => 'Écrivez votre message…';

  @override
  String get companionSend => 'Envoyer';

  @override
  String get companionTyping => 'Le Compagnon écrit…';

  @override
  String get companionDisclaimer =>
      'Le Compagnon ne pose pas de diagnostic et ne modifie pas votre traitement.';

  @override
  String get companionUrgent => 'Aide urgente';

  @override
  String get companionQuickCraving => 'J\'ai une forte envie';

  @override
  String get companionQuickBreath => 'Exercice de respiration';

  @override
  String get companionQuickDoctor => 'Je veux parler au médecin';

  @override
  String get companionBook => 'Prendre rendez-vous';

  @override
  String get crisisTitle => 'Vous n\'êtes pas seul(e)';

  @override
  String get crisisBody =>
      'Si vous êtes en danger ou pensez à vous faire du mal, appelez maintenant.';

  @override
  String get crisisEmergency =>
      'Numéros d\'urgence : [à confirmer par le cabinet]';

  @override
  String get crisisClose => 'Fermer';

  @override
  String addictionType(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'opioids': 'Opioïdes',
      'cannabis': 'Cannabis',
      'alcohol': 'Alcool',
      'tobacco': 'Tabac',
      'pills': 'Psychotropes (comprimés)',
      'stimulants': 'Stimulants',
      'gambling': 'Jeux d\'argent',
      'other': 'Autre',
    });
    return '$_temp0';
  }

  @override
  String recoveryCleanSince(String date) {
    return 'Sans consommation depuis le $date';
  }

  @override
  String get checkInTitle => 'Cette semaine';

  @override
  String checkInCount(int count) {
    return '$count sur 7';
  }

  @override
  String get checkInAction => 'Journée sans consommation';

  @override
  String get checkInDone => 'Journée enregistrée. Bravo.';

  @override
  String checkInDayDone(String day) {
    return '$day : validé';
  }

  @override
  String checkInDayOpen(String day) {
    return '$day : non validé';
  }

  @override
  String get checkInReminder => 'Rappel quotidien';

  @override
  String get checkInReminderOff => 'Désactivé';

  @override
  String get checkInReminderPick => 'Choisir l\'heure du rappel';

  @override
  String get checkInReminderStop => 'Désactiver le rappel';

  @override
  String get relapseWhen => 'Quand est-ce arrivé ?';

  @override
  String get relapseToday => 'Aujourd\'hui';

  @override
  String get relapseYesterday => 'Hier';

  @override
  String get relapseTime => 'Heure';

  @override
  String get addictionFormTitle => 'De quoi vous rétablissez-vous ?';

  @override
  String get addictionFormBody =>
      'Choisissez le type et la date de votre dernière consommation. Votre médecin vérifiera ces informations.';

  @override
  String get addictionTypeLabel => 'Type';

  @override
  String get addictionSubstance => 'Produit précis (facultatif)';

  @override
  String get addictionSubstanceHint => 'Ex. : nom du médicament ou du produit';

  @override
  String get addictionCleanSince => 'Sans consommation depuis le';

  @override
  String get addictionPickDate => 'Choisir la date';

  @override
  String get addictionSave => 'Enregistrer';

  @override
  String get addictionAdd => 'Ajouter ce dont je me rétablis';

  @override
  String get addictionAddAnother => 'Ajouter une autre addiction';

  @override
  String get addictionEmpty =>
      'Ajoutez ce dont vous vous rétablissez pour lancer votre compteur.';

  @override
  String get addictionPending => 'En attente de validation du médecin';

  @override
  String get addictionSaved => 'Enregistré. Votre médecin va le vérifier.';

  @override
  String get recoverySaveError =>
      'Enregistrement impossible. Vérifiez la connexion et réessayez.';

  @override
  String get profileDocNationalId => 'Carte d\'identité algérienne';

  @override
  String get profileDocPassport => 'Passeport algérien';

  @override
  String get profileScanPassport => 'Scanner mon passeport';

  @override
  String get profilePassportNumber => 'Numéro de passeport';

  @override
  String get scanPlaceCard => 'Placez la carte dans le cadre';

  @override
  String get scanPlacePassport =>
      'Placez la page photo dans le cadre, avec les deux lignes du bas';

  @override
  String get scanHold => 'Ne bougez plus…';

  @override
  String get scanSlow =>
      'Lecture difficile. Essayez avec plus de lumière, ou saisissez les informations vous-même.';

  @override
  String get scanPrivacy =>
      'Le document est lu sur votre téléphone ; aucune photo n\'est enregistrée.';

  @override
  String get scanTorchOn => 'Allumer la lampe';

  @override
  String get scanTorchOff => 'Éteindre la lampe';

  @override
  String get scanTypeInstead => 'Saisir moi-même';

  @override
  String get cameraClose => 'Fermer';

  @override
  String get cameraDenied =>
      'Caméra indisponible. Autorisez-la dans les réglages du téléphone, ou saisissez les informations vous-même.';

  @override
  String get cameraRetry => 'Réessayer';

  @override
  String get selfieCamTitle => 'Votre selfie';

  @override
  String get selfieNoFace => 'Regardez la caméra';

  @override
  String get selfieOneFace => 'Un seul visage, s\'il vous plaît';

  @override
  String get selfieCloser => 'Approchez-vous un peu';

  @override
  String get selfieCenter => 'Placez votre visage au centre';

  @override
  String get selfieReady => 'Parfait, prenez la photo';

  @override
  String get selfieTake => 'Prendre la photo';

  @override
  String get selfieCheck => 'La photo est-elle nette ?';

  @override
  String get selfieUse => 'Utiliser cette photo';

  @override
  String get selfieCamPrivacy =>
      'La photo est envoyée chiffrée, à votre médecin seulement.';

  @override
  String get scanNotAlgerian => 'Seul le passeport algérien est accepté.';

  @override
  String get substanceLabel => 'Substance';

  @override
  String get substanceOther => 'Autre substance';

  @override
  String get recoveryLockedTitle => 'S\'ouvre après votre premier rendez-vous';

  @override
  String get recoveryLockedBody =>
      'Le suivi s\'ouvre une fois votre premier rendez-vous confirmé et payé.';

  @override
  String get recoveryLockedBook => 'Prendre rendez-vous';

  @override
  String get dailyCheckAction => 'Faire le point du jour';

  @override
  String get dailyCheckTitle => 'Comment s\'est passée votre journée ?';

  @override
  String dailyCheckWithout(String substance) {
    return 'Aujourd\'hui sans $substance ?';
  }

  @override
  String get dailyCheckYes => 'Oui';

  @override
  String get dailyCheckNo => 'Non';

  @override
  String get dailyCheckCraving => 'Envie de consommer';

  @override
  String get ratingLow => 'Faible';

  @override
  String get ratingHigh => 'Fort';

  @override
  String ratingValue(String label, int value) {
    return '$label : $value sur 5';
  }

  @override
  String get dailyCheckNeedAnswers =>
      'Répondez à toutes les questions pour enregistrer.';

  @override
  String get habitsTitle => 'Mes bonnes habitudes';

  @override
  String get habitsEmpty =>
      'Choisissez une bonne habitude pour remplacer la consommation.';

  @override
  String get habitsAdd => 'Ajouter une habitude';

  @override
  String get habitsOwn => 'Avec mes mots';

  @override
  String get habitsOwnHint => 'Ex. : jardiner';

  @override
  String get habitsReminder => 'Rappel quotidien';

  @override
  String habitsRemove(String habit) {
    return 'Retirer $habit';
  }

  @override
  String habitsDone(String habit) {
    return '$habit : fait aujourd\'hui';
  }

  @override
  String habitsOpen(String habit) {
    return '$habit : pas encore fait';
  }

  @override
  String get habitsMax => 'Vous pouvez garder 5 habitudes au maximum.';

  @override
  String get goalTitle => 'Votre prochain petit objectif';

  @override
  String get goalChange => 'Changer l\'objectif';

  @override
  String get goalAuto => 'Automatique';

  @override
  String get reminderTitle => 'Rappel';

  @override
  String reminderTomorrow(String time) {
    return 'Votre rendez-vous est demain à $time.';
  }

  @override
  String reminderSoon(String time) {
    return 'Votre rendez-vous est dans une heure, à $time.';
  }

  @override
  String get apptReceipt => 'Voir le reçu';

  @override
  String get receiptTitle => 'Reçu de paiement';

  @override
  String get receiptNumber => 'N° de reçu';

  @override
  String get receiptDoctor => 'Médecin';

  @override
  String get receiptVisit => 'Rendez-vous';

  @override
  String get receiptPaidOn => 'Payé le';

  @override
  String get receiptRef => 'Référence du paiement';

  @override
  String get receiptNote => 'Reçu de paiement, pas une facture.';

  @override
  String get receiptCopy => 'Copier le reçu';

  @override
  String get receiptCopied => 'Reçu copié';

  @override
  String get receiptNotPaid => 'Ce rendez-vous n\'est pas encore payé.';

  @override
  String get reminderDailyCheck => 'C\'est l\'heure de votre rappel du jour.';

  @override
  String reminderHabit(String habit) {
    return 'C\'est l\'heure : $habit';
  }

  @override
  String get reminderHabitOwn => 'C\'est l\'heure de votre habitude.';

  @override
  String get articlesTitle => 'Articles';

  @override
  String get articlesAll => 'Tous';

  @override
  String get articlesSaved => 'Enregistrés';

  @override
  String get articlesNone => 'Pas encore d\'article dans cette rubrique.';

  @override
  String get articlesNoneSaved =>
      'Aucun article enregistré. Touchez le marque-page dans un article pour le garder.';

  @override
  String get articleSave => 'Enregistrer l\'article';

  @override
  String get articleUnsave => 'Retirer des enregistrés';

  @override
  String get articleSavedLabel => 'Enregistré';

  @override
  String get articleSaveFailed => 'Enregistrement impossible. Réessayez.';

  @override
  String get articleTopicAddiction => 'Comprendre l\'addiction';

  @override
  String get articleTopicCravings => 'Envies et déclencheurs';

  @override
  String get articleTopicRelapse => 'Prévenir la rechute';

  @override
  String get articleTopicMedication => 'Médicaments';

  @override
  String get articleTopicFamily => 'Famille et soutien';

  @override
  String get articleTopicMotivation => 'Motivation';

  @override
  String get milestoneTitle => 'Bravo !';

  @override
  String milestoneBody(int days, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days jours',
      one: 'Une journée entière',
    );
    return '$_temp0 sans $name. C\'est un vrai pas, continuez.';
  }

  @override
  String get milestoneBadges => 'Vos badges de cette série';

  @override
  String get milestoneContinue => 'Continuer';
}
