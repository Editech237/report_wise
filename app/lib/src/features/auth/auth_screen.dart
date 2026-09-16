import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/auth_widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _needsConfirmation = false;
  bool _canResend = true;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _needsConfirmation = false;
    });
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) {
      setState(() => _error = 'Auth not configured');
      setState(() => _busy = false);
      return;
    }
    try {
      if (_signUp) {
        final response = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          fullName: _fullName.text.trim(),
        );
        if (!mounted) return;
        if (response.user != null && response.session == null) {
          setState(() {
            _needsConfirmation = true;
            _error =
                'Account created for ${response.user!.email ?? _email.text.trim()}. Check your inbox for a confirmation link, then sign in. If you do not see it, check spam or tap Resend.';
          });
          return;
        }
        if (response.session != null) return;
        setState(() {
          _needsConfirmation = true;
          _error =
              'Account created. Check your inbox for a confirmation link, then sign in.';
        });
      } else {
        await auth.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      final code = (e.code ?? '').toLowerCase();
      debugPrint(
        'AuthException code=$code message=${e.message} statusCode=${e.statusCode}',
      );
      String friendly = e.message;
      bool needsConfirm = false;

      if (msg.contains('email not confirmed') ||
          msg.contains('email_not_confirmed') ||
          code.contains('email_not_confirmed')) {
        friendly =
            'Email not confirmed. Check your inbox for the confirmation link we sent to ${_email.text.trim()}.';
        needsConfirm = true;
      } else if (msg.contains('invalid login credentials') ||
          msg.contains('invalid credentials') ||
          code.contains('invalid_credentials')) {
        friendly =
            'Invalid email or password. If you just registered, confirm your email first (check inbox/spam). Otherwise verify your password.';

        needsConfirm = true;
      } else if (msg.contains('user already registered') ||
          msg.contains('already exists')) {
        friendly =
            'An account with this email already exists. Try signing in instead.';
      } else if (msg.contains('password should be at least 6')) {
        friendly = 'Password must be at least 6 characters.';
      }

      setState(() {
        _error = friendly;
        _needsConfirmation = needsConfirm;
      });
    } catch (e) {
      if (mounted)
        setState(() => _error = 'Something went wrong. Please try again. ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email first to resend confirmation.');
      return;
    }
    setState(() => _busy = true);
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) {
      setState(() => _error = 'Auth not configured');
      setState(() => _busy = false);
      return;
    }
    try {
      await auth.resendConfirmation(email: _email.text.trim());
      if (mounted) {
        setState(() {
          _canResend = false;
          _error =
              'Confirmation email resent to ${_email.text.trim()}. Check inbox and spam.';
          _needsConfirmation = true;
        });
        // Re-enable after 30s
        Future.delayed(const Duration(seconds: 30), () {
          if (mounted) setState(() => _canResend = true);
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not resend. Try again. ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'you@school.cm',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, emailController.text.trim()),
            child: const Text('Send reset link'),
          ),
        ],
      ),
    );
    emailController.dispose();
    if (email == null || email.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      await auth.resetPassword(email: email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Reset link sent to $email. Check your inbox (and spam) to set a new password.';
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not send the reset link. Try again.';
      });
    }
  }

  void _toggleMode() {
    setState(() {
      _signUp = !_signUp;
      _error = null;
    });
    // subtle re-animate on toggle
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: isCompact ? _buildCompactLayout() : _buildWideLayout(),
    );
  }

  Widget _buildWideLayout() {
    final size = MediaQuery.of(context).size;
    return Row(
      children: [
        Expanded(
          flex: size.width > 1600 ? 2 : 1,
          child: Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(0, (1 - v) * 20),
                          child: child,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Illustration with subtle shadow container
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 32,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                'assets/images/auth_illustration.png',
                                fit: BoxFit.contain,
                                height: 380,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 320,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: const Icon(
                                    Icons.school_rounded,
                                    size: 96,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Correct School,\nCorrect Future.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Cameroon Secondary School\nManagement Platform',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.75),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildFeatureRow(),
                const SizedBox(height: 32),
                Text(
                  'REPORTWISE ©2026',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 9,
                    color: Colors.white.withOpacity(0.45),
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right — form panel
        Expanded(
          flex: 1,
          child: Container(
            color: AppColors.background,
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width < 1300 ? 40 : 72,
                  vertical: 48,
                ),
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AuthHeaderSection(
                            title: _signUp
                                ? 'Create your account'
                                : 'Welcome Back',
                            subtitle: _signUp
                                ? 'Join hundreds of Cameroonian secondary schools managing academics with ReportWise.'
                                : 'Please enter your credentials to access your dashboard.',
                          ),
                          const SizedBox(height: 32),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.04),
                                  end: Offset.zero,
                                ).animate(anim),
                                child: child,
                              ),
                            ),
                            child: Column(
                              key: ValueKey(_signUp),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_signUp) ...[
                                  const AuthSectionTitle(
                                    icon: Icons.person_outline,
                                    title: 'PERSONAL IDENTITY',
                                  ),
                                  const SizedBox(height: 12),
                                  AuthTextField(
                                    label: "FULL NAME",
                                    hint: "e.g. Prof. Jean-Marc Mbarga",
                                    icon: Icons.badge_outlined,
                                    controller: _fullName,
                                    textInputAction: TextInputAction.next,
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                        ? 'Full name is required'
                                        : null,
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                const AuthSectionTitle(
                                  icon: Icons.lock_outline,
                                  title: 'ACCOUNT CREDENTIALS',
                                ),
                                const SizedBox(height: 12),
                                AuthTextField(
                                  label: "EMAIL ADDRESS",
                                  hint: "you@school.cm",
                                  icon: Icons.mail_outline,
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    if (value.isEmpty)
                                      return 'Email is required';
                                    if (!value.contains('@'))
                                      return 'Enter a valid email';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
AuthTextField(
                                    label: "PASSWORD",
                                    hint: "At least 6 characters",
                                    icon: Icons.lock_outline,
                                    controller: _password,
                                    isPassword: true,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _submit(),
                                    validator: (v) => (v == null || v.length < 6)
                                        ? 'At least 6 characters'
                                        : null,
                                  ),
                                  if (!_signUp)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _busy ? null : _forgotPassword,
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.primary,
                                        ),
                                        child: const Text('Forgot password?'),
                                      ),
                                    ),
                                ],
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _isSuccessMsg
                                    ? AppColors.accentGreenLight
                                    : AppColors.accentRedLight,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isSuccessMsg
                                      ? AppColors.accentGreen.withOpacity(0.2)
                                      : AppColors.accentRed.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isSuccessMsg
                                        ? Icons.check_circle_outline
                                        : Icons.error_outline,
                                    size: 18,
                                    color: _isSuccessMsg
                                        ? AppColors.accentGreen
                                        : AppColors.accentRed,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12.5,
                                        color: _isSuccessMsg
                                            ? AppColors.accentGreen
                                            : AppColors.accentRed,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_needsConfirmation) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _busy || !_canResend
                                          ? null
                                          : _resend,
                                      icon: const Icon(
                                        Icons.mail_outline,
                                        size: 16,
                                      ),
                                      label: Text(
                                        _canResend
                                            ? 'Resend confirmation'
                                            : 'Sent — check inbox',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                        side: const BorderSide(
                                          color: AppColors.border,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'After confirming, tap Sign in. Schools onboarding appears automatically when you have no school yet.',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 11,
                                  color: AppColors.onSurfaceVariant.withOpacity(
                                    0.6,
                                  ),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                minimumSize: const Size(0, 56),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: const StadiumBorder(),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _signUp
                                              ? 'Create account'
                                              : 'Sign in',
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _signUp
                                    ? 'Already have an account?'
                                    : "Don't have an account yet?",
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 13,
                                  color: AppColors.onSurfaceVariant.withOpacity(
                                    0.7,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _busy ? null : _toggleMode,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                ),
                                child: Text(
                                  _signUp ? 'Sign in' : 'Create account',
                                  style: const TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'By continuing, you agree to our Terms & Privacy Policy',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant.withOpacity(
                                  0.45,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool get _isSuccessMsg =>
      _error != null && _error!.toLowerCase().contains('check your inbox');

  Widget _buildFeatureRow() {
    return Row(
      children: [
        _FeatureChip(icon: Icons.verified_outlined, label: 'MINESEC\nAligned'),
        const SizedBox(width: 12),
        _FeatureChip(
          icon: Icons.offline_bolt_outlined,
          label: 'Offline\nReady',
        ),
        const SizedBox(width: 12),
        _FeatureChip(icon: Icons.calculate_outlined, label: 'Mordern'),
      ],
    );
  }

  Widget _buildCompactLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Top branded header for mobile
          Container(
            width: double.infinity,
            color: AppColors.primary,
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ReportWise',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cameroon Secondary Platform',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _signUp ? 'Create account' : 'Welcome Back',
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _signUp
                            ? 'Join our platform and manage your school.'
                            : 'Enter your credentials to continue.',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          color: AppColors.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_signUp) ...[
                        AuthTextField(
                          label: 'FULL NAME',
                          hint: 'Your full name',
                          icon: Icons.person_outline,
                          controller: _fullName,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      AuthTextField(
                        label: 'EMAIL',
                        hint: 'you@school.cm',
                        icon: Icons.mail_outline,
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final val = v?.trim() ?? '';
                          if (val.isEmpty) return 'Required';
                          if (!val.contains('@')) return 'Invalid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AuthTextField(
                        label: 'PASSWORD',
                        hint: 'At least 6 characters',
                        icon: Icons.lock_outline,
                        controller: _password,
                        isPassword: true,
                        onSubmitted: (_) => _submit(),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'At least 6 characters'
                            : null,
                      ),
                      if (!_signUp)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy ? null : _forgotPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isSuccessMsg
                                ? AppColors.accentGreenLight
                                : AppColors.accentRedLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              color: _isSuccessMsg
                                  ? AppColors.accentGreen
                                  : AppColors.accentRed,
                            ),
                          ),
                        ),
                        if (_needsConfirmation) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _busy || !_canResend ? null : _resend,
                              icon: const Icon(Icons.mail_outline, size: 16),
                              label: Text(
                                _canResend
                                    ? 'Resend confirmation'
                                    : 'Sent — check inbox',
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_signUp ? 'Create account' : 'Sign in'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _signUp
                                ? 'Already have an account?'
                                : "Don't have an account?",
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13,
                            ),
                          ),
                          TextButton(
                            onPressed: _toggleMode,
                            child: Text(_signUp ? 'Sign in' : 'Create account'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
