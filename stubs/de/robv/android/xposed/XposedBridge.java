// Compile-time stub of the Xposed API, provided at runtime by LSPosed/Vector
package de.robv.android.xposed;

import java.util.Set;

public final class XposedBridge {
    public static Set<XC_MethodHook> hookAllMethods(Class<?> hookClass, String methodName, XC_MethodHook callback) {
        throw new UnsupportedOperationException();
    }

    public static void log(String text) {
        throw new UnsupportedOperationException();
    }

    public static void log(Throwable t) {
        throw new UnsupportedOperationException();
    }
}
