using Ryujinx.Common.Logging;
using System;
using System.Diagnostics;
using System.Threading;

namespace Ryujinx.Common.Diagnostics
{
    public static class ReadbackDecisionTelemetry
    {
        private sealed class OperationMetrics
        {
            private readonly string _name;
            private long _dequeued;
            private long _queuedTicks;
            private long _queueDepthTotal;
            private long _calls;
            private long _callTicks;
            private long _lastLog = Stopwatch.GetTimestamp();

            public OperationMetrics(string name) => _name = name;

            public void Dequeued(long ticks, int depth, ulong identity, string boundary = null)
            {
                if (!GezinjinxPerformanceMode.DetailedTelemetry) return;
                Interlocked.Increment(ref _dequeued);
                Interlocked.Add(ref _queuedTicks, ticks);
                Interlocked.Add(ref _queueDepthTotal, depth);
                TryLog(identity, boundary);
            }

            public void Called(long ticks, ulong identity)
            {
                if (!GezinjinxPerformanceMode.DetailedTelemetry) return;
                Interlocked.Increment(ref _calls);
                Interlocked.Add(ref _callTicks, ticks);
                TryLog(identity, null);
            }

            private void TryLog(ulong identity, string boundary)
            {
                long now = Stopwatch.GetTimestamp();
                long last = Volatile.Read(ref _lastLog);
                if (now - last < Stopwatch.Frequency * 5 || Interlocked.CompareExchange(ref _lastLog, now, last) != last) return;
                Logger.Info?.Print(LogClass.Gpu, FormattableString.Invariant(
                    $"[NEOV2-SUBMISSION-DIAGNOSTICS] operation={_name} identity={identity} boundary={boundary} dequeued={Interlocked.Exchange(ref _dequeued, 0)} queueDepthTotal={Interlocked.Exchange(ref _queueDepthTotal, 0)} queuedMs={Interlocked.Exchange(ref _queuedTicks, 0) * 1000.0 / Stopwatch.Frequency:F2} calls={Interlocked.Exchange(ref _calls, 0)} callMs={Interlocked.Exchange(ref _callTicks, 0) * 1000.0 / Stopwatch.Frequency:F2}"));
            }
        }

        private static readonly OperationMetrics Submit = new("Submit");
        private static readonly OperationMetrics Present = new("Present");
        private static readonly OperationMetrics SparseBind = new("BindSparse");
        private static readonly OperationMetrics Drain = new("Drain");

        public static void RecordSubmitDequeued(long ticks, int depth, ulong timelineValue) => Submit.Dequeued(ticks, depth, timelineValue);
        public static void RecordPresentDequeued(long ticks, int depth, ulong sequence) => Present.Dequeued(ticks, depth, sequence);
        public static void RecordSparseBindDequeued(long ticks, int depth, ulong sequence) => SparseBind.Dequeued(ticks, depth, sequence);
        public static void RecordDrainDequeued(long ticks, int depth, ulong sequence, string boundary) => Drain.Dequeued(ticks, depth, sequence, boundary);
        public static void RecordQueueSubmit(long ticks, ulong timelineValue) => Submit.Called(ticks, timelineValue);
        public static void RecordQueuePresent(long ticks, ulong sequence) => Present.Called(ticks, sequence);
        public static void RecordQueueBindSparse(long ticks, ulong sequence) => SparseBind.Called(ticks, sequence);

        public static void RecordSubmissionBoundary(string boundary, bool cancelled)
        {
            if (GezinjinxPerformanceMode.DetailedTelemetry)
            {
                Logger.Info?.Print(LogClass.Gpu, $"[NEOV2-SUBMISSION-BOUNDARY] boundary={boundary} cancelled={cancelled}");
            }
        }

        public static void RecordSubmissionStateTransition(string previous, string current, ulong sequence)
        {
            if (GezinjinxPerformanceMode.DetailedTelemetry)
            {
                Logger.Info?.Print(LogClass.Gpu, $"[NEOV2-SUBMISSION-STATE] previous={previous} current={current} sequence={sequence}");
            }
        }

        // Fault diagnostics remain available even when detailed sampling is off.
        public static void RecordSubmissionFault(string operation, string error, ulong timelineValue, ulong sequence, int queueDepth)
        {
            Logger.Error?.Print(LogClass.Gpu,
                $"[NEOV2-SUBMISSION-FAULT] operation={operation} timeline={timelineValue} sequence={sequence} queueDepth={queueDepth} error={error}");
            GezinjinxGuestStallTelemetry.LogProgress();
        }
    }
}
