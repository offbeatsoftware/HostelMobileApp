/// Supabase project settings.
///
/// Both values are in the Supabase Dashboard: click **Connect** at the top of
/// the project (or Project Settings > API Keys). The publishable key (also
/// called the anon key) is meant to be inside apps; the data is protected by
/// the Row Level Security rules in supabase/002_mobile_access.sql.
/// Never put the secret / service_role key here.
class SupabaseConfig {
  /// For example https://abcdefghijklmnop.supabase.co
  static const url = 'PASTE_SUPABASE_PROJECT_URL_HERE';

  /// Starts with sb_publishable_ (or eyJ for the older anon key).
  static const publishableKey = 'PASTE_SUPABASE_PUBLISHABLE_KEY_HERE';

  static bool get isConfigured =>
      url.startsWith('https://') && !publishableKey.startsWith('PASTE_');
}
