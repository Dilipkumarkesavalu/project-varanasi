import 'package:flutter/material.dart';
import 'package:varanasi_core/varanasi_core.dart';
import 'package:varanasi_ui/varanasi_ui.dart';

/// Calls `GET /health` through the shared [ApiClient] and shows the result.
class BackendStatusCard extends StatefulWidget {
  const BackendStatusCard({required this.api, super.key});

  final ApiClient api;

  @override
  State<BackendStatusCard> createState() => _BackendStatusCardState();
}

class _BackendStatusCardState extends State<BackendStatusCard> {
  late Future<ApiResponse> _health = widget.api.get('/health');

  void _retry() => setState(() => _health = widget.api.get('/health'));

  @override
  Widget build(BuildContext context) {
    return Card(
      // Sized by its content (loading, error with retry, or status), at least 120px tall.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: FutureBuilder<ApiResponse>(
          future: _health,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingView(message: 'Checking backend…');
            }
            final error = snapshot.error;
            if (error != null) {
              return ErrorView(
                title: 'Backend unreachable',
                message: error is ApiException ? error.title : null,
                correlationId: error is ApiException
                    ? error.correlationId
                    : null,
                onRetry: _retry,
              );
            }
            return Padding(
              padding: const EdgeInsets.all(VSpacing.xl),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: VColors.success),
                  const SizedBox(width: VSpacing.sm),
                  Text('Backend status: ${snapshot.data!.json['status']}'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
