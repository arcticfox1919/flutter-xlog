import com.tencent.mars.xlog.Log;
import com.tencent.mars.xlog.Xlog;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Future;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Bounded callback/concurrency regressions against the production Java APIs. */
public final class InstanceLifecycleTest {
    private static final class Backend extends Xlog {
        final AtomicInteger creations = new AtomicInteger();
        final AtomicInteger writes = new AtomicInteger();
        final java.util.concurrent.ConcurrentHashMap<Long, String> prefixes =
                new java.util.concurrent.ConcurrentHashMap<Long, String>();
        volatile String blockedPhase = "";
        volatile String blockedPrefix = "";
        volatile String failedLookup = "";
        volatile String failedCreate = "";
        volatile String zeroCreate = "";
        volatile String failedRelease = "";
        volatile boolean failCloseAll;
        volatile boolean mutateFlush;
        volatile boolean callbacks;
        volatile CountDownLatch entered = new CountDownLatch(1);
        volatile CountDownLatch resume = new CountDownLatch(1);

        void block(String phase, String prefix) {
            entered = new CountDownLatch(1);
            resume = new CountDownLatch(1);
            blockedPhase = phase;
            blockedPrefix = prefix;
        }
        void call(String phase, final String prefix) {
            if (callbacks) {
                // This worker needs the registry monitor. Waiting here deadlocks
                // the previous implementation, which called the backend under it.
                Future<Log.LogInstance> read = start(new Callable<Log.LogInstance>() {
                    public Log.LogInstance call() { return Log.getLogInstance(prefix); }
                });
                result(read);
            }
            if (blockedPhase.equals(phase) && blockedPrefix.equals(prefix)) {
                entered.countDown();
                await(resume);
            }
        }
        @Override public long getXlogInstance(String prefix) {
            call("lookup", prefix);
            if (failedLookup.equals(prefix)) throw new IllegalStateException("lookup failed");
            return 0;
        }
        @Override public long newXlogInstance(XLogConfig config) {
            int handle = creations.incrementAndGet();
            call("create", config.nameprefix);
            if (failedCreate.equals(config.nameprefix)) throw new IllegalStateException("creation failed");
            if (zeroCreate.equals(config.nameprefix)) return 0;
            prefixes.put((long) handle, config.nameprefix);
            return handle;
        }
        @Override public void releaseXlogInstance(String prefix) {
            call("release", prefix);
            if (failedRelease.equals(prefix)) throw new IllegalStateException("release failed");
        }
        @Override public void appenderClose() {
            call("closeAll", "");
            if (failCloseAll) throw new IllegalStateException("global close failed");
        }
        @Override public void appenderFlush(long pointer, boolean sync) {
            call("flush", "");
            if (pointer != 0 && mutateFlush) {
                mutateFlush = false;
                Log.closeLogInstance("flush_a".equals(prefixes.get(pointer)) ? "flush_b" : "flush_a");
            }
        }
        @Override public int getLogLevel(long pointer) { return LEVEL_VERBOSE; }
        @Override public void logI(long pointer, String tag, String file, String function,
                int line, int pid, long tid, long mainTid, String text) { writes.incrementAndGet(); }
    }

    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    private static void await(CountDownLatch latch) {
        try {
            check(latch.await(5, TimeUnit.SECONDS), "lifecycle gate timed out");
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw new AssertionError(error);
        }
    }
    private static <T> Future<T> start(Callable<T> action) {
        FutureTask<T> future = new FutureTask<T>(action);
        Thread thread = new Thread(future, "instance-lifecycle-test");
        thread.setDaemon(true);
        thread.start();
        return future;
    }
    private static <T> T result(Future<T> future) {
        try {
            return future.get(2, TimeUnit.SECONDS);
        } catch (Exception error) {
            throw new AssertionError("Blocked registry callback or failed operation", error);
        }
    }
    private static Xlog.XLogConfig config(String prefix) {
        Xlog.XLogConfig config = new Xlog.XLogConfig();
        config.logdir = "/logs";
        config.nameprefix = prefix;
        return config;
    }
    private static void busyOpen(final String prefix, final boolean legacy) {
        result(start(new Callable<Void>() {
            public Void call() {
                try {
                    if (legacy) Log.openLogInstance(2, 0, "/cache", "/logs", prefix, 0);
                    else Log.openLogInstance(config(prefix));
                } catch (IllegalStateException expected) { return null; }
                throw new AssertionError("Concurrent open did not fail fast: " + prefix);
            }
        }));
    }
    private static void busyClose(final String prefix) {
        result(start(new Callable<Void>() {
            public Void call() {
                try { Log.closeLogInstance(prefix); }
                catch (IllegalStateException expected) { return null; }
                throw new AssertionError("Concurrent close did not fail fast");
            }
        }));
    }
    private static void failedOpen(String prefix, boolean legacy) {
        try {
            if (legacy) Log.openLogInstance(2, 0, "/cache", "/logs", prefix, 0);
            else Log.openLogInstance(config(prefix));
        } catch (IllegalStateException expected) {
            check(Log.getLogInstance(prefix) == null, "Failed instance was published");
            return;
        }
        throw new AssertionError("Expected creation failure");
    }

