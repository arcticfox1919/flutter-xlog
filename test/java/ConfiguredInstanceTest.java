import com.tencent.mars.xlog.Log;
import com.tencent.mars.xlog.Xlog;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/** Host contract tests; replaces JNI with a capture backend, not the Java APIs. */
public final class ConfiguredInstanceTest {
    private static final String PUBLIC_KEY =
            "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
            + "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8";

    private static final class CaptureXlog extends Xlog {
        XLogConfig received;
        int opens;
        boolean fail;
        long lastWrite;
        long lastFlush;
        long lastLevel;
        long lastConsole;
        long lastFiles;
        String lastRelease;
        String message;

        @Override public long newXlogInstance(XLogConfig config) {
            received = config;
            opens++;
            return fail ? 0 : 100 + opens;
        }
        @Override public long getXlogInstance(String prefix) {
            return "native_owned".equals(prefix) ? 42 : 0;
        }
        @Override public int getLogLevel(long pointer) { lastLevel = pointer; return LEVEL_VERBOSE; }
        @Override public void releaseXlogInstance(String prefix) { lastRelease = prefix; }
        @Override public void setConsoleLogOpen(long pointer, boolean open) { lastConsole = pointer; }
        // This extra method also compiles against the SDK without the file-list API.
        public String[] getFilePathFromTimeSpan(long pointer, int days, String prefix) {
            lastFiles = pointer; return new String[0];
        }
        @Override public void appenderFlush(long pointer, boolean sync) { lastFlush = pointer; }
        @Override public void logI(long pointer, String tag, String file, String function,
                int line, int pid, long tid, long mainTid, String text) {
            lastWrite = pointer;
            message = text;
        }
    }

