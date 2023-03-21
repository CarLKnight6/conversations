package twilio.flutter.twilio_conversations

import ConversationMethods
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import com.twilio.conversations.ConversationListener
import com.twilio.conversations.ConversationsClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import twilio.flutter.twilio_conversations.listeners.ClientListener
import twilio.flutter.twilio_conversations.methods.ConversationClientMethods
import twilio.flutter.twilio_conversations.methods.MessageMethods
import twilio.flutter.twilio_conversations.methods.ParticipantMethods
import twilio.flutter.twilio_conversations.methods.PluginMethods
import twilio.flutter.twilio_conversations.methods.UserMethods

/** TwilioConversationsPlugin */
class TwilioConversationsPlugin : FlutterPlugin {
    companion object {
        @Suppress("unused")
        @JvmStatic
        lateinit var instance: TwilioConversationsPlugin

        @JvmStatic
        lateinit var currentFlutterPluginBinding: FlutterPlugin.FlutterPluginBinding

        // Flutter > Host APIs
        @JvmStatic
        val pluginApi: Api.PluginApi = PluginMethods()

        @JvmStatic
        val conversationClientApi: Api.ConversationClientApi = ConversationClientMethods()

        @JvmStatic
        val conversationApi: Api.ConversationApi = ConversationMethods()

        @JvmStatic
        val participantApi: Api.ParticipantApi = ParticipantMethods()

        @JvmStatic
        val messageApi: Api.MessageApi = MessageMethods()

        @JvmStatic
        val userApi: Api.UserApi = UserMethods()

        // Host > Flutter APIs
        @JvmStatic
        lateinit var flutterClientApi: Api.FlutterConversationClientApi

        @JvmStatic
        lateinit var flutterLoggingApi: Api.FlutterLoggingApi

        @JvmStatic
        var client: ConversationsClient? = null

        lateinit var messenger: BinaryMessenger

        lateinit var applicationContext: Context

        var clientListener: ClientListener? = null

        var conversationListeners: HashMap<String, ConversationListener> = hashMapOf()

        var handler = Handler(Looper.getMainLooper())
        var nativeDebug: Boolean = false
        val LOG_TAG = "Twilio_Conversations"

        private var initialized = false

        @JvmStatic
        fun debug(msg: String) {
            if (nativeDebug) {
                Log.d(LOG_TAG, msg)
                handler.post {
                    flutterLoggingApi.logFromHost(msg) { }
                }
            }
        }
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        if (initialized) {
            Log.d(LOG_TAG, "TwilioConversationsPlugin.onAttachedToEngine: already initialized")
            messenger = currentFlutterPluginBinding.binaryMessenger
        } else {
            Log.d(LOG_TAG, "TwilioConversationsPlugin.onAttachedToEngine")
            messenger = flutterPluginBinding.binaryMessenger
            currentFlutterPluginBinding = flutterPluginBinding
        }

        instance = this
        applicationContext = flutterPluginBinding.applicationContext

        Api.PluginApi.setup(messenger, pluginApi)
        Api.ConversationClientApi.setup(messenger, conversationClientApi)
        Api.ConversationApi.setup(messenger, conversationApi)
        Api.ParticipantApi.setup(messenger, participantApi)
        Api.UserApi.setup(messenger, userApi)
        Api.MessageApi.setup(messenger, messageApi)
        flutterClientApi = Api.FlutterConversationClientApi(messenger)
        flutterLoggingApi = Api.FlutterLoggingApi(messenger)

        initialized = true
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        debug("TwilioConversationsPlugin.onDetachedFromEngine")
        initialized = false
    }
}
