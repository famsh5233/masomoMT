/// App text in Swahili and English. Swahili speakers get a Swahili interface;
/// everyone else gets English. Lesson content itself comes from the server.
class S {
  const S(this.lang);

  final String lang;

  bool get sw => lang == 'sw';
  String _t(String swText, String enText) => sw ? swText : enText;

  // Onboarding
  String get welcomeTitle => _t('Ongea Kiingereza kwa kujiamini', 'Speak English with confidence');
  String get welcomeBody => _t(
    'Fanya mazoezi ya kuongea na Mwalimu, mwalimu wa AI anayekusahihisha na kukueleza kwa Kiswahili.',
    'Practise speaking with Mwalimu, an AI teacher who corrects you and explains in your language.',
  );
  String get country => _t('Nchi', 'Country');
  String get phoneLabel => _t('Namba ya simu', 'Phone number');
  String get phoneHint => '07XX XXX XXX';
  String get sendCode => _t('Tuma namba ya uthibitisho', 'Send code');
  String codeSentTo(String phone) => _t('Tumetuma namba kwa SMS kwenda +$phone', 'We sent a code by SMS to +$phone');
  String get codeLabel => _t('Namba ya uthibitisho (tarakimu 6)', '6-digit code');
  String get verify => _t('Thibitisha', 'Verify');
  String get resend => _t('Tuma tena', 'Send again');
  String get changeNumber => _t('Badilisha namba', 'Change number');
  String get switchLanguage => _t('English', 'Kiswahili');
  String get setupTitle => _t('Tukufahamu', 'About you');
  String get yourName => _t('Jina lako', 'Your name');
  String get nameRequired => _t('Andika jina lako', 'Enter your name');
  String get nativeLanguage => _t('Lugha yako ya kwanza', 'Your first language');
  String get yourLevel => _t('Kiwango chako cha Kiingereza', 'Your English level');
  String levelLabel(String level) => switch (level) {
    'A1' => _t('Naanza kabisa', 'Complete beginner'),
    'A2' => _t('Najua maneno machache', 'I know some words'),
    'B1' => _t('Naelewa, lakini kuongea ni kugumu', 'I understand, but speaking is hard'),
    'B2' => _t('Naongea vizuri kiasi', 'I speak fairly well'),
    'C1' => _t('Naongea vizuri sana', 'I speak very well'),
    _ => level,
  };
  String get continueLabel => _t('Endelea', 'Continue');
  String get save => _t('Hifadhi', 'Save');

  // Navigation
  String get tabSpeak => _t('Ongea', 'Speak');
  String get tabLessons => _t('Masomo', 'Lessons');
  String get tabVideos => _t('Video', 'Videos');
  String get tabAccount => _t('Akaunti', 'Account');

  // Tutor
  String scenario(String code) => switch (code) {
    'free_talk' => _t('Mazungumzo', 'Free talk'),
    'job_interview' => _t('Usaili wa kazi', 'Job interview'),
    'customer_service' => _t('Kuhudumia mteja', 'Serving customers'),
    'tourism' => _t('Utalii', 'Tourism'),
    'phone_call' => _t('Simu ya kazi', 'Phone call'),
    'small_business' => _t('Kuuza biashara', 'Selling'),
    _ => code,
  };
  String get tutorIntro => _t(
    'Habari! Mimi ni Mwalimu. Bonyeza kipaza sauti uongee kwa Kiingereza, au andika. Nitakusahihisha.',
    "Hi! I'm Mwalimu. Tap the mic and speak English, or type. I'll correct you as we talk.",
  );
  String get tapToSpeak => _t('Bonyeza uongee', 'Tap to speak');
  String get listening => _t('Nakusikiliza... bonyeza kumaliza', 'Listening... tap to finish');
  String get typeHint => _t('Au andika kwa Kiingereza', 'Or type in English');
  String get send => _t('Tuma', 'Send');
  String turnsLeft(int n) => _t('Mazungumzo $n yamebaki leo', '$n turns left today');
  String get betterWay => _t('Njia bora ya kusema', 'A better way to say it');
  String get score => _t('Alama', 'Score');
  String get listen => _t('Sikiliza', 'Listen');
  String get limitTitle => _t('Umemaliza mazungumzo ya leo', "You've used today's turns");
  String get limitBody => _t(
    'Jiunge na Pro upate hadi mazungumzo 40 kila siku na masomo yote.',
    'Go Pro for up to 40 turns a day and every lesson.',
  );
  String get limitBodyPro => _t('Rudi kesho kwa mazungumzo mapya.', 'Come back tomorrow for more practice.');
  String get micDenied => _t('Ruhusu kipaza sauti ili uongee.', 'Allow the microphone so you can speak.');
  String get speechUnavailable => _t(
    'Kutambua sauti hakupatikani kwenye kifaa hiki. Andika badala yake.',
    "Speech recognition isn't available on this device. Please type instead.",
  );
  String get didNotHear => _t('Sikukusikia vizuri. Jaribu tena.', "I didn't catch that. Try again.");

