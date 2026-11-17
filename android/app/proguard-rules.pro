# VOICEVOX コア（Java API）
# ネイティブ側（JNI）がクラス名・フィールド名・メソッド名で直接さわり、
# AudioQuery などは Gson で JSON に変換するため、縮小（R8）で名前を変えたり
# 削ったりしないようにする。
-keep class jp.hiroshiba.voicevoxcore.** { *; }
-keepclassmembers class jp.hiroshiba.voicevoxcore.** { *; }
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-dontwarn jp.hiroshiba.voicevoxcore.**

# Gson（VOICEVOX コアが使う）
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-dontwarn javax.annotation.**
