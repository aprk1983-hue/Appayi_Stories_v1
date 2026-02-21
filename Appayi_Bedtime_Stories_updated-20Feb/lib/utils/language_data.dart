// lib/utils/language_data.dart
import 'package:flutter/foundation.dart' show immutable;

@immutable
class LanguageData {
  // Helper to get full language name from code
  static String getLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'hi':
        return 'हिन्दी (Hindi)';
      case 'ta':
        return 'தமிழ் (Tamil)';
      //case 'ml':
        //return 'മലയാളം (Malayalam)';
      //case 'te':
        //return 'తెలుగు (Telugu)';
      //case 'kn':
        //return 'ಕನ್ನಡ (Kannada)';
      default:
        return code;
    }
  }

  /// Master list of all categories by language.
  static const Map<String, List<Map<String, String>>> categoriesByLang = {
    'en': [
      //{'label': 'Bedtime Stories', 'key': 'Bedtime'},
      {'label': 'Folk Tales/Fables', 'key': 'Folk Tales/Fables'},
      {'label': 'Adventures', 'key': 'Adventure'},
      //{'label': 'Science & Environmental', 'key': 'Science & Environmental Studies'},
      {'label': 'Moral Stories', 'key': 'Moral'},
      //{'label': 'Animal Stories', 'key': 'Animals'},
      {'label': 'Fairy Tales', 'key': 'Fairy Tales'},
      {'label': 'Fantasy', 'key': 'Fantasy'},
      //{'label': 'Realistic', 'key': 'Realistic'},
      //{'label': 'Forest', 'key': 'Forest'},
    ],
    'hi': [
      //{'label': 'सोने के समय की कहानियाँ', 'key': 'Bedtime'},
      {'label': 'लोक कथाएं/दंतकथाएं', 'key': 'Folk Tales/Fables'},
      {'label': 'साहसिक', 'key': 'Adventure'},
      //{'label': 'विज्ञान और पर्यावरण', 'key': 'Science & Environmental Studies'},
      {'label': 'नैतिक', 'key': 'Moral'},
      //{'label': 'जानवरों की कहानियां', 'key': 'Animals'},
      {'label': 'परियों की कहानियां', 'key': 'Fairy Tales'},
      {'label': 'काल्पनिक', 'key': 'Fantasy'},
      //{'label': 'यथार्थवादी', 'key': 'Realistic'},
      //{'label': 'जंगल', 'key': 'Forest'},
    ],
    'ta': [
      {'label': 'படுக்கை நேரக் கதைகள்', 'key': 'Bedtime'},
      {'label': 'நாட்டுப்புறக் கதைகள்', 'key': 'Folk Tales/Fables'},
      {'label': 'சாகசங்கள்', 'key': 'Adventure'},
      //{'label': 'அறிவியல் & சுற்றுச்சூழல்', 'key': 'Science & Environmental Studies'},
      {'label': 'நீதிக் கதைகள்', 'key': 'Moral'},
      //{'label': 'விலங்கு கதைகள்', 'key': 'Animals'},
      {'label': 'தேவதை கதைகள்', 'key': 'Fairy Tales'},
      {'label': 'கற்பனை', 'key': 'Fantasy'},
      //{'label': 'யதார்த்தமான', 'key': 'Realistic'},
      //{'label': 'காடு', 'key': 'Forest'},
    ],
    //'ml': [
    //  {'label': 'ഉറക്കസമയം കഥകൾ', 'key': 'Bedtime'},
      //{'label': 'നാടോടിക്കഥകൾ', 'key': 'Folk Tales/Fables'},
      //{'label': 'സാഹസികത', 'key': 'Adventure'},
      //{'label': 'ശാസ്ത്രം & പരിസ്ഥിതി', 'key': 'Science & Environmental Studies'},
      //{'label': 'ധാർമിക കഥകൾ', 'key': 'Moral'},
      //{'label': 'മൃഗ കഥകൾ', 'key': 'Animals'},
      //{'label': 'മാലാഖ കഥകൾ', 'key': 'Fairy Tales'},
      //{'label': 'ഫാന്റസി', 'key': 'Fantasy'},
      //{'label': 'യാഥാർത്ഥ്യ കഥകൾ', 'key': 'Realistic'},
      //{'label': 'കാട്', 'key': 'Forest'},
    //],
    //'te': [
      //{'label': 'నిద్రవేళ కథలు', 'key': 'Bedtime'},
      //{'label': 'జానపద కథలు', 'key': 'Folk Tales/Fables'},
      //{'label': 'సాహసాలు', 'key': 'Adventure'},
      //{'label': 'సైన్స్ & పర్యావరణం', 'key': 'Science & Environmental Studies'},
      //{'label': 'నీతి కథలు', 'key': 'Moral'},
      //{'label': 'జంతువుల కథలు', 'key': 'Animals'},
      //{'label': 'అద్భుత కథలు', 'key': 'Fairy Tales'},
      //{'label': 'ఫాంటసీ', 'key': 'Fantasy'},
      //{'label': 'వాస్తవిక కథలు', 'key': 'Realistic'},
      //{'label': 'అడవి', 'key': 'Forest'},
    //],
    //'kn': [
      //{'label': 'ಮಲಗುವ ಸಮಯದ ಕಥೆಗಳು', 'key': 'Bedtime'},
      //{'label': 'ಜಾನಪದ ಕಥೆಗಳು', 'key': 'Folk Tales/Fables'},
      //{'label': 'ಸಾಹಸಗಳು', 'key': 'Adventure'},
      //{'label': 'ವಿಜ್ಞಾನ ಮತ್ತು ಪರಿಸರ', 'key': 'Science & Environmental Studies'},
      //{'label': 'ನೈತಿಕ ಕಥೆಗಳು', 'key': 'Moral'},
      //{'label': 'ಪ್ರಾಣಿ ಕಥೆಗಳು', 'key': 'Animals'},
      //{'label': 'ಅದ್ಭುತ ಕಥೆಗಳು', 'key': 'Fairy Tales'},
      //{'label': 'ಫ್ಯಾಂಟಸಿ', 'key': 'Fantasy'},
      //{'label': 'ವಾಸ್ತವಿಕ', 'key': 'Realistic'},
      //{'label': 'ಕಾಡು', 'key': 'Forest'},
    //],
  };
}