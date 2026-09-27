import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'state_views.dart';

/// One column of a [VDataTable].
class VColumn<T> {
  const VColumn({
    required this.label,
    required this.cell,
    this.numeric = false,
  });

  final String label;
  final String Function(T row) cell;

  /// Right-aligned with tabular figures (amounts, counts).
  final bool numeric;
}

/// Simple data table with a built-in empty state. Horizontally scrollable on narrow screens.
class VDataTable<T> extends StatelessWidget {
  const VDataTable({
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    super.key,
  });

  final List<VColumn<T>> columns;
  final List<T> rows;
  final ValueChanged<T>? onRowTap;
  final String emptyTitle;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return EmptyView(title: emptyTitle, message: emptyMessage);
    }
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: textTheme.labelLarge?.copyWith(
            color: VColors.textSecondary,
          ),
          showCheckboxColumn: false,
          columns: [
            for (final column in columns)
              DataColumn(label: Text(column.label), numeric: column.numeric),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                onSelectChanged: onRowTap == null
                    ? null
                    : (_) => onRowTap!(row),
                cells: [
                  for (final column in columns)
                    DataCell(
                      Text(
                        column.cell(row),
                        style: column.numeric
                            ? const TextStyle(
                                fontFeatures: VTypography.tabularFigures,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