  // Pro / paywall
  String get goPro => _t('Jiunge na Pro', 'Go Pro');
  String get proTitle => 'Masomo Pro';
  String get proBenefit1 => _t('Hadi mazungumzo 40 na Mwalimu kila siku', 'Up to 40 turns with Mwalimu every day');
  String get proBenefit2 => _t('Masomo yote ya wiki 12', 'All 12 weeks of lessons');
  String get proBenefit3 => _t('Video zote za masomo', 'Every video lesson');
  String get choosePlan => _t('Chagua mpango', 'Choose a plan');
  String get chooseNetwork => _t('Chagua mtandao', 'Choose your network');
  String get payingNumber => _t('Namba itakayolipa', 'Number to pay from');
  String pay(String amount) => _t('Lipa $amount', 'Pay $amount');
  String get checkPhone =>
      _t('Angalia simu yako na uweke PIN kuthibitisha malipo.', 'Check your phone and enter your PIN to confirm.');
  String get waiting => _t('Tunasubiri uthibitisho...', 'Waiting for confirmation...');
  String get paySuccess => _t('Hongera! Pro imewashwa.', 'Done! Pro is now active.');
  String get payFailed => _t('Malipo hayakukamilika. Jaribu tena.', "The payment didn't go through. Please try again.");
  String get payTimeout => _t(
    'Hatujapokea uthibitisho bado. Kama pesa imekatwa, wasiliana na msaada.',
    'No confirmation yet. If money was taken, please contact support.',
  );
  String get payWithPlay => _t('Lipa kupitia Google Play', 'Pay with Google Play');
  String get done => _t('Sawa', 'Done');
  String get close => _t('Funga', 'Close');
  String planLabel(int days) => switch (days) {
    7 => _t('Wiki 1', '1 week'),
    30 => _t('Mwezi 1', '1 month'),
    90 => _t('Miezi 3', '3 months'),
    365 => _t('Mwaka 1', '1 year'),
    _ => _t('Siku $days', '$days days'),
  };
  String get bestValue => _t('Nafuu zaidi', 'Best value');
  String get mobileMoneyOnlyTz => _t(
    'Malipo kwa simu yanapatikana Tanzania tu kwa sasa.',
    'Mobile money payment is available in Tanzania only for now.',
  );

  // Lessons
  String week(int n) => _t('Wiki $n', 'Week $n');
  String get comingSoon => _t('Inakuja hivi karibuni', 'Coming soon');
  String get objectives => _t('Utakachojifunza', "What you'll learn");
  String get vocabulary => _t('Msamiati', 'Vocabulary');
  String get phrases => _t('Sentensi muhimu', 'Useful phrases');
  String get dialogue => _t('Mazungumzo ya mfano', 'Example conversation');
  String get grammar => _t('Sarufi', 'Grammar');
  String get speakingTasks => _t('Mazoezi ya kuongea', 'Speaking practice');
  String get practiseWithMwalimu => _t('Fanya mazoezi na Mwalimu', 'Practise with Mwalimu');
  String get quiz => _t('Jaribio', 'Quiz');
  String get checkAnswers => _t('Angalia majibu', 'Check answers');
  String quizScore(int a, int b) => _t('Umepata $a kati ya $b', 'You scored $a out of $b');
  String get answerAll => _t('Jibu maswali yote kwanza', 'Answer every question first');

  // Videos
  String get videosUnavailable => _t('Video hazipatikani kwa sasa.', 'Videos are unavailable right now.');
  String get noVideos => _t('Hakuna video kwa wiki hii bado.', 'No videos for this week yet.');

  // Account
  String proUntil(String date) => _t('Pro hadi $date', 'Pro until $date');
  String get freePlan => _t('Mpango wa bure', 'Free plan');
  String get editProfile => _t('Badilisha taarifa', 'Edit profile');
  String get help => _t('Msaada', 'Help');
  String get privacy => _t('Sera ya faragha', 'Privacy policy');
  String get logout => _t('Toka', 'Log out');
  String get level => _t('Kiwango', 'Level');

  // Support
  String get supportIntro => _t(
    'Habari! Tuandikie swali lako kuhusu app, malipo au masomo.',
    'Hi! Ask us anything about the app, payments or lessons.',
  );
  String get supportHint => _t('Andika swali lako', 'Write your question');
  String get escalated => _t(
    'Tumepokea. Mtu wa timu yetu atakujibu hivi karibuni.',
    'Got it. Someone from our team will get back to you soon.',
  );

  // Errors
  String get network => _t('Hakuna mtandao. Angalia intaneti yako.', 'No connection. Check your internet.');
  String get generic => _t('Kuna tatizo. Jaribu tena.', 'Something went wrong. Please try again.');
  String get retry => _t('Jaribu tena', 'Try again');
  String get badPhone => _t('Andika namba sahihi ya simu', 'Enter a valid phone number');
  String get sessionExpired => _t('Tafadhali ingia tena.', 'Please sign in again.');
}
