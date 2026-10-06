# ── ML Kit (text recognition, face detection) ─────────────────────────────
# ML Kit discovers its internal components by reflection (ComponentRegistrar
# classes named in merged manifest metadata). R8 full mode strips them, and
# in release builds TextRecognition.getClient() then throws
#   NullPointerException: ... Object.getClass() on a null object reference
# which surfaced as OCR "Something went wrong" (production audit 2026-09).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face_bundled.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google_mlkit_** { *; }
-keep class com.google_mlkit_**.** { *; }

# The plugin references CJK recognizers, which we do not bundle (APK size).
# Their scripts report "unavailable" at runtime.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ── PDFium (pdfrx) uses JNI/FFI lookups by name ──────────────────────────
-keep class io.github.espresso3389.** { *; }

# ── ML Kit barcode (mobile_scanner, bundled model) ───────────────────────
# Same reflection-based component discovery as text/face above.
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }

# ── flutter_local_notifications (expiry reminders) ───────────────────────
# Scheduled notifications are persisted with Gson and restored by the boot
# receiver; R8 must keep the generic signatures and the plugin's models,
# otherwise reminders are lost after a reboot in release builds only.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# camera, local_auth (androidx.biometric), the document scanner and Play
# Billing ship their own consumer rules. SQLCipher is loaded through Dart
# FFI (package:sqlite3 build hook), so there are no JVM classes to keep.
