import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncgate/src/app/providers.dart';

/// IDs of the workers who have agreed to the privacy notice.
final FutureProvider<Set<String>> consentedWorkersProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
      final workers = await ref.watch(workerRepositoryProvider).all();
      ref.watch(workersProvider);
      final consent = ref.watch(consentRepositoryProvider);
      return {
        for (final w in workers)
          if (await consent.hasConsent(w.id)) w.id,
      };
    });
