#!/usr/bin/env python3
"""What does ONE MORE concurrent kraken2 fork cost in RAM?

That is the question params.kraken2_task_memory_gb answers. On a local
executor Nextflow's per-task `memory` is admission control, so if N forks share
a memory-mapped index the reservation should be the per-fork MARGINAL cost, not
the whole database -- otherwise the executor admits fewer forks than
max_classification_forks asks for (audit F5,
docs/performance/realtime_many_barcodes_audit_2026-10-26.md).

Two measurement traps this script exists to avoid:

  * With ONE process, file-backed mapped pages count as PRIVATE -- nothing else
    maps them -- so sharing is invisible below two concurrent forks.
  * RSS counts a shared page once per process, so summing RSS across forks
    triple-counts the index. PSS splits a shared page across its mappers, so
    the sum of PSS is the real footprint and its slope against N is the
    marginal cost per fork.

Measured 2026-10-27 against two real databases, with the page cache warmed as
KRAKEN2_DB_PRELOAD warms it:

  viral          619 MB hash, 27,069 taxa:  +54 M/fork at 1 thread, +139 M at 4
  standard_08gb  8.0 GB hash, 50,333 taxa:  +54 M/fork at 1 thread, +149 M at 4

Flat across a 13x larger index, because the index is shared and the private
part is read buffers and per-thread state: roughly 50 MB plus 25 MB per thread.
Without memory mapping one fork took 7.7 GB private -- the whole index -- which
is the cost the unscaled reservation is sized for and is correct only then.

  python3 docs/performance/scripts/kraken2_fork_memory_probe.py <db> <reads.fastq.gz> <label>
"""
import subprocess, sys, time

def rollup(pid):
    try:
        with open(f"/proc/{pid}/smaps_rollup") as fh:
            d = {}
            for line in fh:
                k, _, v = line.partition(':')
                v = v.strip()
                if v.endswith('kB'):
                    d[k] = int(v[:-2].strip())
            return d
    except (FileNotFoundError, ProcessLookupError, OSError):
        return None

def run(db, reads, n, threads, mmap):
    cmd = ['kraken2', '--db', db, '--threads', str(threads),
           '--report', '/dev/null', '--output', '/dev/null', reads]
    if mmap:
        cmd.insert(1, '--memory-mapping')
    procs = [subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
             for _ in range(n)]
    t0 = time.time()
    peak = dict(total_pss=0, total_rss=0, total_private=0, total_shared=0, samples=0)
    while any(p.poll() is None for p in procs):
        pss = rss = priv = shar = 0
        alive = 0
        for p in procs:
            r = rollup(p.pid)
            if not r:
                continue
            alive += 1
            pss  += r.get('Pss', 0)
            rss  += r.get('Rss', 0)
            priv += r.get('Private_Clean', 0) + r.get('Private_Dirty', 0)
            shar += r.get('Shared_Clean', 0) + r.get('Shared_Dirty', 0)
        # sum first, then peak: taking the max of each key independently and
        # adding them afterwards reports a total that never existed
        if alive == n:
            peak['samples'] += 1
            peak['total_pss']     = max(peak['total_pss'], pss)
            peak['total_rss']     = max(peak['total_rss'], rss)
            peak['total_private'] = max(peak['total_private'], priv)
            peak['total_shared']  = max(peak['total_shared'], shar)
        time.sleep(0.02)
    for p in procs:
        p.wait()
    peak['wall'] = time.time() - t0
    return peak

db, reads, label = sys.argv[1], sys.argv[2], sys.argv[3]
print(f"  {label}")
print(f"    {'mmap':<5} {'forks':>5} {'sum RSS':>9} {'sum PSS':>9} {'sum priv':>9} "
      f"{'sum shared':>11} {'PSS/fork':>9} {'wall':>7}")
for mmap in (True, False):
    prev = None
    for n in (1, 2, 4):
        r = run(db, reads, n, 1, mmap)
        if r['samples'] == 0:
            print(f"    {'yes' if mmap else 'no':<5} {n:>5}   (never saw all {n} alive together)")
            continue
        mb = lambda k: r[k] / 1024
        marginal = ''
        if prev is not None:
            dn = n - prev[0]
            marginal = f"  (+{(mb('total_pss') - prev[1]) / dn:.0f}M per extra fork)"
        print(f"    {'yes' if mmap else 'no':<5} {n:>5} {mb('total_rss'):8.0f}M {mb('total_pss'):8.0f}M "
              f"{mb('total_private'):8.0f}M {mb('total_shared'):10.0f}M "
              f"{mb('total_pss')/n:8.0f}M {r['wall']:6.1f}s{marginal}")
        prev = (n, mb('total_pss'))
