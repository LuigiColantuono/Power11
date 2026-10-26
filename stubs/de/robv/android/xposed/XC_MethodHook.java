// Compile-time stub of the Xposed API, provided at runtime by LSPosed/Vector
package de.robv.android.xposed;

import java.lang.reflect.Member;

public abstract class XC_MethodHook {
    protected void beforeHookedMethod(MethodHookParam param) throws Throwable {
    }

    protected void afterHookedMethod(MethodHookParam param) throws Throwable {
    }

    public static final class MethodHookParam {
        public Member method;
        public Object thisObject;
        public Object[] args;

        public Object getResult() {
            throw new UnsupportedOperationException();
        }

        public void setResult(Object result) {
            throw new UnsupportedOperationException();
        }
    }
}
