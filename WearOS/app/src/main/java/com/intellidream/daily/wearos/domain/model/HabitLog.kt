package com.intellidream.daily.wearos.domain.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import java.util.UUID

object FlexibleMetadataSerializer : KSerializer<String?> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("FlexibleMetadata", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: String?) {
        if (value == null) {
            encoder.encodeNull()
        } else {
            encoder.encodeString(value)
        }
    }

    override fun deserialize(decoder: Decoder): String? {
        val jsonDecoder = decoder as? JsonDecoder ?: return try { decoder.decodeString() } catch (_: Exception) { null }
        val element = jsonDecoder.decodeJsonElement()
        return when (element) {
            is JsonNull -> null
            is JsonPrimitive -> element.content
            is JsonObject -> element.toString()
            is JsonArray -> element.toString()
        }
    }
}

object FlexibleDoubleSerializer : KSerializer<Double> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("FlexibleDouble", PrimitiveKind.DOUBLE)

    override fun serialize(encoder: Encoder, value: Double) {
        encoder.encodeDouble(value)
    }

    override fun deserialize(decoder: Decoder): Double {
        val jsonDecoder = decoder as? JsonDecoder ?: return try { decoder.decodeDouble() } catch (_: Exception) { 0.0 }
        val element = jsonDecoder.decodeJsonElement()
        return when (element) {
            is JsonPrimitive -> {
                element.doubleOrNull ?: element.intOrNull?.toDouble() ?: element.content.toDoubleOrNull() ?: 0.0
            }
            else -> 0.0
        }
    }
}

@Serializable
data class HabitLog(
    val id: String = UUID.randomUUID().toString(),
    val user_id: String? = null,
    val habit_type: String,
    @Serializable(with = FlexibleDoubleSerializer::class)
    val value: Double = 0.0,
    val unit: String = "",
    val logged_at: String = "",
    @Serializable(with = FlexibleMetadataSerializer::class)
    val metadata: String? = null,
    val is_deleted: Boolean = false
)
