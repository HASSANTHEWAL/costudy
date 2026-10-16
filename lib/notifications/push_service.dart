import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push notification plumbing for FR-06 — simultaneous revelation.
///
/// The only notification CoStudy ever sends is "a session formed", and every
/// member receives it at the same moment from one multicast in the scheduled
/// matcher. There is deliberately no "someone is interested in you", no
/// nudge, no re-engagement prompt: an unmatched intent expires in silence, so
/// there is nothing else this channel is for.
///
/// The token lives at users/{uid}.fcmToken, which firestore.rules makes
/// strictly owner-readable and owner-writable — otherwise another student
/// could redirect a session notification to their own device.
class PushService {
  PushService({FirebaseMessaging? messaging, FirebaseFirestore? firestore})
      : _injectedMessaging = messaging,
        _injectedFirestore = firestore;

  final FirebaseMessaging? _injectedMessaging;
  final FirebaseFirestore? _injectedFirestore;

  /// Resolved lazily so the service can be constructed before Firebase starts.
  late final FirebaseMessaging _messaging =
      _injectedMessaging ?? FirebaseMessaging.instance;
  late final FirebaseFirestore _db =
      _injectedFirestore ?? FirebaseFirestore.instance;

  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  /// Emits when a session-found push arrives while the app is open.
  final _sessionFound = StreamController<String?>.broadcast();

  /// Coalition id from an incoming `session_found` message, or null if the
  /// payload omitted one.
  Stream<String?> get onSessionFound => _sessionFound.stream;

  /// Ask for notification permission, register the token, and start listening.
  ///
  /// Called after sign-in rather than at launch: permission prompts shown
  /// before a student knows what the app does get denied, and on Android a
  /// denial is sticky. By this point they have registered an intent or are
  /// about to, so the request has a reason attached to it.
  Future<void> start(String uid) async {
    // Explicit request is required on both platforms — Android 13+ gates
    // POST_NOTIFICATIONS behind a runtime prompt, and iOS has always done so.
    final settings = await _messaging.requestPermission();

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (granted) {
      try {
        final token = await _messaging.getToken();
        if (token != null) await _writeToken(uid, token);
      } on FirebaseException catch (error) {
        // A missing token is not fatal. The matcher skips members it cannot
        // reach and still forms their session — see notifyMembers().
        debugPrint('CoStudy: could not register FCM token (${error.code})');
      }

      // Tokens rotate on reinstall, restore, and periodically on their own. A
      // stale token means a silent miss on the one notification that matters,
      // so this subscription is not optional.
      _refreshSubscription?.cancel();
      _refreshSubscription = _messaging.onTokenRefresh.listen(
        (token) => _writeToken(uid, token),
        onError: (Object error) =>
            debugPrint('CoStudy: token refresh failed: $error'),
      );
    }

    _foregroundSubscription?.cancel();
    _foregroundSubscription =
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (message.data['type'] != 'session_found') return;
    _sessionFound.add(message.data['coalitionId'] as String?);
  }

  Future<void> _writeToken(String uid, String token) async {
    try {
      await _db.collection('users').doc(uid).set(
        {
          'fcmToken': token,
          'statusVerifikasi': true,
          'diperbaruiPada': FieldValue.serverTimestamp(),
        },
        // Merge: this must not clobber jurusan or preferensiSuasana, which
        // Profile Setup owns.
        SetOptions(merge: true),
      );
    } on FirebaseException catch (error) {
      debugPrint('CoStudy: could not store FCM token (${error.code})');
    }
  }

  /// Clear the token on sign-out.
  ///
  /// Matters on a shared device: without this the next student to sign in
  /// would keep receiving the previous one's session notifications.
  Future<void> stop(String? uid) async {
    await _refreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _refreshSubscription = null;
    _foregroundSubscription = null;

    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set(
        {'fcmToken': null},
        SetOptions(merge: true),
      );
    } on FirebaseException catch (error) {
      debugPrint('CoStudy: could not clear FCM token (${error.code})');
    }
  }

  Future<void> dispose() async {
    await stop(null);
    await _sessionFound.close();
  }
}
