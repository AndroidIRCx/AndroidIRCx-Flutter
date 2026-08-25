import 'package:androidircx/features/security/presentation/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  const _Host({required this.unlock});
  final AppUnlockCallback unlock;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _enabled = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _enabled = true),
              child: const Text('enable'),
            ),
            Expanded(
              child: AppLockGate(
                enabled: _enabled,
                unlock: widget.unlock,
                child: const Text('home content'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onDisposed});

  final VoidCallback onDisposed;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void dispose() {
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('home content');
}

void main() {
  testWidgets('enabling app lock at runtime does not immediately lock', (
    tester,
  ) async {
    var unlockCalls = 0;
    await tester.pumpWidget(
      _Host(
        unlock: () async {
          unlockCalls++;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('home content'), findsOneWidget);

    // Toggle app lock on while the app is in the foreground.
    await tester.tap(find.text('enable'));
    await tester.pumpAndSettle();

    // Stays unlocked; no unlock prompt fired, no lock screen shown.
    expect(find.text('home content'), findsOneWidget);
    expect(find.text('AndroidIRCX is locked'), findsNothing);
    expect(unlockCalls, 0);
  });

  testWidgets('app launched with lock enabled shows the lock screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          enabled: true,
          unlock: () async => false,
          child: const Text('home content'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AndroidIRCX is locked'), findsOneWidget);
    expect(find.text('home content'), findsNothing);
  });

  testWidgets('re-locking keeps the child session tree mounted', (
    tester,
  ) async {
    var unlockCalls = 0;
    var disposed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          enabled: true,
          unlock: () async {
            unlockCalls++;
            return true;
          },
          child: _Probe(onDisposed: () => disposed = true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(unlockCalls, 1);
    expect(find.text('home content'), findsOneWidget);

    final state = tester.state(find.byType(AppLockGate)) as dynamic;
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();

    expect(find.text('AndroidIRCX is locked'), findsOneWidget);
    expect(disposed, isFalse);
    expect(unlockCalls, 1);
  });
}
