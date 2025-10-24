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

  /// Create a [ConversationClient] with retry logic.
  Future<ConversationClient?> create({
    required String jwtToken,
    Properties properties = const Properties(),
    int retryCount = 0,
  }) async {
    assert(jwtToken.isNotEmpty);

    log('create conversation plugin => token2: ${jwtToken.substring(0, 50)}...');
    log('Attempt ${retryCount + 1}');

    conversationClient = ConversationClient();

    try {
      // Add delay to ensure channel is ready
      await Future.delayed(const Duration(milliseconds: 500));

      log('Calling native create()...');

      final ConversationClientData result =
          await pluginApi.create(jwtToken, properties.toPigeon()).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Native create() timed out');
        },
      );

      log('✅ Native create() succeeded');
      conversationClient
          ?.updateFromMap(Map<String, dynamic>.from(result.encode() as Map));

      return conversationClient;
    } on PlatformException catch (e) {
      log('❌ PlatformException: ${e.code} - ${e.message}');

      // Retry on channel-error up to 3 times
      if ((e.code == 'channel-error' ||
              e.message?.contains('Unable to establish connection') == true) &&
          retryCount < 3) {
        log('⏳ Retrying (${retryCount + 1}/3)...');
        await Future.delayed(const Duration(seconds: 2));
        conversationClient = null;
        return create(
          jwtToken: jwtToken,
          properties: properties,
          retryCount: retryCount + 1,
        );
      }

      conversationClient = null;
      log('❌ create => Error: $e');
      rethrow;
    } catch (e) {
      log('❌ Unexpected error: $e');
      conversationClient = null;
      rethrow;
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

  static void log(dynamic msg) {
    if (_dartDebug) {
      print('[   DART   ] $msg');
    }
  }

  @override
  void logFromHost(String msg) {
    print('[  NATIVE  ] $msg');
  }

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