    public static void main(String[] args) {
        final Backend backend = new Backend();
        Log.setLogImp(backend);
        final Log.LogInstance ready = Log.openLogInstance(config("ready"));
        backend.callbacks = true;
        Log.openLogInstance(config("callbacks")); // lookup and creation callbacks
        Log.closeLogInstance("callbacks");       // native release callback
        Log.appenderFlush();                     // global and instance callbacks

        backend.block("create", "slow");
        Future<Log.LogInstance> slow = start(new Callable<Log.LogInstance>() {
            public Log.LogInstance call() { return Log.openLogInstance(config("slow")); }
        });
        await(backend.entered);
        try {
            check(Log.getLogInstance("slow") == null, "Pending creation was published early");
            check(result(start(new Callable<Log.LogInstance>() {
                public Log.LogInstance call() { return Log.getLogInstance("ready"); }
            })) == ready, "Ready lookup blocked behind native creation");
            busyOpen("slow", false);
            busyOpen("slow", true);
            busyClose("slow");
            int before = backend.creations.get();
            Log.openLogInstance(config("independent"));
            check(backend.creations.get() == before + 1, "Unrelated creation was serialized in Java");
            before = backend.writes.get();
            ready.i("Tag", "write during another creation", (Object[]) null);
            check(backend.writes.get() == before + 1, "Ready logging blocked behind registry lifecycle");
        } finally { backend.resume.countDown(); }
        check(result(slow) == Log.getLogInstance("slow"), "Completed creation was not published");

        backend.failedLookup = "lookup_failure";
        check(Log.openLogInstance(config("lookup_failure")) != null,
                "Configured creation must delegate native reuse to the native factory");
        backend.failedLookup = "";
        Log.openLogInstance(config("lookup_failure"));
        backend.failedCreate = "create_failure";
        failedOpen("create_failure", false);
        backend.failedCreate = "";
        Log.openLogInstance(config("create_failure"));
        backend.zeroCreate = "zero_failure";
        failedOpen("zero_failure", false);
        backend.zeroCreate = "";
        Log.openLogInstance(config("zero_failure"));
        backend.zeroCreate = "legacy_failure";
        failedOpen("legacy_failure", true);
        backend.zeroCreate = "";
        Log.openLogInstance(2, 0, "/cache", "/logs", "legacy_failure", 0);

        final Log.LogInstance closing = Log.openLogInstance(config("closing"));
        backend.block("release", "closing");
        Future<Void> close = start(new Callable<Void>() {
            public Void call() { Log.closeLogInstance("closing"); return null; }
        });
        await(backend.entered);
        try {
            check(Log.getLogInstance("closing") == null, "Closing instance remained discoverable");
            busyOpen("closing", false);
            busyOpen("closing", true);
            busyClose("closing");
            int before = backend.writes.get();
            closing.i("Tag", "closed", (Object[]) null);
            check(backend.writes.get() == before, "Invalidated Java handle still wrote");
        } finally { backend.resume.countDown(); }
        result(close);
        Log.openLogInstance(config("closing"));

        final Log.LogInstance failedClose = Log.openLogInstance(config("release_failure"));
        backend.failedRelease = "release_failure";
        try {
            Log.closeLogInstance("release_failure");
            throw new AssertionError("Expected release failure");
        } catch (IllegalStateException expected) {
            check(Log.getLogInstance("release_failure") == null, "Failed release resurrected a Java handle");
        }
        backend.failedRelease = "";
        Log.openLogInstance(config("release_failure"));
        int before = backend.writes.get();
        failedClose.i("Tag", "invalidated", (Object[]) null);
        check(backend.writes.get() == before, "Old handle revived after a failed close");

        backend.failCloseAll = true;
        try {
            Log.appenderClose();
            throw new AssertionError("Expected global close failure");
        } catch (IllegalStateException expected) { /* global reservation must be reset */ }
        backend.failCloseAll = false;
        Log.openLogInstance(config("after_failed_close_all"));

        backend.block("closeAll", "");
        Future<Void> all = start(new Callable<Void>() {
            public Void call() { Log.appenderClose(); return null; }
        });
        await(backend.entered);
        try {
            check(Log.getLogInstance("ready") == ready, "Global close holds registry lock across JNI");
            busyOpen("during_close_all", false);
            busyClose("ready");
            result(start(new Callable<Void>() {
                public Void call() {
                    try { Log.appenderClose(); }
                    catch (IllegalStateException expected) { return null; }
                    throw new AssertionError("Overlapping global close should fail fast");
                }
            }));
        } finally { backend.resume.countDown(); }
        result(all);
        check(Log.getLogInstance("ready") == null && Log.getLogInstance("slow") == null,
                "Global close skipped entries or invalidated its map iterator");
        Log.openLogInstance(config("flush_a"));
        Log.openLogInstance(config("flush_b"));
        backend.mutateFlush = true;
        Log.appenderFlush();
        check((Log.getLogInstance("flush_a") == null) != (Log.getLogInstance("flush_b") == null),
                "Flush did not tolerate a callback modifying the registry snapshot");
        System.out.println("PASS: unlocked backend callbacks, pending visibility, concurrent operations,"
                + " ready writes, failure rollback, close/reopen and global-close coordination");
    }
}
