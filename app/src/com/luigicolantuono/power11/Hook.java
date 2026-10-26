package com.luigicolantuono.power11;

import android.app.Instrumentation;
import android.content.Context;
import android.content.res.Resources;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.provider.Settings;

import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * Customizes SystemUI's AOSP power menu (GlobalActionsDialogLite):
 * item order, grid columns and extra reboot entries.
 *
 * Config is read from Settings.Global on every menu open, so changes made by
 * the KernelSU module apply without restarting anything. SystemUI cannot
 * reboot to recovery/bootloader itself, so those entries create a
 * power11_<cmd> file in SystemUI's data dir and the module's root watcher
 * runs the command.
 */
public class Hook implements IXposedHookLoadPackage {
    private static final String TAG = "Power11: ";
    private static final String SELF = "com.luigicolantuono.power11";
    private static final String SYSTEMUI = "com.android.systemui";
    private static final String DIALOG = "com.android.systemui.globalactions.GlobalActionsDialogLite";

    private static final String KEY_ITEMS = "power11_items";
    private static final String KEY_COLUMNS = "power11_columns";

    // Extra entries: key -> label, drawable in this APK
    private static final Map<String, String[]> CUSTOM = new LinkedHashMap<>();

    static {
        CUSTOM.put("recovery", new String[]{"Recovery", "ic_p11_recovery"});
        CUSTOM.put("bootloader", new String[]{"Bootloader", "ic_p11_bootloader"});
        CUSTOM.put("systemui", new String[]{"SystemUI", "ic_p11_systemui"});
        CUSTOM.put("softreboot", new String[]{"Soft reboot", "ic_p11_softreboot"});
    }

    // AOSP action class name fragment -> menu key
    private static final String[][] AOSP_CLASSES = {
            {"Emergency", "emergency"}, {"LockDown", "lockdown"}, {"ShutDown", "power"},
            {"Restart", "restart"}, {"Screenshot", "screenshot"}, {"BugReport", "bugreport"},
            {"AirplaneMode", "airplane"}, {"SilentMode", "silent"},
    };

    // Message resource name -> menu key, for anonymous action classes
    private static final String[][] AOSP_MESSAGES = {
            {"global_action_settings", "settings"}, {"global_action_emergency", "emergency"},
            {"global_action_lockdown", "lockdown"}, {"global_action_power_off", "power"},
            {"global_action_restart", "restart"}, {"global_action_screenshot", "screenshot"},
            {"global_action_bug_report", "bugreport"}, {"global_actions_toggle_airplane_mode", "airplane"},
    };

