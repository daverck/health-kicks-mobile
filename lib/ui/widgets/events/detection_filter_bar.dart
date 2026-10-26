import 'package:flutter/material.dart';

/// Data model representing a category filter option.
class CategoryFilterOption {
  final String id;
  final String label;
  final IconData icon;

  const CategoryFilterOption({
    required this.id,
    required this.label,
    required this.icon,
  });
}

/// Horizontal bar displaying category filter chips.
class DetectionFilterBar extends StatelessWidget {
  final List<CategoryFilterOption> filters;
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  const DetectionFilterBar({
    super.key,
    required this.filters,
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedCategory == filter.id;

          return FilterChip(
            selected: isSelected,
            avatar: Icon(
              filter.icon,
              size: 16,
              color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
            ),
            label: Text(filter.label),
            labelStyle: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            ),
            showCheckmark: false,
            selectedColor: theme.colorScheme.primary,
            checkmarkColor: theme.colorScheme.onPrimary,
            onSelected: (selected) {
              if (selected) {
                onSelected(filter.id);
              }
            },
          );
        },
      ),
    );
  }
}

