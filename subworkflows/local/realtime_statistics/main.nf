/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: REALTIME_STATISTICS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Real-time statistics generation for nanopore data monitoring

    Generates two types of statistics:
    1. SNAPSHOT: Statistics for the current batch only (incremental)
    2. CUMULATIVE: Running totals and trends across all processed batches

    Features:
    - Batch-level metrics calculation
    - Cumulative trend analysis
    - Performance monitoring
    - Quality threshold alerting
    - JSON and HTML report generation
----------------------------------------------------------------------------------------
*/

include { GENERATE_SNAPSHOT_STATS } from '../../../modules/local/generate_snapshot_stats/main'
include { UPDATE_CUMULATIVE_STATS } from '../../../modules/local/update_cumulative_stats/main'
include { GENERATE_REALTIME_REPORT } from '../../../modules/local/generate_realtime_report/main'

workflow REALTIME_STATISTICS {

    take:
    ch_batches      // channel: [ val(batch_meta), [ file_metas ] ]
    stats_config    // val: statistics configuration

    main:

    ch_versions = Channel.empty()

    //
    // Generate snapshot statistics for each batch
    //
    GENERATE_SNAPSHOT_STATS (
        ch_batches,
        stats_config
    )
    ch_versions = ch_versions.mix(GENERATE_SNAPSHOT_STATS.out.versions)

    //
    // Update cumulative statistics with each new batch
    //
    // The update receives EVERY snapshot seen so far and recomputes the session
    // totals from that set. It used to receive the prior cumulative_state.json
    // read out of params.outdir inside this map, which raced the task that
    // writes it: two concurrent batches both saw the same prior and each
    // published prior + own, so the later publish dropped the earlier batch
    // from the session totals. Nothing here may read the publish directory;
    // BatchSeriesAccumulator keeps the series in the head process, and the
    // maxForks 1 on UPDATE_CUMULATIVE_STATS (conf/modules.config) makes the
    // most complete result also the last one published.
    //
    def snapshot_series = new BatchSeriesAccumulator()
    ch_cumulative_input = GENERATE_SNAPSHOT_STATS.out.snapshot_stats
        .map { batch_meta, snapshot_stats ->
            [ batch_meta, snapshot_series.accumulate('session', batch_meta.batch_id, snapshot_stats) ]
        }

    UPDATE_CUMULATIVE_STATS (
        ch_cumulative_input,
        stats_config
    )
    ch_versions = ch_versions.mix(UPDATE_CUMULATIVE_STATS.out.versions)

    //
    // Generate real-time HTML reports
    //
    ch_report_input = GENERATE_SNAPSHOT_STATS.out.snapshot_stats
        .join(UPDATE_CUMULATIVE_STATS.out.cumulative_stats, by: 0)
        .map { batch_meta, snapshot_stats, cumulative_stats ->
            [ batch_meta, snapshot_stats, cumulative_stats ]
        }

    GENERATE_REALTIME_REPORT (
        ch_report_input,
        stats_config
    )
    ch_versions = ch_versions.mix(GENERATE_REALTIME_REPORT.out.versions)

    emit:
    snapshot_stats = GENERATE_SNAPSHOT_STATS.out.snapshot_stats      // channel: [ val(batch_meta), path(snapshot.json) ]
    cumulative_stats = UPDATE_CUMULATIVE_STATS.out.cumulative_stats  // channel: [ val(batch_meta), path(cumulative.json) ]
    realtime_reports = GENERATE_REALTIME_REPORT.out.html             // channel: [ val(batch_meta), path(report.html) ]
    alert_notifications = UPDATE_CUMULATIVE_STATS.out.alerts         // channel: [ val(batch_meta), path(alerts.json) ]
    versions = ch_versions                                            // channel: [ path(versions.yml) ]
}
