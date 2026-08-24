import 'package:academic_engine/academic_engine.dart';
import 'package:flutter/material.dart';

/// Landing/home screen.
///
/// The demo card at the bottom runs the real Engine against the spec's
/// validation example (section 30) — proof that the academic engine is wired
/// into the app.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.school_rounded,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'ReportWise',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Cameroon Secondary School Management Platform',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 48),
              const _EngineDemoCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineDemoCard extends StatelessWidget {
  const _EngineDemoCard();

  @override
  Widget build(BuildContext context) {
    // Section 30 validation example, computed by the real engine.
    final scheme = const SchemeConfig(
      id: 'demo',
      name: 'Demo',
      components: [
        AssessmentComponent(
            id: 'exam', name: 'Exam', componentType: 'EXAM', weight: 1.0, maxScore: 20),
      ],
      source: ConfigSource.nationalDefault,
    );
    final result = computeStudentPeriod(
      studentId: 'demo',
      scheme: scheme,
      subjects: const [
        SubjectConfig(
            subjectId: 'MATHS', code: 'MATHS', name: 'Mathematics', coefficient: 5),
        SubjectConfig(
            subjectId: 'PHY', code: 'PHY', name: 'Physics', coefficient: 4),
        SubjectConfig(
            subjectId: 'ENG', code: 'ENG', name: 'English', coefficient: 2),
      ],
      marks: const [
        ComponentMark(subjectId: 'MATHS', componentId: 'exam', score: 14),
        ComponentMark(subjectId: 'PHY', componentId: 'exam', score: 12),
        ComponentMark(subjectId: 'ENG', componentId: 'exam', score: 15),
      ],
      policy: MissingMarkPolicy(
        excludedStatuses: AbsenceStatus.values
            .where((s) => s != AbsenceStatus.entered && s != AbsenceStatus.zero)
            .toSet(),
      ),
      display: DisplayPrecision.standard,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Grading engine smoke test',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...result.subjects.map((s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(s.config.name),
                  trailing: Text(
                    '${s.subjectAverage?.toStringAsFixed(2) ?? '—'} × '
                    '${s.config.coefficient.toStringAsFixed(1)} = '
                    '${s.weightedPoints?.toStringAsFixed(2) ?? '—'}',
                  ),
                )),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('General average'),
              trailing: Text(
                result.generalAverage?.toStringAsFixed(2) ?? '—',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}