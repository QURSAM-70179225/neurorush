import 'package:flutter/material.dart';

/// Material icons for the names used in shared/achievements.json.
const achievementIcons = <String, IconData>{
  'flag': Icons.flag_rounded,
  'directions_run': Icons.directions_run_rounded,
  'fitness_center': Icons.fitness_center_rounded,
  'sports_martial_arts': Icons.sports_martial_arts_rounded,
  'all_inclusive': Icons.all_inclusive_rounded,
  'bolt': Icons.bolt_rounded,
  'electric_bolt': Icons.electric_bolt_rounded,
  'trending_up': Icons.trending_up_rounded,
  'auto_awesome': Icons.auto_awesome_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'local_fire_department': Icons.local_fire_department_rounded,
  'whatshot': Icons.whatshot_rounded,
  'calendar_month': Icons.calendar_month_rounded,
  'military_tech': Icons.military_tech_rounded,
  'star': Icons.star_rounded,
  'stars': Icons.stars_rounded,
  'verified': Icons.verified_rounded,
  'diamond': Icons.diamond_rounded,
  'timeline': Icons.timeline_rounded,
  'crown': Icons.emoji_events_rounded,
  'speed': Icons.speed_rounded,
  'flash_on': Icons.flash_on_rounded,
  'explore': Icons.explore_rounded,
  'psychology': Icons.psychology_rounded,
  'psychology_alt': Icons.psychology_alt_rounded,
  'terrain': Icons.terrain_rounded,
  'group_add': Icons.group_add_rounded,
  'groups': Icons.groups_rounded,
  'calculate': Icons.calculate_rounded,
  'photo_camera': Icons.photo_camera_rounded,
};

IconData achievementIcon(String name) => achievementIcons[name] ?? Icons.emoji_events_rounded;
