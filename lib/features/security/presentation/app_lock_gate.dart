import 'package:flutter/material.dart';
import 'package:androidircx/core/security/device_unlock_session.dart';

/// Returns true if the user successfully authenticated.
typedef AppUnlockCallback = Future<bool> Function();

/// Gates [child] behind a biometric/PIN unlock when [enabled].
///
/// Locks again whenever the app is backgrounded, so returning to the app
/// requires re-authentication. [unlock] is overridable for tests; the default
/// prompts biometric with a device-credential (PIN/passphrase) fallback.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.enabled,
    required this.child,
    this.unlock,
  });

  final bool enabled;
  final Widget child;
  final AppUnlockCallback? unlock;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _prompting = false;
  bool _hasMountedChild = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUnlock());
    } else {
      _unlocked = true;
      _hasMountedChild = true;
    }
  }

  @override
  void didUpdateWidget(covariant AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _unlocked = true;
      _hasMountedChild = true;
    } else if (!oldWidget.enabled && widget.enabled) {
      // Just enabled at runtime: the user is already in the app (and confirmed
      // authentication in Settings), so stay unlocked now. The lock engages on
      // the next time the app is backgrounded and resumed.
      _unlocked = true;
      _hasMountedChild = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (mounted) {
        DeviceUnlockSession.instance.invalidate();
        setState(() => _unlocked = false);
      }
    } else if (state == AppLifecycleState.resumed && !_unlocked) {
      _attemptUnlock();
    }
  }

  Future<bool> _defaultUnlock() async {
    return DeviceUnlockSession.instance.authenticate(
      reason: 'Unlock AndroidIRCX',
    );
  }

  Future<void> _attemptUnlock() async {
    if (_prompting || _unlocked || !mounted) {
      return;
    }
    _prompting = true;
    final unlocked = await (widget.unlock ?? _defaultUnlock)();
    _prompting = false;
    if (mounted && unlocked) {
      setState(() {
        _unlocked = true;
        _hasMountedChild = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.enabled && !_unlocked;
    if (!_hasMountedChild && locked) {
      return const _AppLockScreen();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: IgnorePointer(
            ignoring: locked,
            child: TickerMode(enabled: !locked, child: widget.child),
          ),
        ),
        if (locked) const Positioned.fill(child: _AppLockScreen()),
      ],
    );
  }
}

class _AppLockScreen extends StatelessWidget {
  const _AppLockScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('AndroidIRCX is locked', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                final state = context
                    .findAncestorStateOfType<_AppLockGateState>();
                state?._attemptUnlock();
              },
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
