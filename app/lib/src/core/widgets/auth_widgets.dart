import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AuthHeaderSection extends StatelessWidget {
  final String title;
  final String subtitle;
  const AuthHeaderSection({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.school_rounded, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ReportWise',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  'Cameroon Secondary Platform',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant.withOpacity(0.6),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13.5,
            color: AppColors.onSurfaceVariant.withOpacity(0.7),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class AuthSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const AuthSectionTitle({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: AppColors.primary,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class AuthTextField extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final bool isPassword;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  final List<String>? autofillHints;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.isPassword = false,
    this.keyboardType,
    this.validator,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A8A9A),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscure,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onSubmitted,
          autofillHints: widget.autofillHints,
          style: const TextStyle(fontFamily: 'Lexend', fontSize: 14, color: AppColors.onSurface),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon, size: 18, color: AppColors.onSurfaceVariant.withOpacity(0.6)),
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                      color: AppColors.onSurfaceVariant.withOpacity(0.5),
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class ResponsiveLayoutWrapper extends StatelessWidget {
  final List<Widget> children;
  final bool isCompact;
  const ResponsiveLayoutWrapper({super.key, required this.children, required this.isCompact});

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Column(
        children: children.map((c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: c)).toList(),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: children[0]),
        const SizedBox(width: 16),
        if (children.length > 1) Expanded(child: children[1]),
      ],
    );
  }
}
