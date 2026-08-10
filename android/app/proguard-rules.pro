# ONNX Runtime's native (JNI) code constructs Java objects like NodeInfo
# directly by class/constructor name. R8 can't see those native call sites,
# so without this keep rule it strips "unused" members (e.g. NodeInfo's
# constructor), causing a NoSuchMethodError at runtime in release builds.
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
