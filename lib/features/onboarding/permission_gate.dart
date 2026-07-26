import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart' show OnAudioQuery;
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/media_permissions.dart';
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

  /// FIX (#18): the required permission is SDK-dependent —
  /// READ_MEDIA_AUDIO (Permission.audio) on Android 13+,
  /// READ_EXTERNAL_STORAGE (Permission.storage) on Android 12 and below.
  /// permission_handler 11.x does NOT map Permission.audio to storage on
  /// old Androids (the old FIX #3 comment claimed it did) — it just returns
  /// denied instantly, so the system dialog never appeared on Android ≤ 12.
  Future<bool> _isGranted() async {
    final perm = await MediaPermissions.required();
    final status = await perm.status;
    debugPrint('[Orvo] gate status: $perm=$status '
        '(sdk=${await MediaPermissions.sdkInt()})');
    if (!status.isGranted) return false;

    // FIX (#19): the system permission alone is NOT enough — on_audio_query
    // gates every query on its OWN check (READ + WRITE external storage on
    // Android ≤ 12; READ_MEDIA_AUDIO + READ_MEDIA_IMAGES on 13+). If we let
    // the app through while that check fails, queries throw
    // MissingPermissions and the fork's error path crashes natively with
    // "Reply already submitted". So the plugin's status is the final word.
    final pluginOk = await _pluginStatus();
    debugPrint('[Orvo] plugin permissionsStatus: $pluginOk');
    return pluginOk;
  }

  Future<bool> _pluginStatus() async {
    try {
      return await OnAudioQuery().permissionsStatus();
    } catch (e) {
      debugPrint('[Orvo] plugin permissionsStatus ERROR: $e');
      return false;
    }
  }

  Future<void> _check() async {
    var granted = await _isGranted();

    // System side granted but plugin side not (e.g. WRITE_EXTERNAL_STORAGE
    // newly declared but never requested): top it up silently. Since the
    // storage group is already approved, this auto-grants without a dialog.
    if (!granted) {
      final perm = await MediaPermissions.required();
      if ((await perm.status).isGranted) {
        await _ensurePluginPermission();
        granted = await _pluginStatus();
      }
    }

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

      final requiredPerm = await MediaPermissions.required();
      final imagesPerm = await MediaPermissions.optionalImages();

      // Ask for everything relevant in one system flow — images purely for
      // album art on Android 13+ — but gate ONLY on the required permission.
      final results = await [
        requiredPerm,
        if (imagesPerm != null) imagesPerm,
      ].request();
      debugPrint('[Orvo] gate request results: $results');

      final status = results[requiredPerm];
      final granted = status?.isGranted ?? false;

      if (!mounted) return;
      if (granted) {
        // FIX (#19): system permission granted — now make the plugin's own
        // check pass too (it additionally needs WRITE_EXTERNAL_STORAGE on
        // Android ≤ 12). Only open the gate once the plugin agrees, so its
        // queries can never hit the natively-crashing MissingPermissions
        // path.
        await _ensurePluginPermission();
        final pluginOk = await _pluginStatus();
        if (!mounted) return;
        if (pluginOk) {
          _grant();
        } else {
          debugPrint('[Orvo] plugin still lacks permission after sync');
          setState(() => _state = _GateState.denied);
        }
        return;
      }

      // Only the required permission being permanently denied blocks the
      // app; the fix lives in system Settings.
      final permanent = status?.isPermanentlyDenied ?? false;
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

  /// FIX (#19): asks the plugin to request its OWN permission array
  /// ([READ, WRITE] external storage on Android ≤ 12) so its internal check
  /// passes. With the storage group already approved by the user, this
  /// auto-grants without showing another dialog.
  Future<void> _ensurePluginPermission() async {
    try {
      final query = OnAudioQuery();
      if (!await query.permissionsStatus()) {
        final requested = await query.permissionsRequest();
        debugPrint('[Orvo] plugin permissionsRequest: $requested');
      }
    } catch (e) {
      debugPrint('[Orvo] plugin permission sync ERROR: $e');
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
                'Orvo plays the songs already on this device. Allow music '
                'access to build your library — photo access is optional '
                'and only used for album art. Nothing ever leaves your '
                'phone.',
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
                      : 'Allow access'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  permanentlyDenied
                      ? 'In Settings → Permissions, allow "Music and audio" '
                          'for Orvo.'
                      : 'Only music access is required — you can skip the '
                          'photos prompt if you prefer.',
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
