import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';

class FirstLaunchGate extends StatefulWidget {
  final Widget child;

  const FirstLaunchGate({super.key, required this.child});

  @override
  State<FirstLaunchGate> createState() => _FirstLaunchGateState();
}

class _FirstLaunchGateState extends State<FirstLaunchGate> {
  late Future<bool> _seen;

  @override
  void initState() {
    super.initState();
    _seen = _hasSeenOnboarding();
  }

  Future<bool> _hasSeenOnboarding() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('reportwise_brand_onboarding_seen') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _seen,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _LaunchSplash();
        return snapshot.data!
            ? widget.child
            : BrandOnboarding(child: widget.child);
      },
    );
  }
}

class BrandOnboarding extends StatefulWidget {
  final Widget child;

  const BrandOnboarding({super.key, required this.child});

  @override
  State<BrandOnboarding> createState() => _BrandOnboardingState();
}

class _BrandOnboardingState extends State<BrandOnboarding> {
  final _pages = const [
    _BrandPage(
      title: 'Run your school with clarity',
      body:
          'ReportWise brings students, classes, teachers, subjects, and results into one trusted school workspace.',
      icon: Icons.dashboard_customize_outlined,
      color: AppColors.secondary,
    ),
    _BrandPage(
      title: 'Make every mark count',
      body:
          'Teachers enter the right sequence marks for their assigned classes, while terms and report cards stay accurate.',
      icon: Icons.edit_note_rounded,
      color: AppColors.primary,
    ),
    _BrandPage(
      title: 'Build better outcomes together',
      body:
          'Give school leaders a clear view of progress and give families reliable, professional academic records.',
      icon: Icons.insights_outlined,
      color: Color(0xFFF2A900),
    ),
  ];
  final _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('reportwise_brand_onboarding_seen', true);
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => widget.child));
    }
  }

  void _next() {
    if (_current == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_current];
    return Scaffold(
      backgroundColor: AppColors.surfaceLow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/reportwise_logo.png',
                        width: 150,
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                      const Spacer(),
                      TextButton(onPressed: _finish, child: const Text('Skip')),
                    ],
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: (index) =>
                          setState(() => _current = index),
                      itemBuilder: (context, index) =>
                          _BrandPageView(page: _pages[index]),
                    ),
                  ),
                  Row(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < _pages.length; i++)
                            _Dot(active: i == _current, color: page.color),
                        ],
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _next,
                        icon: Icon(
                          _current == _pages.length - 1
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _current == _pages.length - 1
                              ? 'Get started'
                              : 'Continue',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPage extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final Color color;

  const _BrandPage({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _BrandPageView extends StatelessWidget {
  final _BrandPage page;

  const _BrandPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 220,
          height: 220,
          padding: const EdgeInsets.all(34),
          decoration: BoxDecoration(
            color: page.color.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          child: Image.asset(
            'assets/images/reportwise_icon.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 42),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14,
            height: 1.6,
            color: AppColors.onSurfaceVariant.withOpacity(0.78),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  final Color color;

  const _Dot({required this.active, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    margin: const EdgeInsets.only(right: 6),
    width: active ? 24 : 7,
    height: 7,
    decoration: BoxDecoration(
      color: active ? color : AppColors.border,
      borderRadius: BorderRadius.circular(99),
    ),
  );
}

class _LaunchSplash extends StatelessWidget {
  const _LaunchSplash();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surfaceLow,
    body: Center(
      child: Image.asset('assets/images/reportwise_logo.png', width: 220),
    ),
  );
}
