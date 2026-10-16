using System.Security.Cryptography;
using System.Text;
using Fewshot.Core.Enums;
using Fewshot.Core.Interfaces;
using Fewshot.Core.Models;
using Fewshot.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace Fewshot.Infrastructure.Context;

public class ContextInjector : IContextInjector
{
    private readonly IExperimentService _experiments;
    private readonly IMemoryService _memory;
    private readonly IPreferenceService _preferences;
    private readonly IAntiPatternService _antiPatterns;
    private readonly IAuditService _audit;
    private readonly AclFormatter _acl;
    private readonly ProseFormatter _prose;
    private readonly ITokenCounter _tokenCounter;
    private readonly FewshotDbContext _db;

    // These finding types warrant dropping the entire segment — credentials with zero legitimate use
    private static readonly HashSet<string> HardBlockTypes =
    [
        "ConnectionString", "PrivateKey", "BearerToken",
        "AWSKey", "GitHubToken", "ApiKeyParam", "SSN"
    ];

    private static readonly Dictionary<ContextTier, int> TierBudgets = new()
    {
        [ContextTier.P1] = 800,
        [ContextTier.P2] = 1500,
        [ContextTier.P3] = 400,
        [ContextTier.P4] = 300,
        [ContextTier.P5] = 500
    };

    public ContextInjector(
        IExperimentService experiments,
        IMemoryService memory,
        IPreferenceService preferences,
        IAntiPatternService antiPatterns,
        IAuditService audit,
        AclFormatter acl,
        ProseFormatter prose,
        ITokenCounter tokenCounter,
        FewshotDbContext db)
    {
        _experiments = experiments;
        _memory = memory;
        _preferences = preferences;
        _antiPatterns = antiPatterns;
        _audit = audit;
        _acl = acl;
        _prose = prose;
        _tokenCounter = tokenCounter;
        _db = db;
    }

    public async Task<ContextInjectionResult> BuildContextAsync(int sessionId, ContextInputs inputs)
    {
        return await BuildCoreAsync(sessionId, inputs);
    }

    public async Task<ContextInjectionResult> BuildContextAutoAsync(int sessionId, CurrentStateContext state, ProjectFacts? facts = null)
    {
        // Build semantic search query from current state
        var searchQuery = BuildSearchQuery(state);

        var project = string.IsNullOrWhiteSpace(state.Project) ? null : state.Project;

        // All of these hit the same scoped FewshotDbContext (memory search is in-process
        // cosine over _db.Memories, not Qdrant) — must run sequentially
        var memories = await _memory.SearchAsync(searchQuery, sessionId, project: project);
        var allPreferences = await _preferences.GetAllAsync();
        var antiPatterns = await _antiPatterns.GetByProjectAsync(project);

        var inputs = new ContextInputs
        {
            State = state,
            Memories = memories,
            Preferences = allPreferences,
            AntiPatterns = antiPatterns,
            Facts = facts ?? await HydrateFactsAsync()
        };

        return await BuildCoreAsync(sessionId, inputs);
    }

    private async Task<ProjectFacts> HydrateFactsAsync()
    {
        var projects = await _db.Projects
            .Where(p => p.IsActive && p.Facts != null && p.Facts != "")
            .OrderBy(p => p.DisplayName)
            .Select(p => new { p.DisplayName, p.Facts })
            .ToListAsync();

        return new ProjectFacts
        {
            Projects = projects
                .Select(p => new ProjectRegistryEntry { Name = p.DisplayName, Notes = p.Facts })
                .ToList()
        };
    }