    private static Xlog.XLogConfig config(String prefix) {
        Xlog.XLogConfig config = new Xlog.XLogConfig();
        config.nameprefix = prefix;
        config.logdir = "/logs/" + prefix;
        config.cachedir = "/cache/" + prefix;
        config.level = Xlog.LEVEL_WARNING;
        config.mode = Xlog.AppednerModeSync;
        config.pubkey = PUBLIC_KEY;
        config.compressmode = Xlog.ZSTD_MODE;
        config.compresslevel = -2;
        config.cachedays = 5;
        return config;
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static void rejects(Class<? extends Throwable> expected, Xlog.XLogConfig config) {
        try {
            Log.openLogInstance(config);
        } catch (Throwable error) {
            if (expected.isInstance(error)) return;
            throw new AssertionError("Unexpected failure: " + error, error);
        }
        throw new AssertionError("Expected " + expected.getName());
    }

    private static void checkKotlin(CaptureXlog backend) throws Exception {
        Log.setLogImp(backend);
        Class<?> facade = Class.forName("xyz.bczl.xlog.XLog");
        Object singleton = facade.getField("INSTANCE").get(null);
        Class<?> levelType = Class.forName("xyz.bczl.xlog.LogLevel");
        Object warning = levelType.getField("WARNING").get(null);
        Method factory = facade.getMethod("openInstance", String.class, String.class,
                String.class, String.class, levelType, int.class, int.class, int.class, int.class,
                long.class, long.class);
        Object writer = factory.invoke(singleton, "/kcache", "/klogs", "kotlin_config",
                PUBLIC_KEY, warning, Xlog.AppednerModeSync, Xlog.ZSTD_MODE, 4, 9,
                (1L << 33) + 123, (1L << 32) + 456);
        Xlog.XLogConfig config = backend.received;
        check(config.level == Xlog.LEVEL_WARNING && config.mode == Xlog.AppednerModeSync
                && "/kcache".equals(config.cachedir) && "/klogs".equals(config.logdir)
                && "kotlin_config".equals(config.nameprefix) && PUBLIC_KEY.equals(config.pubkey)
                && config.compressmode == Xlog.ZSTD_MODE && config.compresslevel == 4
                && config.cachedays == 9 && config.maxFileSizeBytes == (1L << 33) + 123
                && config.maxAliveTimeSeconds == (1L << 32) + 456,
                "Kotlin must forward the complete creation configuration without narrowing");
        long expectedTarget = 100 + backend.opens;
        writer.getClass().getMethod("i", String.class, String.class)
                .invoke(writer, "HTTP", "Kotlin 100% %s literal");
        check(backend.lastWrite == expectedTarget && "Kotlin 100% %s literal".equals(backend.message),
                "Kotlin writer must address the configured instance without formatting plain text");
        int before = backend.opens;
        Object reused = factory.invoke(singleton, "/other-cache", "/other-logs", "kotlin_config",
                "invalid-but-ignored", warning, 0, 1, 3, 0, -1L, 0L);
        reused.getClass().getMethod("i", String.class, String.class).invoke(reused, "HTTP", "reused");
        check(backend.opens == before && backend.lastWrite == expectedTarget,
                "Kotlin must reuse the native instance without applying new settings");
        Method oldFactory = facade.getMethod("openInstance", String.class, String.class,
                String.class, levelType, int.class, int.class);
        oldFactory.invoke(singleton, "/kcache", "/klogs", "kotlin_legacy", warning, 0, 2);
        check(backend.received.pubkey.length() == 0 && backend.received.compressmode == Xlog.ZLIB_MODE
                && backend.received.cachedays == 2 && backend.received.maxFileSizeBytes == 0
                && backend.received.maxAliveTimeSeconds == 864000, "Kotlin defaults changed");
        System.out.println("PASS: actual compiled Kotlin factory, all fields, target, errors and old overload");
    }

    public static void main(String[] args) throws Exception {
        CaptureXlog backend = new CaptureXlog();
        Log.setLogImp(backend);
        Xlog.XLogConfig networkConfig = config("network");
        networkConfig.maxFileSizeBytes = (1L << 33) + 123;
        networkConfig.maxAliveTimeSeconds = (1L << 32) + 456;
        Log.LogInstance network = Log.openLogInstance(networkConfig);
        check(backend.received.maxFileSizeBytes == (1L << 33) + 123
                && backend.received.maxAliveTimeSeconds == (1L << 32) + 456,
                "File policy fields were narrowed or dropped");
        check(backend.received == networkConfig, "Xlog must pass the complete config to JNI");
        check(PUBLIC_KEY.equals(backend.received.pubkey), "Encryption key must not be discarded");
        check(backend.received.compressmode == Xlog.ZSTD_MODE
                && backend.received.compresslevel == -2, "Compression settings must be retained");
        check(backend.received.cachedays == 5 && backend.received.mode == Xlog.AppednerModeSync
                && backend.received.level == Xlog.LEVEL_WARNING
                && "/cache/network".equals(backend.received.cachedir)
                && "/logs/network".equals(backend.received.logdir), "Other config fields were changed");
        check(Log.getLogInstance("network") == network, "Configured instances must be registered");
        network.i("Tag", "100% %s literal", (Object[]) null);
        check(backend.lastWrite == 101 && "100% %s literal".equals(backend.message), "Wrong target/payload");
        network.appenderFlushSync();
        check(backend.lastFlush == 101, "Management must address the same configured instance");

        Xlog.XLogConfig paymentConfig = config("payment");
        paymentConfig.pubkey = "";
        paymentConfig.compressmode = Xlog.ZLIB_MODE;
        Log.LogInstance payment = Log.openLogInstance(paymentConfig);
        payment.i("Order", "paid", (Object[]) null);
        check(backend.lastWrite == 102 && backend.received.pubkey.length() == 0
                && backend.received.compressmode == Xlog.ZLIB_MODE, "Instance settings/routing mixed");

        int before = backend.opens;
        check(Log.openLogInstance(config("network")) == network, "Existing instance must be reused");
        check(backend.opens == before, "Reusing a prefix must not enter the creation backend");

        backend.fail = true;
        rejects(IllegalStateException.class, config("failed"));
        check(Log.getLogInstance("failed") == null, "Zero/native failure must not be registered");
        backend.fail = false;
        check(Log.openLogInstance(config("failed")) != null, "Failed creation must be retryable");

        before = backend.opens;
        rejects(IllegalArgumentException.class, null);
        Xlog.XLogConfig invalid = config("");
        rejects(IllegalArgumentException.class, invalid);
        invalid = config("missing_path");
        invalid.logdir = null;
        rejects(IllegalArgumentException.class, invalid);
        invalid = config("invalid_key");
        invalid.pubkey = "invalid";
        rejects(IllegalArgumentException.class, invalid);
        invalid = config("invalid_mode");
        invalid.mode = 2;
        rejects(IllegalArgumentException.class, invalid);
        invalid = config("invalid_compression");
        invalid.compressmode = -1;
        rejects(IllegalArgumentException.class, invalid);
        invalid = config("invalid_level");
        invalid.level = Xlog.LEVEL_NONE + 1;
        rejects(IllegalArgumentException.class, invalid);
        invalid.level = -1;
        rejects(IllegalArgumentException.class, invalid);
        invalid = config("invalid_size");
        invalid.maxFileSizeBytes = -1;
        rejects(IllegalArgumentException.class, invalid);
        invalid = config("invalid_retention");
        invalid.maxAliveTimeSeconds = 86399;
        rejects(IllegalArgumentException.class, invalid);
        check(backend.opens == before, "Invalid configuration reached the backend");

        Log.LogInstance legacy = Log.openLogInstance(2, 0, "/cache", "/logs", "legacy", 3);
        check(backend.received.pubkey.length() == 0 && backend.received.compressmode == Xlog.ZLIB_MODE
                && backend.received.cachedays == 3, "Legacy defaults changed");
        before = backend.opens;
        check(legacy == Log.openLogInstance(2, 0, "/cache", "/logs", "legacy", 3)
                && backend.opens == before, "Legacy idempotent open changed");

        // Native handles belong to their creator, even after global backend replacement.
        CaptureXlog replacement = new CaptureXlog();
        Log.setLogImp(replacement);
        backend.lastWrite = 0;
        network.i("Tag", "owned by original backend", (Object[]) null);
        check(backend.lastWrite == 101 && replacement.lastWrite == 0,
                "An existing native handle was passed to the replacement backend");
        network.getLogLevel();
        check(backend.lastLevel == 101 && replacement.lastLevel == 0, "Level query changed backend");
        network.appenderFlushSync();
        check(backend.lastFlush == 101 && replacement.lastFlush == 0, "Flush changed backend");
        network.setConsoleLogOpen(false);
        check(backend.lastConsole == 101 && replacement.lastConsole == 0, "Console setting changed backend");
        try {
            network.getClass().getMethod("getFilesFromTimeSpan", int.class).invoke(network, 0);
            check(backend.lastFiles == 101 && replacement.lastFiles == 0, "File query changed backend");
        } catch (NoSuchMethodException sdkWithoutFileList) { /* Android SDK has no file-list API. */ }
        Log.setLogImp(null);
        backend.lastWrite = 0;
        network.i("Tag", "global backend disabled", (Object[]) null);
        check(backend.lastWrite == 101, "Disabling the global backend disabled an owned instance");
        backend.lastFlush = 0;
        Log.appenderFlush();
        check(backend.lastFlush != 0, "Global flush skipped owned instances without a global backend");
        Log.closeLogInstance("network");
        check("network".equals(backend.lastRelease), "Release must use the creator backend");
        backend.lastWrite = 0;
        network.i("Tag", "closed", (Object[]) null);
        check(backend.lastWrite == 0, "Closed instance revived after backend replacement");
        Log.setLogImp(backend);

        final int[] legacyCalls = {0};
        Log.LogImp oldBackend = (Log.LogImp) Proxy.newProxyInstance(Log.class.getClassLoader(),
                new Class<?>[] {Log.LogImp.class}, new InvocationHandler() {
            @Override public Object invoke(Object proxy, Method method, Object[] arguments) {
                if (method.getName().equals("openLogInstance")) { legacyCalls[0]++; return 73L; }
                if (method.getName().equals("getXlogInstance")) return 0L;
                if (method.getName().equals("getLogLevel")) return 0;
                return null;
            }
        });
        Log.setLogImp(oldBackend);
        rejects(UnsupportedOperationException.class, config("unsupported"));
        check(legacyCalls[0] == 0, "Unsupported backend must not silently drop encryption settings");
        Log.openLogInstance(2, 0, "/cache", "/logs", "custom_backend", 0);
        check(legacyCalls[0] == 1, "Original third-party LogImp must remain usable");
        if (args.length != 0) checkKotlin(backend);
        Log.setLogImp(null);
        Log.appenderClose();
        check(Log.getLogInstance("payment") == null && Log.getLogInstance("legacy") == null,
                "Global close skipped owned instances without a global backend");
        System.out.println("PASS: creator backend routing and management after replacement/null,"
                + " configured routing, all fields, duplicate prefixes, creation failure,"
                + " validation, legacy defaults, and third-party backend compatibility");
    }
}
