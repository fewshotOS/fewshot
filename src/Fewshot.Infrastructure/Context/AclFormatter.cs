using System.Text;
using Fewshot.Core.Interfaces;
using Fewshot.Core.Models;

namespace Fewshot.Infrastructure.Context;

public class AclFormatter : IContextFormatter
{
    public string FormatP1(CurrentStateContext s)
    {
        var sb = new StringBuilder();
        sb.AppendLine("§p1·state");

        var projectLine = $"  →project: {s.Project}";
        if (!string.IsNullOrEmpty(s.Environment)) projectLine += $"|env:{s.Environment}";
        if (!string.IsNullOrEmpty(s.Branch)) projectLine += $"|branch:{s.Branch}";
        sb.AppendLine(projectLine);

        if (s.ChangedLast24h.Count > 0)
            sb.AppendLine($"  →changed·24h: {string.Join(", ", s.ChangedLast24h)}");
        if (s.ChangedLast7d.Count > 0)
            sb.AppendLine($"  →changed·7d: {string.Join(", ", s.ChangedLast7d)}");
        if (s.SprintItems.Count > 0)
        {
            var grouped = s.SprintItems.GroupBy(i => i.Status);
            foreach (var g in grouped)
                sb.AppendLine($"  →sprint·{g.Key.ToLower()}: {string.Join(", ", g.Select(i => i.Count > 1 ? $"{i.Description}(×{i.Count})" : i.Description))}");
        }
        if (s.RecentErrors.Count > 0)
        {
            foreach (var e in s.RecentErrors)
                sb.AppendLine($"  →error[{e.Timeframe}×{e.OccurrenceCount}]: {e.Description}");
        }
        if (s.LastDeployTime.HasValue)
            sb.AppendLine($"  →deploy·last: {s.LastDeployTime:g}|{s.LastDeployStatus ?? "unknown"}");

        sb.AppendLine("§end");
        return sb.ToString().TrimEnd();
    }

    public string FormatP2(List<SemanticMemory> memories)
    {
        if (memories.Count == 0) return string.Empty;

        var sb = new StringBuilder();
        sb.AppendLine("§p2·memory");

        foreach (var m in memories.OrderByDescending(m => m.RelevanceScore))
        {
            var tags = !string.IsNullOrEmpty(m.Tags) ? $"|{m.Tags}" : "";
            sb.AppendLine($"  →recall[{m.RelevanceScore:F2}]: {m.Summary.Replace("\n", " ")}{tags}");
            if (!string.IsNullOrEmpty(m.Solution))
                sb.AppendLine($"    §approach: {m.Solution.Replace("\n", " ")}");
            if (!string.IsNullOrEmpty(m.OutcomeLabel))
                sb.AppendLine($"    §outcome: {m.OutcomeLabel}");
        }

        sb.AppendLine("§end");
        return sb.ToString().TrimEnd();
    }

    public string FormatP3(List<AntiPattern> antiPatterns)
    {
        if (antiPatterns.Count == 0) return string.Empty;

        var sb = new StringBuilder();
        sb.AppendLine("§p3·never");

        foreach (var ap in antiPatterns)
        {
            sb.AppendLine($"  →block: {ap.Pattern}");
            var reason = ap.Reason;
            if (!string.IsNullOrEmpty(ap.ErrorCode)) reason += $"|error:{ap.ErrorCode}";
            sb.AppendLine($"    ×reason: {reason}");
        }

        sb.AppendLine("§end");
        return sb.ToString().TrimEnd();
    }

    public string FormatP4(List<Preference> preferences)
    {
        if (preferences.Count == 0) return string.Empty;

        var sb = new StringBuilder();
        sb.AppendLine("§p4·prefs");

        var explicitPrefs = preferences.Where(p => p.IsExplicit).ToList();
        var inferredPrefs = preferences.Where(p => !p.IsExplicit).OrderByDescending(p => p.ConfidenceScore).ToList();

        if (explicitPrefs.Count > 0)
        {
            sb.AppendLine("  →explicit");
            foreach (var p in explicitPrefs)
                sb.AppendLine($"    {p.Category.ToLower()}/{p.Key}: {p.Value}");
        }

        foreach (var p in inferredPrefs)
            sb.AppendLine($"  →inferred[{p.ConfidenceScore:F2}]: {p.Category.ToLower()}/{p.Key}={p.Value}");

        sb.AppendLine("§end");
        return sb.ToString().TrimEnd();
    }

    public string FormatP5(ProjectFacts facts)
    {
        if (facts.Projects.Count == 0 && facts.Endpoints.Count == 0 &&
            facts.KnownGoodPatterns.Count == 0 && facts.PinnedVersions.Count == 0)
            return string.Empty;

        var sb = new StringBuilder();
        sb.AppendLine("§p5·facts");

        if (facts.Projects.Count > 0)
        {
            sb.AppendLine("  →registry");
            foreach (var p in facts.Projects)
            {
                var line = $"    {p.Name}: {p.Stack}";
                if (!string.IsNullOrEmpty(p.HostingInfo)) line += $"|{p.HostingInfo}";
                if (!string.IsNullOrEmpty(p.Notes)) line += $"|{p.Notes}";
                sb.AppendLine(line);
            }
        }

        if (facts.Endpoints.Count > 0)
        {
            sb.AppendLine("  →endpoints");
            foreach (var (key, val) in facts.Endpoints)
                sb.AppendLine($"    {key}: {val}");
        }

        if (facts.KnownGoodPatterns.Count > 0)
        {
            sb.AppendLine("  →patterns·known-good");
            foreach (var p in facts.KnownGoodPatterns)
                sb.AppendLine($"    {p}");
        }

        if (facts.PinnedVersions.Count > 0)
        {
            sb.AppendLine("  →versions·pinned");
            sb.AppendLine($"    {string.Join("|", facts.PinnedVersions.Select(kv => $"{kv.Key}:{kv.Value}"))}");
        }

        sb.AppendLine("§end");
        return sb.ToString().TrimEnd();
    }
}
