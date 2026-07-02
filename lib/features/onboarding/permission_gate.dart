import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../library/providers/library_providers.dart';

enum _GateState { checking, granted, denied }

class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends ConsumerState<PermissionGate>
    with WidgetsBindingObserver {
  _GateState _state = _GateState.checking;
  bool _requesting = false;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when returning from system Settings.
    if (state == AppLifecycleState.resumed && _state != _GateState.granted) {
      _check();
    }
  }

  /// Android 13+ uses READ_MEDIA_AUDIO (Permission.audio); older Android
  /// uses READ_EXTERNAL_STORAGE (Permission.storage). Checking both covers
  /// every API level — the irrelevant one simply reports denied.
  Future<bool> _isGranted() async {
    final audio = await Permission.audio.status;
    final storage = await Permission.storage.status;
    debugPrint('[Orvo] gate status: audio=$audio storage=$storage');
    return audio.isGranted || storage.isGranted;
  }

  Future<void> _check() async {
    final granted = await _isGranted();
    if (!mounted) return;
    if (granted) {
      _grant();
    } else {
      setState(() => _state = _GateState.denied);
    }
  }

  Future<void> _request() async {
    if (_requesting) return;
    _requesting = true;
    try {
      if (await _isGranted()) {
        if (mounted) _grant();
        return;
      }

      // Requesting both in one call shows a single dialog for whichever
      // permission applies to this Android version.
      final results =
          await [Permission.audio, Permission.storage].request();
      debugPrint('[Orvo] gate request results: $results');

      final audio = results[Permission.audio];
      final storage = results[Permission.storage];
      final granted =
          (audio?.isGranted ?? false) || (storage?.isGranted ?? false);

      if (!mounted) return;
      if (granted) {
        _grant();
        return;
      }

      // "Don't allow" twice (or a policy block) — the dialog will never
      // show again; the user must enable it from app settings.
      final permanent = (audio?.isPermanentlyDenied ?? false) &&
          (storage == null || !storage.isGranted);
      setState(() {
        _permanentlyDenied = permanent;
        _state = _GateState.denied;
      });
      if (permanent) {
        await openAppSettings();
      }
    } finally {
      _requesting = false;
    }
  }

  void _grant() {
    setState(() => _state = _GateState.granted);
    ref.read(permissionGrantedProvider.notifier).state = true;
    ref.invalidate(songsProvider);
    ref.invalidate(albumsProvider);
    ref.invalidate(artistsProvider);
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.granted:
        return widget.child;
      case _GateState.checking:
        return const Scaffold(body: SizedBox.shrink());
      case _GateState.denied:
        return _PermissionScreen(
          onGrant: _request,
          permanentlyDenied: _permanentlyDenied,
        );
    }
  }
}

class _PermissionScreen extends StatelessWidget {
  const _PermissionScreen({
    required this.onGrant,
    required this.permanentlyDenied,
  });

  final VoidCallback onGrant;
  final bool permanentlyDenied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(Icons.library_music_rounded,
                    size: 36, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 28),
              Text('Your music,\nbeautifully played.',
                  style: theme.textTheme.displayLarge),
              const SizedBox(height: 14),
              Text(
                'Orvo plays the songs already on this device. Allow music access '
                'to build your library — nothing ever leaves your phone.',
                style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(.65)),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: onGrant,
                  child: Text(permanentlyDenied
                      ? 'Open settings'
                      : 'Allow music access'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  permanentlyDenied
                      ? 'Enable "Music and audio" for Orvo in Settings, then come back.'
                      : 'If you already allowed it, tap again to continue.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .moveY(begin: 20, end: 0, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}