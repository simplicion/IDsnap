# ML Kit text recognition: the plugin references CJK recognizers, which we do
# not bundle (APK size). Their scripts report "unavailable" at runtime.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
