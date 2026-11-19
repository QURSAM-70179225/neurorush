# Flutter and plugin classes are kept by their own consumer rules.
# Keep annotations and generic signatures used by Firebase / Play Billing.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
# Google Play Core (deferred components) is referenced by the Flutter engine but not used.
-dontwarn com.google.android.play.core.**
