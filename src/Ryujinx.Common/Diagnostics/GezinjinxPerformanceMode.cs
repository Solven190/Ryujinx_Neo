using System;

namespace Ryujinx.Common.Diagnostics
{
    // The NEOV2 Vulkan port retains this API name from Gezinjinx. This switch
    // controls diagnostics only; it must not change scheduling or GPU work.
    public static class GezinjinxPerformanceMode
    {
        public static bool DetailedTelemetry { get; } =
            Environment.GetEnvironmentVariable("RYUJINX_DETAILED_TELEMETRY") is "1" ||
            string.Equals(Environment.GetEnvironmentVariable("RYUJINX_DETAILED_TELEMETRY"), "true", StringComparison.OrdinalIgnoreCase);
    }
}
