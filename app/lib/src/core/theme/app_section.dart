import 'package:flutter/material.dart';

enum AppSection {
  dashboard,
  studentRegistry,
  teacherRegistry,
  academicRecords,
  marks,
  reportCards,
  classes,
  subjects,
  settings,
}

extension AppSectionX on AppSection {
  String get label {
    switch (this) {
      case AppSection.dashboard:
        return 'Dashboard';
      case AppSection.studentRegistry:
        return 'Students';
      case AppSection.teacherRegistry:
        return 'Teachers';
      case AppSection.academicRecords:
        return 'Academic';
      case AppSection.marks:
        return 'Mark entry';
      case AppSection.reportCards:
        return 'Reports';
      case AppSection.classes:
        return 'Classes';
      case AppSection.subjects:
        return 'Subjects';
      case AppSection.settings:
        return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case AppSection.dashboard:
        return Icons.dashboard_outlined;
      case AppSection.studentRegistry:
        return Icons.people_outlined;
      case AppSection.teacherRegistry:
        return Icons.groups_outlined;
      case AppSection.academicRecords:
        return Icons.calendar_view_day_outlined;
      case AppSection.marks:
        return Icons.edit_note_outlined;
      case AppSection.reportCards:
        return Icons.description_outlined;
      case AppSection.classes:
        return Icons.menu_book_outlined;
      case AppSection.subjects:
        return Icons.stacked_bar_chart_outlined;
      case AppSection.settings:
        return Icons.settings_outlined;
    }
  }

  IconData get iconFilled {
    switch (this) {
      case AppSection.dashboard:
        return Icons.dashboard_rounded;
      case AppSection.studentRegistry:
        return Icons.people_rounded;
      case AppSection.teacherRegistry:
        return Icons.groups_rounded;
      case AppSection.academicRecords:
        return Icons.calendar_view_day_rounded;
      case AppSection.marks:
        return Icons.edit_note_rounded;
      case AppSection.reportCards:
        return Icons.description_rounded;
      case AppSection.classes:
        return Icons.menu_book_rounded;
      case AppSection.subjects:
        return Icons.stacked_bar_chart_rounded;
      case AppSection.settings:
        return Icons.settings_rounded;
    }
  }
}
