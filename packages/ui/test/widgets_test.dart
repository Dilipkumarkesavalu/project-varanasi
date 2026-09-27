import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varanasi_ui/varanasi_ui.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildVaranasiTheme(),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('VButton calls onPressed, and ignores taps while loading', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(VButton(label: 'Save', onPressed: () => taps++)),
    );
    await tester.tap(find.text('Save'));
    expect(taps, 1);

    await tester.pumpWidget(
      _wrap(VButton(label: 'Save', loading: true, onPressed: () => taps++)),
    );
    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('required VTextField validates inside a Form', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      _wrap(
        Form(
          key: formKey,
          child: const VTextField(label: 'Customer name', required: true),
        ),
      ),
    );

    expect(find.text('Customer name *'), findsOneWidget);
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Customer name is required.'), findsOneWidget);
  });

  testWidgets('VDataTable shows rows, or the empty state', (tester) async {
    final columns = [
      VColumn<(String, int)>(label: 'Name', cell: (r) => r.$1),
      VColumn<(String, int)>(
        label: 'Qty',
        cell: (r) => '${r.$2}',
        numeric: true,
      ),
    ];
    await tester.pumpWidget(
      _wrap(VDataTable(columns: columns, rows: const [('Tea', 3)])),
    );
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        VDataTable(columns: columns, rows: const [], emptyTitle: 'No items'),
      ),
    );
    expect(find.text('No items'), findsOneWidget);
  });

  testWidgets('ErrorView shows the reference and retries', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        ErrorView(
          title: 'Could not load',
          correlationId: 'req-123',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Reference: req-123'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('showVConfirmDialog returns true only on confirm', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );

    final result = showVConfirmDialog(
      context: ctx,
      title: 'Void invoice?',
      message: 'This cannot be undone.',
      confirmLabel: 'Void',
      destructive: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Void'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });

  testWidgets('LoadingView shows a spinner and message', (tester) async {
    await tester.pumpWidget(
      _wrap(const LoadingView(message: 'Loading invoices…')),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading invoices…'), findsOneWidget);
  });
}
