using Ryujinx.Common.Logging;
using System;
using System.Diagnostics;

namespace Ryujinx.Common.Diagnostics
{
    // Records host progress only. A successful submit is not GPU completion.
    public static class GezinjinxGuestStallTelemetry
    {
        private static readonly object Sync = new();
        private static long _lastSubmit;
        private static long _lastPresent;
        private static ulong _submitTimeline;
        private static ulong _submitSequence;
        private static ulong _presentSequence;

        public static void RecordVkSubmit(ulong timelineValue, ulong sequence)
        {
            if (!GezinjinxPerformanceMode.DetailedTelemetry) return;
            lock (Sync)
            {
                _lastSubmit = Stopwatch.GetTimestamp();
                _submitTimeline = timelineValue;
                _submitSequence = sequence;
            }
        }

        public static void RecordPresent(ulong sequence)
        {
            if (!GezinjinxPerformanceMode.DetailedTelemetry) return;
            lock (Sync)
            {
                _lastPresent = Stopwatch.GetTimestamp();
                _presentSequence = sequence;
            }
        }

        public static void LogProgress()
        {
            if (!GezinjinxPerformanceMode.DetailedTelemetry) return;
            string message;
            lock (Sync)
            {
                long now = Stopwatch.GetTimestamp();
                double submitAge = _lastSubmit == 0 ? -1 : (now - _lastSubmit) * 1000.0 / Stopwatch.Frequency;
                double presentAge = _lastPresent == 0 ? -1 : (now - _lastPresent) * 1000.0 / Stopwatch.Frequency;
                message = FormattableString.Invariant(
                    $"[NEOV2-HOST-PROGRESS] submitTimeline={_submitTimeline} submitSequence={_submitSequence} presentSequence={_presentSequence} submitAgeMs={submitAge:F2} presentAgeMs={presentAge:F2}");
            }
            Logger.Info?.Print(LogClass.Gpu, message);
        }
    }
}
