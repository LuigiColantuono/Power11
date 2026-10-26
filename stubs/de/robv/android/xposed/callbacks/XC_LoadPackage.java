// Compile-time stub of the Xposed API, provided at runtime by LSPosed/Vector
package de.robv.android.xposed.callbacks;

public abstract class XC_LoadPackage {
    public static final class LoadPackageParam {
        public String packageName;
        public String processName;
        public ClassLoader classLoader;
        public boolean isFirstApplication;
    }
}
