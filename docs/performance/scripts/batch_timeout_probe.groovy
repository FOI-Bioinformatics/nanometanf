// Measures how long a PARTIAL batch waits under the shipped fixed-rate
// sampler in BatchUtils.batchWithTimeout, against the "reset the timer on
// each flush" alternative audit F10 recommended. This is what withdrew F10:
// resetting the clock is worse on both mean and maximum wait.
//
// It reimplements the two TIMER POLICIES rather than calling
// batchWithTimeout, because that method takes a Nextflow channel
// (ch_input.subscribe) and so cannot run outside Nextflow. The shipped policy
// here mirrors lib/BatchUtils.groovy exactly: scheduleAtFixedRate(task,
// periodMs, periodMs) with no clock reset in drainAndEmit.
//
//   java -cp groovy-4.x.jar:gpars-1.2.1.jar \
//        groovy.ui.GroovyMain docs/performance/scripts/batch_timeout_probe.groovy
import groovyx.gpars.dataflow.DataflowQueue
import groovyx.gpars.dataflow.operator.PoisonPill
import java.util.concurrent.ConcurrentLinkedDeque
import java.util.concurrent.atomic.AtomicLong

long PERIOD = 2000L     // stands in for batch_timeout, scaled down
long SPACING = 300L     // one file every 300 ms: a slow barcode
int  N = 20
int  BATCH = 1000       // high, so only the timer ever flushes

// --- shipped behaviour: scheduleAtFixedRate, never reset -------------------
def runFixedRate = { ->
    def buffer = new ConcurrentLinkedDeque(); def lock = new Object()
    def waits = []
    def drain = {
        if (buffer.isEmpty()) return
        long now = System.currentTimeMillis()
        def item = buffer.pollFirst()
        while (item != null) { waits << (now - item); item = buffer.pollFirst() }
    }
    def timer = new Timer('fixed', true)
    timer.scheduleAtFixedRate({ synchronized(lock) { drain() } } as TimerTask, PERIOD, PERIOD)
    N.times { synchronized(lock) { buffer.add(System.currentTimeMillis()) }; Thread.sleep(SPACING) }
    Thread.sleep(PERIOD + 200); synchronized(lock) { drain() }; timer.cancel()
    return waits
}

// --- F10's suggestion: the clock restarts at each flush, so a pending batch
// --- waits the full period measured from when it started filling ----------
def runResetOnFlush = { ->
    def buffer = new ConcurrentLinkedDeque(); def lock = new Object()
    def waits = []; def oldest = new AtomicLong(0L)
    def drain = {
        if (buffer.isEmpty()) return
        long now = System.currentTimeMillis()
        def item = buffer.pollFirst()
        while (item != null) { waits << (now - item); item = buffer.pollFirst() }
        oldest.set(0L)
    }
    long tick = Math.max(50L, (long)(PERIOD / 10))
    def timer = new Timer('reset', true)
    timer.scheduleAtFixedRate({
        synchronized(lock) {
            long o = oldest.get()
            if (o > 0L && System.currentTimeMillis() - o >= PERIOD) drain()
        }
    } as TimerTask, tick, tick)
    N.times {
        synchronized(lock) {
            long t = System.currentTimeMillis()
            if (buffer.isEmpty()) oldest.set(t)
            buffer.add(t)
        }
        Thread.sleep(SPACING)
    }
    Thread.sleep(PERIOD + 400); synchronized(lock) { drain() }; timer.cancel()
    return waits
}

def report = { String label, List w ->
    printf "%-26s n=%2d  mean=%5d ms  min=%4d  max=%5d  p50=%5d%n",
        label, w.size(), (long)(w.sum() / w.size()), w.min(), w.max(), w.sort(false)[(int)(w.size()/2)]
}
println "period=${PERIOD} ms, one item every ${SPACING} ms, ${N} items, count threshold never reached"
println "-" * 78
report('shipped (fixed-rate)', runFixedRate())
report('F10 (reset on flush)', runResetOnFlush())
println "-" * 78