    private final Map<Object, String> customActions = Collections.synchronizedMap(new WeakHashMap<>());
    private ClassLoader classLoader;
    private Context context;
    private int columnsResId;
    private volatile int columns;

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) {
        // Main process only: the power menu never shows in :screenshot and friends
        if (!SYSTEMUI.equals(lpparam.packageName) || !SYSTEMUI.equals(lpparam.processName)) return;
        classLoader = lpparam.classLoader;

        hook(Instrumentation.class, "callApplicationOnCreate", new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                if (context != null) return;
                context = (Context) param.args[0];
                columnsResId = context.getResources().getIdentifier("power_menu_lite_max_columns", "integer", SYSTEMUI);
                writeMarker("power11_alive", String.valueOf(Process.myPid()));
            }
        });

        Class<?> dialog;
        Class<?> restart;
        try {
            dialog = classLoader.loadClass(DIALOG);
            restart = classLoader.loadClass(DIALOG + "$RestartAction");
        } catch (ClassNotFoundException e) {
            XposedBridge.log(TAG + "AOSP power menu classes not found: " + e);
            return;
        }

        // Which AOSP actions SystemUI builds
        hook(dialog, "getDefaultActions", new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                List<String> items = readItems();
                if (items == null) return;
                List<String> aosp = new ArrayList<>();
                for (String key : items) {
                    if (!CUSTOM.containsKey(key)) aosp.add(key);
                }
                param.setResult(aosp.toArray(new String[0]));
            }
        });

        // Show everything in the grid: no overflow menu, no "power options" group
        hook(dialog, "getMaxShownPowerItems", new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                if (readItems() != null) param.setResult(99);
            }
        });

        hook(dialog, "createActionItems", new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                try {
                    reorder(param.thisObject, restart);
                } catch (Throwable t) {
                    XposedBridge.log(TAG + "reorder failed");
                    XposedBridge.log(t);
                }
            }
        });

        hook(Resources.class, "getInteger", new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                if (columns > 0 && columnsResId != 0 && (int) param.args[0] == columnsResId) {
                    param.setResult(columns);
                }
            }
        });

        // Our entries are RestartAction instances with a different icon, label and action
        hook(restart, "onPress", new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                String key = customActions.get(param.thisObject);
                if (key == null) return;
                run(key);
                param.setResult(null);
            }
        });
        hook(restart, "onLongPress", new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                if (customActions.containsKey(param.thisObject)) param.setResult(false);
            }
        });

        XposedBridge.log(TAG + "hooked " + DIALOG);
    }

    private static void hook(Class<?> clazz, String method, XC_MethodHook callback) {
        if (XposedBridge.hookAllMethods(clazz, method, callback).isEmpty()) {
            XposedBridge.log(TAG + "method not found: " + clazz.getName() + "#" + method);
        }
    }

    // ------------------------------------------------------------- config

    /** Configured items in menu order, or null to leave the ROM default. */
    private List<String> readItems() {
        if (context == null) return null;
        String value = Settings.Global.getString(context.getContentResolver(), KEY_ITEMS);
        if (value == null || value.trim().isEmpty()) return null;
        List<String> items = new ArrayList<>();
        for (String s : value.split(",")) {
            if (!s.trim().isEmpty()) items.add(s.trim());
        }
        return items.isEmpty() ? null : items;
    }

    // ------------------------------------------------------------- menu

    @SuppressWarnings("unchecked")
    private void reorder(Object dialog, Class<?> restartClass) throws Exception {
        List<String> items = readItems();
        columns = Settings.Global.getInt(context.getContentResolver(), KEY_COLUMNS, 0);
        if (items == null) return;

        List<Object> mItems = (List<Object>) getField(dialog, "mItems");
        List<Object> overflow = (List<Object>) getField(dialog, "mOverflowItems");
        List<Object> power = (List<Object>) getField(dialog, "mPowerItems");

        List<Object> built = new ArrayList<>(mItems);
        if (overflow != null) {
            built.addAll(overflow);
            overflow.clear();
        }

        Map<String, Object> byKey = new LinkedHashMap<>();
        List<Object> unknown = new ArrayList<>();
        for (Object action : built) {
            if (action.getClass().getName().contains("PowerOptions")) {
                // Power off and restart grouped under one button: take them back out
                if (power != null) {
                    for (Object p : power) {
                        String key = keyOf(p);
                        if (key != null) byKey.putIfAbsent(key, p);
                    }
                    power.clear();
                }
                continue;
            }
            String key = keyOf(action);
            if (key != null && !byKey.containsKey(key)) {
                byKey.put(key, action);
            } else {
                unknown.add(action);
            }
        }

        List<Object> result = new ArrayList<>();
        for (String key : items) {
            if (CUSTOM.containsKey(key)) {
                Object action = createCustom(dialog, restartClass, key);
                if (action != null) result.add(action);
            } else if (byKey.containsKey(key)) {
                result.add(byKey.get(key));
            }
        }
        // Selected AOSP actions we could not identify keep their place at the end
        result.addAll(unknown);

        mItems.clear();
        mItems.addAll(result);
    }

    private String keyOf(Object action) {
        String name = action.getClass().getName();
        for (String[] pair : AOSP_CLASSES) {
            if (name.contains(pair[0])) return pair[1];
        }
        try {
            Method m = findMethod(action.getClass(), "getMessageResId");
            int id = (int) m.invoke(action);
            if (id != 0) {
                String entry = context.getResources().getResourceEntryName(id);
                for (String[] pair : AOSP_MESSAGES) {
                    if (pair[0].equals(entry)) return pair[1];
                }
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    private Object createCustom(Object dialog, Class<?> restartClass, String key) {
        try {
            Constructor<?> ctor = restartClass.getDeclaredConstructors()[0];
            ctor.setAccessible(true);
            Class<?>[] types = ctor.getParameterTypes();
            Object[] args = new Object[types.length];
            for (int i = 0; i < types.length; i++) {
                if (types[i].isInstance(dialog)) args[i] = dialog;
                else if (types[i] == boolean.class) args[i] = false;
                else if (types[i] == int.class) args[i] = 0;
            }
            Object action = ctor.newInstance(args);

            String[] spec = CUSTOM.get(key);
            setField(action, "mMessage", spec[0]);
            Drawable icon = loadIcon(spec[1]);
            if (icon != null) setField(action, "mIcon", icon);

            customActions.put(action, key);
            return action;
        } catch (Throwable t) {
            XposedBridge.log(TAG + "cannot create " + key);
            XposedBridge.log(t);
            return null;
        }
    }

    private Drawable loadIcon(String name) {
        try {
            Context self = context.createPackageContext(SELF, Context.CONTEXT_IGNORE_SECURITY);
            int id = self.getResources().getIdentifier(name, "drawable", SELF);
            return id == 0 ? null : self.getDrawable(id);
        } catch (Throwable t) {
            XposedBridge.log(TAG + "icon " + name + ": " + t);
            return null;
        }
    }

    // ------------------------------------------------------------- actions

    private void run(String key) {
        if ("systemui".equals(key)) {
            // Let the dialog close first
            new Handler(Looper.getMainLooper()).postDelayed(() -> Process.killProcess(Process.myPid()), 250);
            return;
        }
        // Picked up by the module's root watcher (see watcher.sh)
        File file = new File(dataDir(), "power11_" + key);
        file.delete();
        writeMarker(file.getName(), "");
    }

    private File dataDir() {
        return context.createDeviceProtectedStorageContext().getDataDir();
    }

    private void writeMarker(String name, String content) {
        try (FileOutputStream out = new FileOutputStream(new File(dataDir(), name))) {
            out.write(content.getBytes());
        } catch (Throwable t) {
            XposedBridge.log(TAG + "cannot write " + name + ": " + t);
        }
    }

    // ------------------------------------------------------------- reflection

    private static Field findField(Class<?> clazz, String name) throws NoSuchFieldException {
        for (Class<?> c = clazz; c != null; c = c.getSuperclass()) {
            try {
                Field f = c.getDeclaredField(name);
                f.setAccessible(true);
                return f;
            } catch (NoSuchFieldException ignored) {
            }
        }
        throw new NoSuchFieldException(clazz.getName() + "." + name);
    }

    private static Method findMethod(Class<?> clazz, String name) throws NoSuchMethodException {
        for (Class<?> c = clazz; c != null; c = c.getSuperclass()) {
            for (Method m : c.getDeclaredMethods()) {
                if (m.getName().equals(name) && m.getParameterTypes().length == 0) {
                    m.setAccessible(true);
                    return m;
                }
            }
        }
        throw new NoSuchMethodException(clazz.getName() + "#" + name);
    }

    private static Object getField(Object obj, String name) {
        try {
            return findField(obj.getClass(), name).get(obj);
        } catch (Throwable t) {
            return null;
        }
    }

    private static void setField(Object obj, String name, Object value) throws Exception {
        findField(obj.getClass(), name).set(obj, value);
    }
}
