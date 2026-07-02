import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

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
  final OnAudioQuery _query = OnAudioQuery();
  _GateState _state = _GateState.checking;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check AFTER the first frame so the plugin is fully attached to the
    // Activity — requesting during startup returns false without a dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _state != _GateState.granted) {
      _check();
    }
  }

  Future<void> _check() async {
    final granted = await _query.permissionsStatus();
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
    bool granted = await _query.permissionsStatus();
    if (!granted) {
      granted = await _query.permissionsRequest();
    }
    _requesting = false;
    if (!mounted) return;
    if (granted) {
      _grant();
    } else {
      setState(() => _state = _GateState.denied);
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
        return _PermissionScreen(onGrant: _request);
    }
  }
}

class _PermissionScreen extends StatelessWidget {
  const _PermissionScreen({required this.onGrant});

  final VoidCallback onGrant;

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
                  child: const Text('Allow music access'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'If you already allowed it, tap again to continue.',
                  style: theme.textTheme.bodySmall,
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