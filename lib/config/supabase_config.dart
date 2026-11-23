/// Supabase project settings.
///
/// Both values are in the Supabase Dashboard: click **Connect** at the top of
/// the project (or Project Settings > API Keys). The publishable key (also
/// called the anon key) is meant to be inside apps; the data is protected by
/// the Row Level Security rules in supabase/002_mobile_access.sql.
/// Never put the secret / service_role key here.
class SupabaseConfig {
  /// For example https://abcdefghijklmnop.supabase.co
  static const url = 'https://kvclcgtktbbxceaxbyzz.supabase.co';

  /// Starts with sb_publishable_ (or eyJ for the older anon key).
  static const publishableKey = 'sb_publishable_WaDLK6dCcpT_I706jGOngQ_sLgdz3JF';

  static bool get isConfigured =>
      url.startsWith('https://') && !publishableKey.startsWith('PASTE_');
}
