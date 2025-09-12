# Keep record plugin classes
-keep class com.llfbandit.record.** { *; }
-keep interface com.llfbandit.record.** { *; }

# Keep Flutter plugin registration
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# Keep audio related classes
-keep class android.media.** { *; }

# General Flutter rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep Google Play Core classes (to fix R8 missing classes error)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep Play Store related classes
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Keep Flutter deferred components classes
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# Additional rules to prevent obfuscation issues
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep all native method names and the names of their classes.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Flutter engine classes
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.embedding.android.** { *; }
