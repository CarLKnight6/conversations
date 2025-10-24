import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:twilio_conversations/api.dart';
import 'package:twilio_conversations/twilio_conversations.dart';

class TwilioConversations extends FlutterLoggingApi {
  factory TwilioConversations() {
    _instance ??= TwilioConversations._();
    return _instance!;
  }
  static TwilioConversations? _instance;

  TwilioConversations._({
    PluginApi? pluginApi,
    ConversationApi? conversationApi,
    ParticipantApi? participantApi,
    UserApi? userApi,
    MessageApi? messageApi,
  }) {
    _pluginApi = pluginApi ?? PluginApi();
    _conversationApi = conversationApi ?? ConversationApi();
    _participantApi = participantApi ?? ParticipantApi();
    _userApi = userApi ?? UserApi();
    _messageApi = messageApi ?? MessageApi();
    FlutterLoggingApi.setup(this);
  }

  @visibleForTesting
  factory TwilioConversations.mock({
    PluginApi? pluginApi,
    ConversationApi? conversationApi,
    ParticipantApi? participantApi,
    UserApi? userApi,
    MessageApi? messageApi,
  }) {
    _instance = TwilioConversations._(
      pluginApi: pluginApi,
      conversationApi: conversationApi,
      participantApi: participantApi,
      userApi: userApi,
      messageApi: messageApi,
    );
    return _instance!;
  }

  late PluginApi _pluginApi;
  PluginApi get pluginApi => _pluginApi;

  final _conversationsClientApi = ConversationClientApi();
  ConversationClientApi get conversationsClientApi => _conversationsClientApi;

  late ConversationApi _conversationApi;
  ConversationApi get conversationApi => _conversationApi;

  late ParticipantApi _participantApi;
  ParticipantApi get participantApi => _participantApi;

  late MessageApi _messageApi;
  MessageApi get messageApi => _messageApi;

  late UserApi _userApi;
  UserApi get userApi => _userApi;

  static const EventChannel mediaProgressChannel =
      EventChannel('twilio_programmable_chat/media_progress');

  static bool _dartDebug = false;
  static ConversationClient? conversationClient;

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Create a [ConversationClient] with retry logic for channel errors.
  Future<ConversationClient?> create({
    required String jwtToken,
    Properties properties = const Properties(),
    int retryCount = 0,
  }) async {
    assert(jwtToken.isNotEmpty);

    log('create conversation plugin => token: ${jwtToken.substring(0, 50)}...');
    log('Attempt ${retryCount + 1} of $_maxRetries');

    conversationClient = ConversationClient();

    try {
      // Add a small delay before native call to ensure channel is ready
      await Future.delayed(const Duration(milliseconds: 500));

      log('Calling native pluginApi.create()...');

      final ConversationClientData result =
          await pluginApi.create(jwtToken, properties.toPigeon()).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Native create() timed out after 30 seconds');
        },
      );

      log('✅ Native create() succeeded');
      conversationClient
          ?.updateFromMap(Map<String, dynamic>.from(result.encode() as Map));

      return conversationClient;
    } on PlatformException catch (e) {
      log('❌ PlatformException: ${e.code} - ${e.message}');

      // Retry on channel-error or timeout
      if ((e.code == 'channel-error' ||
              e.message?.contains('Unable to establish connection') == true ||
              e.message?.contains('timeout') == true) &&
          retryCount < _maxRetries) {
        log('⏳ Retrying in ${_retryDelay.inSeconds} seconds... (Attempt ${retryCount + 1}/$_maxRetries)');

        await Future.delayed(_retryDelay);

        // Clear the client and retry
        conversationClient = null;
        return create(
          jwtToken: jwtToken,
          properties: properties,
          retryCount: retryCount + 1,
        );
      }

      // If max retries exceeded or different error, give up
      conversationClient = null;
      log('❌ create => Max retries exceeded or non-retryable error: $e');
      rethrow;
    } on TimeoutException catch (e) {
      log('❌ TimeoutException: $e');

      if (retryCount < _maxRetries) {
        log('⏳ Retrying after timeout... (Attempt ${retryCount + 1}/$_maxRetries)');
        await Future.delayed(_retryDelay);
        conversationClient = null;
        return create(
          jwtToken: jwtToken,
          properties: properties,
          retryCount: retryCount + 1,
        );
      }

      conversationClient = null;
      rethrow;
    } catch (e) {
      log('❌ Unexpected error: $e');
      conversationClient = null;
      rethrow;
    }
  }

  /// Check if the native channel is working
  Future<bool> isChannelReady() async {
    try {
      log('Checking if native channel is ready...');
      await Future.delayed(const Duration(milliseconds: 100));

      // Try a simple debug call to verify channel
      await pluginApi.debug(false, false);

      log('✅ Native channel is ready');
      return true;
    } catch (e) {
      log('❌ Native channel error: $e');
      return false;
    }
  }

  static Exception convertException(PlatformException err) {
    if (err.code == 'TwilioException') {
      final parts = err.message!.split('|');
      final code = parts.first;
      final message = parts.last;
      return TwilioException(code: code, message: message);
    } else if (err.code == 'ClientNotInitializedException') {
      return ClientNotInitializedException(
        code: err.code,
        message: err.message,
        details: err.details,
      );
    } else if (err.code == 'ConversionException') {
      return ConversionException(
        code: err.code,
        message: err.message,
        details: err.details,
      );
    } else if (err.code == 'MissingParameterException') {
      return MissingParameterException(
        code: err.code,
        message: err.message,
        details: err.details,
      );
    } else if (err.code == 'NotFoundException') {
      return NotFoundException(
        code: err.code,
        message: err.message,
        details: err.details,
      );
    }
    return err;
  }

  /// Internal logging method for dart.
  static void log(dynamic msg) {
    if (_dartDebug) {
      print('[   DART   ] $msg');
    }
  }

  /// Host to Flutter logging API
  @override
  void logFromHost(String msg) {
    print('[  NATIVE  ] $msg');
  }

  /// Enable debug logging.
  ///
  /// For native logging set [native] to `true` and for dart set [dart] to `true`.
  static Future<void> debug({
    bool dart = false,
    bool native = false,
    bool sdk = false,
  }) async {
    _dartDebug = dart;
    try {
      await TwilioConversations().pluginApi.debug(native, sdk);
    } catch (e) {
      TwilioConversations.log(
          'TwilioConversations::debug => Caught Exception: $e');
    }
  }
}
