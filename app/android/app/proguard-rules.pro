# Flutter's own engine/embedding classes are referenced from native code and
# must survive shrinking regardless of plugin-specific rules below.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# sqflite and flutter_sms_inbox query Android content providers / SQLite via
# reflection-adjacent cursor APIs in a few plugin-internal classes.
-keep class com.tekartik.sqflite.** { *; }

# Play Core split-install classes are referenced by Flutter's deferred
# components support even though this app doesn't use deferred components;
# missing-class warnings here are expected and safe to ignore, not a sign
# the build needs this library added.
-dontwarn com.google.android.play.core.**
