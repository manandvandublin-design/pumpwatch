# ML Kit text recognition: only the Latin model is bundled; ignore the other language packs.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Direct USB (UVC) camera driver
-keep class com.jiangdg.** { *; }
-keep interface com.jiangdg.** { *; }
-keep class com.chenyeju.** { *; }
-keep class com.serenegiant.** { *; }
-dontwarn com.jiangdg.**
-dontwarn com.serenegiant.**
-dontwarn com.chenyeju.**
