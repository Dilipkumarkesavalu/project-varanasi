import 'package:flutter/material.dart';
import 'package:varanasi_core/varanasi_core.dart';
import 'package:varanasi_ui/varanasi_ui.dart';

import 'backend_status_card.dart';

typedef _Row = ({String name, String plan, int users});

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
    (name: 'Sharma Traders', plan: 'Billing + HRMS', users: 12),
    (name: 'Ganga Textiles', plan: 'HRMS', users: 48),
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
      title: 'Create tenant',
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
      appBar: AppBar(title: const Text('Varanasi Platform')),
      body: ListView(
        padding: const EdgeInsets.all(VSpacing.xl),
        children: [
          BackendStatusCard(api: widget.api),
          const SizedBox(height: VSpacing.xl),
          Text('Create tenant', style: textTheme.titleLarge),
          const SizedBox(height: VSpacing.md),
          Form(
            key: _formKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: VTextField(
                    label: 'Organization name',
                    controller: _name,
                    required: true,
                  ),
                ),
                const SizedBox(width: VSpacing.md),
                VButton(
                  label: 'Create tenant',
                  icon: Icons.add,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
          const SizedBox(height: VSpacing.xl),
          Text('Tenants (sample data)', style: textTheme.titleLarge),
          const SizedBox(height: VSpacing.md),
          VDataTable<_Row>(
            columns: [
              VColumn(label: 'Tenant', cell: (r) => r.name),
              VColumn(label: 'Plan', cell: (r) => r.plan),
              VColumn(label: 'Users', cell: (r) => '${r.users}', numeric: true),
            ],
            rows: _sampleRows,
          ),
        ],
      ),
    );
  }
}
