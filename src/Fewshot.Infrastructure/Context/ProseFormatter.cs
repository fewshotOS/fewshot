using System.Text;
using Fewshot.Core.Interfaces;
using Fewshot.Core.Models;

namespace Fewshot.Infrastructure.Context;

public class ProseFormatter : IContextFormatter
{
    public string FormatP1(CurrentStateContext s)
    {
        var sb = new StringBuilder();
        sb.Append($"You are currently working with Joe on the {s.Project} project.");
        if (!string.IsNullOrEmpty(s.Environment))
            sb.Append($" The environment is {s.Environment}.");
        if (!string.IsNullOrEmpty(s.Branch))
            sb.Append($" The active branch is {s.Branch}.");

        if (s.ChangedLast24h.Count > 0)
            sb.Append($" In the last 24 hours, the following files were modified: {string.Join(", ", s.ChangedLast24h)}.");
        if (s.ChangedLast7d.Count > 0)
            sb.Append($" In the last 7 days, additional changes were made to: {string.Join(", ", s.ChangedLast7d)}.");
        if (s.SprintItems.Count > 0)
        {
            var grouped = s.SprintItems.GroupBy(i => i.Status);
            var parts = grouped.Select(g => $"{g.Key}: {string.Join(", ", g.Select(i => i.Description))}");
            sb.Append($" Sprint status — {string.Join("; ", parts)}.");
        }
        if (s.RecentErrors.Count > 0)
        {
            var errorDescs = s.RecentErrors.Select(e => $"{e.Description} ({e.OccurrenceCount}× in {e.Timeframe})");
            sb.Append($" Recent errors include: {string.Join("; ", errorDescs)}.");
        }
        if (s.LastDeployTime.HasValue)
            sb.Append($" Last deployment: {s.LastDeployTime:g} ({s.LastDeployStatus ?? "unknown"}).");

        return sb.ToString();
    }

    public string FormatP2(List<SemanticMemory> memories)
    {
        if (memories.Count == 0) return string.Empty;

        var sb = new StringBuilder();
        sb.AppendLine("From your shared history with Joe, here are the most relevant past experiences:");

        foreach (var m in memories.OrderByDescending(m => m.RelevanceScore))
        {
            sb.AppendLine();
            sb.Append(m.Summary);
            if (!string.IsNullOrEmpty(m.Solution))
                sb.Append($" The approach used was: {m.Solution}.");
            if (!string.IsNullOrEmpty(m.OutcomeLabel))
                sb.Append($" Outcome: {m.OutcomeLabel}.");
        }

        return sb.ToString().TrimEnd();
    }

    public string FormatP3(List<AntiPattern> antiPatterns)
    {
        if (antiPatterns.Count == 0) return string.Empty;

        var sb = new StringBuilder();
        sb.AppendLine("IMPORTANT — The following approaches have been tried and failed. Do not suggest these under any circumstances:");

        for (var i = 0; i < antiPatterns.Count; i++)
        {
            var ap = antiPatterns[i];
            sb.AppendLine();
            sb.Append($"{i + 1}. Do not use {ap.Pattern}. {ap.Reason}.");
            if (!string.IsNullOrEmpty(ap.ErrorCode))
                sb.Append($" (Error: {ap.ErrorCode})");
        }

        return sb.ToString().TrimEnd();
    }

    public string FormatP4(List<Preference> preferences)
    {
        if (preferences.Count == 0) return string.Empty;

        var sb = new StringBuilder();
        sb.AppendLine("Based on your history working with Joe, you know the following about his preferences:");

        var explicitPrefs = preferences.Where(p => p.IsExplicit).ToList();
        var inferredPrefs = preferences.Where(p => !p.IsExplicit).OrderByDescending(p => p.ConfidenceScore).ToList();

        foreach (var p in explicitPrefs)
            sb.AppendLine($"Joe explicitly prefers {p.Key}: {p.Value} (category: {p.Category}).");

        if (inferredPrefs.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("From observed patterns (not explicitly stated):");
            foreach (var p in inferredPrefs)
            {
                var confidence = p.ConfidenceScore switch
                {
                    >= 0.8 => "high confidence",
                    >= 0.6 => "moderate confidence",
                    _ => "lower confidence"
                };
                sb.AppendLine($"Joe appears to prefer {p.Key}: {p.Value} ({confidence}).");
            }
        }

        return sb.ToString().TrimEnd();
    }

    public string FormatP5(ProjectFacts facts)
    {
        if (facts.Projects.Count == 0 && facts.Endpoints.Count == 0 &&
            facts.KnownGoodPatterns.Count == 0 && facts.PinnedVersions.Count == 0)
            return string.Empty;

        var sb = new StringBuilder();
        sb.AppendLine("For reference, here is Joe's project registry and known facts:");

        foreach (var p in facts.Projects)
        {
            sb.Append($"The {p.Name} project");
            if (!string.IsNullOrEmpty(p.Stack))
                sb.Append($" runs on {p.Stack}");
            if (!string.IsNullOrEmpty(p.HostingInfo))
                sb.Append($", hosted on {p.HostingInfo}");
            sb.Append('.');
            if (!string.IsNullOrEmpty(p.Notes))
                sb.Append($" {p.Notes.TrimEnd('.')}.");
            sb.AppendLine();
        }

        if (facts.Endpoints.Count > 0)
        {
            sb.AppendLine();
            foreach (var (key, val) in facts.Endpoints)
                sb.AppendLine($"The {key} endpoint is: {val}.");
        }

        if (facts.KnownGoodPatterns.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine($"Known good patterns include: {string.Join("; ", facts.KnownGoodPatterns)}.");
        }

        if (facts.PinnedVersions.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine($"Pinned versions: {string.Join(", ", facts.PinnedVersions.Select(kv => $"{kv.Key} {kv.Value}"))}.");
        }

        return sb.ToString().TrimEnd();
    }
}
