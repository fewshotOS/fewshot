using Fewshot.Core.Enums;

namespace Fewshot.Core.Models;

/// <summary>
/// Assembled context ready for system prompt injection.
/// </summary>
public class ContextInjectionResult
{
    public string AssembledContext { get; set; } = string.Empty;
    public int TotalTokens { get; set; }
    public string ContextHash { get; set; } = string.Empty;
    public List<ContextSegment> Segments { get; set; } = [];
    public Dictionary<ContextTier, ContextFormat> FormatPlan { get; set; } = [];
    public int SegmentsDropped { get; set; }
    public int SegmentsRedacted { get; set; }
}

/// <summary>
/// A single tier's formatted output within the assembled context.
/// </summary>
public class ContextSegment
{
    public ContextTier Tier { get; set; }
    public ContextFormat Format { get; set; }
    public string Content { get; set; } = string.Empty;
    public int TokensUsed { get; set; }
    public int TokenBudget { get; set; }
    public bool WasTruncated { get; set; }
    public bool WasAudited { get; set; }
    public bool WasDropped { get; set; }
    public bool WasRedacted { get; set; }
    public List<string> AuditFindings { get; set; } = [];
}

/// <summary>
/// Raw inputs gathered from SQL + Qdrant before formatting.
/// </summary>
public class ContextInputs
{
    public CurrentStateContext State { get; set; } = new();
    public List<SemanticMemory> Memories { get; set; } = [];
    public List<AntiPattern> AntiPatterns { get; set; } = [];
    public List<Preference> Preferences { get; set; } = [];
    public ProjectFacts Facts { get; set; } = new();
}

/// <summary>
/// P1 — Current project state, recent changes, sprint status, errors.
/// </summary>
public class CurrentStateContext
{
    public string Project { get; set; } = string.Empty;
    public string? Environment { get; set; }
    public string? Branch { get; set; }
    public List<string> ChangedLast24h { get; set; } = [];
    public List<string> ChangedLast7d { get; set; } = [];
    public List<SprintItem> SprintItems { get; set; } = [];
    public List<RecentError> RecentErrors { get; set; } = [];
    public DateTime? LastDeployTime { get; set; }
    public string? LastDeployStatus { get; set; }
}

public class SprintItem
{
    public string Description { get; set; } = string.Empty;
    public string Priority { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public int Count { get; set; } = 1;
}

public class RecentError
{
    public string Description { get; set; } = string.Empty;
    public int OccurrenceCount { get; set; }
    public string Timeframe { get; set; } = string.Empty;
}

/// <summary>
/// P2 — Semantic memory result from Qdrant with relevance score.
/// </summary>
public class SemanticMemory
{
    public string Summary { get; set; } = string.Empty;
    public string? Solution { get; set; }
    public string? Approach { get; set; }
    public string? OutcomeLabel { get; set; }
    public double RelevanceScore { get; set; }
    public string? Tags { get; set; }
    public DateTime CreatedAt { get; set; }
    public int SessionId { get; set; }
}

/// <summary>
/// P5 — Project registry, endpoints, known-good patterns, pinned versions.
/// </summary>
public class ProjectFacts
{
    public List<ProjectRegistryEntry> Projects { get; set; } = [];
    public Dictionary<string, string> Endpoints { get; set; } = [];
    public List<string> KnownGoodPatterns { get; set; } = [];
    public Dictionary<string, string> PinnedVersions { get; set; } = [];
}

public class ProjectRegistryEntry
{
    public string Name { get; set; } = string.Empty;
    public string Stack { get; set; } = string.Empty;
    public string? HostingInfo { get; set; }
    public string? Notes { get; set; }
}
