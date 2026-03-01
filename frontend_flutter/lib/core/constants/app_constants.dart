class AppConstants {
  static const String defaultCountry = 'Bangladesh';
  static const String backendBaseUrlAndroid = 'http://192.168.1.2:4000';
  static const String backendBaseUrlIOS = 'http://localhost:4000';
  static const String backendBaseUrlOverride = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: '',
  );
}
