import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication via Supabase Auth (email/password).
/// Profile rows are created automatically by the `on_auth_user_created`
/// trigger (migration 0002).
class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );
  }

  Future<void> resendConfirmation({required String email}) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
    );
  }

  Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() => _client.auth.signOut();
}