    private async Task<ContextInjectionResult> BuildCoreAsync(int sessionId, ContextInputs inputs)
    {
        var plan = await _experiments.AssignFormatsAsync(sessionId);
        var segments = new List<ContextSegment>();

        segments.Add(BuildSegment(plan.TierFormats, ContextTier.P1,
            () => _acl.FormatP1(inputs.State), () => _prose.FormatP1(inputs.State)));

        segments.Add(BuildSegment(plan.TierFormats, ContextTier.P2,
            () => _acl.FormatP2(inputs.Memories), () => _prose.FormatP2(inputs.Memories)));

        segments.Add(BuildSegment(plan.TierFormats, ContextTier.P3,
            () => _acl.FormatP3(inputs.AntiPatterns), () => _prose.FormatP3(inputs.AntiPatterns)));

        segments.Add(BuildSegment(plan.TierFormats, ContextTier.P4,
            () => _acl.FormatP4(inputs.Preferences), () => _prose.FormatP4(inputs.Preferences)));

        segments.Add(BuildSegment(plan.TierFormats, ContextTier.P5,
            () => _acl.FormatP5(inputs.Facts), () => _prose.FormatP5(inputs.Facts)));

        // Remove empty segments, then run audit gate on each
        segments = segments.Where(s => !string.IsNullOrEmpty(s.Content)).ToList();
        await AuditSegmentsAsync(segments, sessionId);

        // Only pass non-dropped segments to Claude
        var safeSegments = segments.Where(s => !s.WasDropped).ToList();

        var assembled = string.Join("\n\n", safeSegments.Select(s => s.Content));
        var hash = ComputeHash(assembled);

        var result = new ContextInjectionResult
        {
            AssembledContext = assembled,
            TotalTokens = safeSegments.Sum(s => s.TokensUsed),
            ContextHash = hash,
            Segments = segments, // include dropped segments so dashboard can show audit info
            FormatPlan = plan.TierFormats,
            SegmentsDropped = segments.Count(s => s.WasDropped),
            SegmentsRedacted = segments.Count(s => s.WasRedacted)
        };

        // Write token counts back to experiment assignments (only safe segments)
        await _experiments.RecordTokenUsageAsync(sessionId, safeSegments);

        return result;
    }

    private async Task AuditSegmentsAsync(List<ContextSegment> segments, int sessionId)
    {
        foreach (var segment in segments)
        {
            var auditResult = await _audit.AnalyzeAsync(segment.Content, sessionId);
            segment.WasAudited = true;
            segment.AuditFindings = auditResult.Findings
                .Select(f => $"{f.DetectedType} ({f.Stage}, {f.Confidence:P0})")
                .ToList();

            if (auditResult.Findings.Count == 0) continue;

            // Hard block: credential types that have zero legitimate use in context
            var hasHardBlock = auditResult.Findings
                .Any(f => HardBlockTypes.Contains(f.DetectedType) && f.Confidence >= 0.85);

            if (hasHardBlock)
            {
                segment.WasDropped = true;
                segment.Content = string.Empty;
                segment.TokensUsed = 0;
                continue;
            }

            // Soft redact: PII and high-entropy tokens — replace spans but keep context
            if (auditResult.RedactedContent != null)
            {
                var originalLen = segment.Content.Length;
                var redactedLen = auditResult.RedactedContent.Length;

                // If redaction destroyed >50% of content, drop the segment entirely
                if (redactedLen < originalLen * 0.5)
                {
                    segment.WasDropped = true;
                    segment.Content = string.Empty;
                    segment.TokensUsed = 0;
                }
                else
                {
                    segment.WasRedacted = true;
                    segment.Content = auditResult.RedactedContent;
                    segment.TokensUsed = _tokenCounter.Count(segment.Content);
                }
            }
        }
    }

    /// <summary>
    /// Build a search query from current state for semantic memory retrieval.
    /// Combines project name, recent files, errors, and sprint context.
    /// </summary>
    private static string BuildSearchQuery(CurrentStateContext state)
    {
        var parts = new List<string>();

        if (!string.IsNullOrEmpty(state.Project))
            parts.Add(state.Project);

        // Add recent file context (just filenames, not full paths)
        foreach (var file in state.ChangedLast24h.Take(3))
        {
            var filename = file.Contains('/') ? file[(file.LastIndexOf('/') + 1)..] : file;
            parts.Add(filename);
        }

        // Add recent errors
        foreach (var error in state.RecentErrors.Take(2))
            parts.Add(error.Description);

        // Add sprint context
        foreach (var item in state.SprintItems.Take(2))
            parts.Add(item.Description);

        return string.Join(" ", parts);
    }

    private ContextSegment BuildSegment(
        Dictionary<ContextTier, ContextFormat> tierFormats,
        ContextTier tier,
        Func<string> aclFormat,
        Func<string> proseFormat)
    {
        var format = tierFormats.GetValueOrDefault(tier, ContextFormat.Prose);
        var content = format == ContextFormat.ACL ? aclFormat() : proseFormat();
        var budget = TierBudgets[tier];
        var tokens = _tokenCounter.Count(content);
        var wasTruncated = false;

        if (tokens > budget)
        {
            content = _tokenCounter.TruncateToTokens(content, budget);
            tokens = _tokenCounter.Count(content);
            wasTruncated = true;
        }

        return new ContextSegment
        {
            Tier = tier,
            Format = format,
            Content = content,
            TokensUsed = tokens,
            TokenBudget = budget,
            WasTruncated = wasTruncated
        };
    }

    private static string ComputeHash(string content)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(content));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
