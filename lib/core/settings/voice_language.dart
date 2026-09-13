/// Which recogniser the assistant's microphone runs.
///
/// On-device recognition needs one fixed locale per session; neither
/// platform detects the spoken language from the audio. "Auto" therefore
/// means the device language, which is right for most phones, and the two
/// explicit choices cover a Bangla speaker on an English phone and vice
/// versa. Persisted by `name`, never by index.
enum VoiceLanguage { auto, english, bangla }

extension VoiceLanguageX on VoiceLanguage {
  String get label => switch (this) {
    VoiceLanguage.auto => 'Auto',
    VoiceLanguage.english => 'English',
    VoiceLanguage.bangla => 'বাংলা',
  };

  String get description => switch (this) {
    VoiceLanguage.auto => 'Auto · device language',
    VoiceLanguage.english => 'English',
    VoiceLanguage.bangla => 'বাংলা (Bangla)',
  };

  /// The BCP-47 language the recogniser should run, or null for the device
  /// default.
  String? get languageCode => switch (this) {
    VoiceLanguage.auto => null,
    VoiceLanguage.english => 'en',
    VoiceLanguage.bangla => 'bn',
  };

  static VoiceLanguage byName(String? name) =>
      VoiceLanguage.values.where((v) => v.name == name).firstOrNull ??
      VoiceLanguage.auto;
}
