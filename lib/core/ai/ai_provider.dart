/// The LLM services the assistant can send a transcript to.
///
/// Persisted by `name`, never by `index`, for the same reason as `AppPalette`:
/// adding a provider in the middle of this list must not silently switch
/// anyone's saved choice.
enum AiProvider { anthropic, openai, gemini, deepseek }

extension AiProviderX on AiProvider {
  String get label => switch (this) {
    AiProvider.anthropic => 'Claude',
    AiProvider.openai => 'OpenAI',
    AiProvider.gemini => 'Gemini',
    AiProvider.deepseek => 'DeepSeek',
  };

  /// The model used when the user leaves the model field blank. All four are
  /// editable in Settings, so a renamed model is a one-line fix for the user
  /// rather than an app update.
  String get defaultModel => switch (this) {
    AiProvider.anthropic => 'claude-sonnet-5',
    AiProvider.openai => 'gpt-6-astra',
    AiProvider.gemini => 'gemini-3.8-flash',
    AiProvider.deepseek => 'deepseek-v4-flash',
  };

  /// Pre-defined models for each provider to show in a dropdown.
  List<String> get availableModels => switch (this) {
    AiProvider.anthropic => [
      'claude-fable-5.1', 'claude-opus-5', 'claude-sonnet-5', 'claude-haiku-4.5',
      'claude-3-7-sonnet-20250219', 'claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022'
    ],
    AiProvider.openai => [
      'gpt-6-astra', 'gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna',
      'gpt-4.1-mini', 'gpt-4o', 'gpt-4o-mini', 'o3-mini', 'o1', 'o1-mini'
    ],
    AiProvider.gemini => [
      'gemini-3.8-flash', 'gemini-3.6-flash', 'gemini-3.1-pro',
      'gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.0-flash', 'gemini-1.5-pro'
    ],
    AiProvider.deepseek => [
      'deepseek-v4-pro', 'deepseek-v4-flash', 'deepseek-v4-flash-vision-exp',
      'deepseek-chat', 'deepseek-reasoner'
    ],
  };

  /// The shape of the key, shown as the field hint so a pasted key from the
  /// wrong console is obvious before the first failed request.
  String get keyHint => switch (this) {
    AiProvider.anthropic => 'sk-ant-…',
    AiProvider.openai => 'sk-…',
    AiProvider.gemini => 'AIza…',
    AiProvider.deepseek => 'sk-…',
  };

  String get consoleUrl => switch (this) {
    AiProvider.anthropic => 'console.anthropic.com',
    AiProvider.openai => 'platform.openai.com',
    AiProvider.gemini => 'aistudio.google.com',
    AiProvider.deepseek => 'platform.deepseek.com',
  };

  /// Resolves a saved preference, falling back to the default rather than
  /// throwing on a name this build does not know.
  static AiProvider byName(String? name) =>
      AiProvider.values.where((p) => p.name == name).firstOrNull ??
      AiProvider.anthropic;
}
