import 'package:dart_couch/dart_couch.dart';
import 'package:dart_couch_widgets/src/db_state_proxy_widget/replication_state_proxy_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const notReady = [
    ReplicationState.waitingForNetwork,
    ReplicationState.terminated,
    ReplicationState.paused,
    ReplicationState.error,
    ReplicationState.initializing,
  ];

  group('isInitialSyncGateOpen', () {
    test('flag false keeps the gate closed regardless of state', () {
      // The decision takes only flags; every state maps to the same input.
      for (final _ in notReady) {
        expect(isInitialSyncGateOpen([false]), isFalse);
      }
    });

    test('flag true opens even when waiting for network', () {
      expect(isInitialSyncGateOpen([true]), isTrue);
    });

    test('mixed databases stay closed until all are true', () {
      expect(isInitialSyncGateOpen([true, false]), isFalse);
      expect(isInitialSyncGateOpen([false, true, true]), isFalse);
      expect(isInitialSyncGateOpen([true, true]), isTrue);
    });

    test('flag flipping false to true opens', () {
      final flags = DcValueNotifier<bool>(false);
      expect(isInitialSyncGateOpen([flags.value]), isFalse);
      flags.value = true;
      expect(isInitialSyncGateOpen([flags.value]), isTrue);
    });
  });

  group('replicationStateHint', () {
    ReplicationProgress p(ReplicationState s, {String? message}) =>
        ReplicationProgress(state: s, message: message);

    test('maps states to hints', () {
      expect(
        replicationStateHint(p(ReplicationState.waitingForNetwork)),
        'Waiting for network…',
      );
      expect(
        replicationStateHint(
          p(ReplicationState.waitingForNetwork, message: 'offline'),
        ),
        'Waiting for network…',
      );
      expect(replicationStateHint(p(ReplicationState.paused)), 'Paused');
      expect(replicationStateHint(p(ReplicationState.terminated)), 'Paused');
      expect(
        replicationStateHint(p(ReplicationState.initializing)),
        'Initializing…',
      );
      expect(
        replicationStateHint(p(ReplicationState.error, message: 'boom')),
        'Error: boom',
      );
      expect(
        replicationStateHint(p(ReplicationState.initialSyncInProgress)),
        isNull,
      );
    });

    test('overall hint prefers errors', () {
      expect(
        overallReplicationHint([
          p(ReplicationState.paused),
          p(ReplicationState.error, message: 'x'),
        ]),
        'Error: x',
      );
      expect(
        overallReplicationHint([
          p(ReplicationState.initialSyncInProgress),
          p(ReplicationState.paused),
        ]),
        'Paused',
      );
      expect(
        overallReplicationHint([p(ReplicationState.initialSyncInProgress)]),
        isNull,
      );
    });
  });
}
