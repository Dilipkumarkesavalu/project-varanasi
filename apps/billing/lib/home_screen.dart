import 'package:flutter/material.dart';
import 'package:varanasi_core/varanasi_core.dart';
import 'package:varanasi_ui/varanasi_ui.dart';

import 'backend_status_card.dart';

typedef _Row = ({String number, String customer, String total});

/// Sample screen proving the shared packages work end to end (M1-FOU-004/005):
/// the backend status comes through [ApiClient]; everything else is `varanasi_ui`.
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.api, super.key});

  final ApiClient api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  static const List<_Row> _sampleRows = [
    (number: 'INV-2026-000123', customer: 'Kashi Stores', total: '11,800.00'),
    (number: 'INV-2026-000122', customer: 'Assi Ghat Cafe', total: '4,500.00'),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await showVDialog<void>(
      context: context,
      title: 'Create invoice',
      body: Text(
        '"${_name.text.trim()}" would be saved here once the API exists.',
      ),
      actions: [
        Builder(
          builder: (context) => VButton(
            label: 'OK',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Varanasi Billing')),
      body: ListView(
        padding: const EdgeInsets.all(VSpacing.xl),
        children: [
          BackendStatusCard(api: widget.api),
          const SizedBox(height: VSpacing.xl),
          Text('Create invoice', style: textTheme.titleLarge),
          const SizedBox(height: VSpacing.md),
          Form(
            key: _formKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: VTextField(
                    label: 'Customer name',
                    controller: _name,
                    required: true,
                  ),
                ),
                const SizedBox(width: VSpacing.md),
                VButton(
                  label: 'Create invoice',
                  icon: Icons.add,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
          const SizedBox(height: VSpacing.xl),
          Text('Invoices (sample data)', style: textTheme.titleLarge),
          const SizedBox(height: VSpacing.md),
          VDataTable<_Row>(
            columns: [
              VColumn(label: 'Invoice', cell: (r) => r.number),
              VColumn(label: 'Customer', cell: (r) => r.customer),
              VColumn(
                label: 'Total (INR)',
                cell: (r) => r.total,
                numeric: true,
              ),
            ],
            rows: _sampleRows,
          ),
        ],
      ),
    );
  }
}
