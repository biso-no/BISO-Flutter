## Keep AndroidX Browser, CustomTabs, and Activity result APIs used by url_launcher's Custom Tabs flow
-keep class androidx.browser.** { *; }
-dontwarn androidx.browser.**

-keep class androidx.activity.result.** { *; }
-dontwarn androidx.activity.result.**

## Keep Kotlin metadata to avoid reflective issues
-keep class kotlin.Metadata { *; }

