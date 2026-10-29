# JNI reads these fields by their original names. R8 cannot see those reads,
# so preserve all fields, including configuration values that look constant.
-keep class com.tencent.mars.xlog.Xlog$XLogConfig { *; }
-keep class com.tencent.mars.xlog.Xlog$XLoggerInfo { *; }
