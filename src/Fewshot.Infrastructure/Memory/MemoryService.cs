using Fewshot.Core.Interfaces;
using Fewshot.Core.Models;
using Fewshot.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace Fewshot.Infrastructure.Memory;

/// <summary>
/// SQLite-backed memory service. Embeddings stored as raw float bytes.
/// Cosine similarity computed in-process — fine for personal-scale stores (thousands of memories).
/// </summary>
public class MemoryService : IMemoryService
{
    private readonly FewshotDbContext _db;
    private readonly IEmbeddingService _embeddings;
    private readonly ILogger<MemoryService> _logger;

    private const int MinSummaryLength = 20;
    private const int MaxSummaryLength = 2000;
    private const double DuplicateThreshold = 0.90; // cosine similarity: higher = more similar

    public MemoryService(FewshotDbContext db, IEmbeddingService embeddings, ILogger<MemoryService> logger)
    {
        _db = db;
        _embeddings = embeddings;
        _logger = logger;
    }

    public async Task<StoredMemory?> StoreAsync(MemoryStoreRequest request)
    {
        if (!ValidateRequest(request, out var rejection))
        {
            _logger.LogInformation("Memory rejected: {Reason}", rejection);
            return null;
        }

        if (await IsDuplicateAsync(request.Summary))
        {
            _logger.LogInformation("Memory rejected: near-duplicate exists");
            return null;
        }

        float[] embedding;
        try
        {
            embedding = await _embeddings.EmbedAsync(BuildEmbeddingText(request));
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            _logger.LogWarning("Embedding service unavailable, cannot store memory: {Message}", ex.Message);
            return null;
        }
        var pointId = Guid.NewGuid().ToString();
        var now = DateTime.UtcNow;

        var memory = new MemoryEntry
        {
            PointId = pointId,
            SessionId = request.SessionId,
            Project = request.Project,
            Summary = request.Summary,
            Solution = request.Solution,
            Approach = request.Approach,
            OutcomeLabel = request.OutcomeLabel,
            Tags = request.Tags,
            Language = request.Language,
            Embedding = ToBytes(embedding),
            CreatedAt = now
        };

        _db.Memories.Add(memory);
        await _db.SaveChangesAsync();

        _logger.LogInformation("Stored memory {PointId} for session {SessionId}: {Summary}",
            pointId, request.SessionId, Truncate(request.Summary, 80));

        return ToStoredMemory(memory);
    }

    public async Task<List<SemanticMemory>> SearchAsync(string query, int sessionId, int limit = 5, double minScore = 0.55, string? project = null)
    {
        float[] queryVector;
        try
        {
            queryVector = await _embeddings.EmbedAsync(query);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            _logger.LogWarning("Embedding service unavailable, returning empty results: {Message}", ex.Message);
            return [];
        }

        // Pull all embeddings and score in-process
        // For thousands of memories this is ~10-20ms — acceptable for local use
        var all = await _db.Memories
            .Where(m => project == null || m.Project == project || m.Project == null)
            .Select(m => new { m.PointId, m.SessionId, m.Summary, m.Solution, m.Approach,
                               m.OutcomeLabel, m.Tags, m.Language, m.CreatedAt, m.Embedding })
            .ToListAsync();

        var expectedBytes = queryVector.Length * sizeof(float);
        var results = all
            .Where(m => m.Embedding is { Length: > 0 } && m.Embedding.Length == expectedBytes)
            .Select(m => new { Memory = m, Score = CosineSimilarity(queryVector, ToFloats(m.Embedding)) })
            .Where(x => x.Score >= minScore)
            .OrderByDescending(x => x.Score)
            .Take(limit)
            .Select(x => new SemanticMemory
            {
                Summary = x.Memory.Summary,
                Solution = x.Memory.Solution,
                Approach = x.Memory.Approach,
                OutcomeLabel = x.Memory.OutcomeLabel,
                Tags = x.Memory.Tags,
                RelevanceScore = x.Score,
                SessionId = x.Memory.SessionId,
                CreatedAt = x.Memory.CreatedAt
            })
            .ToList();

        _logger.LogInformation("Search for '{Query}' returned {Count} memories", Truncate(query, 60), results.Count);
        return results;
    }

    public async Task<StoredMemory?> GetAsync(string pointId)
    {
        var m = await _db.Memories.FindAsync(pointId);
        return m is null ? null : ToStoredMemory(m);
    }

    public async Task<bool> DeleteAsync(string pointId)
    {
        var rows = await _db.Memories.Where(m => m.PointId == pointId).ExecuteDeleteAsync();
        return rows > 0;
    }

    public async Task<List<StoredMemory>> GetBySessionAsync(int sessionId)
    {
        return await _db.Memories
            .Where(m => m.SessionId == sessionId)
            .OrderByDescending(m => m.CreatedAt)
            .Select(m => ToStoredMemory(m))
            .ToListAsync();
    }

    public async Task<bool> IsDuplicateAsync(string summary)
    {
        float[] vector;
        try
        {
            vector = await _embeddings.EmbedAsync(summary);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            _logger.LogWarning("Embedding service unavailable, skipping duplicate check: {Message}", ex.Message);
            return false;
        }

        var all = await _db.Memories.Select(m => m.Embedding).ToListAsync();

        var expectedBytes = vector.Length * sizeof(float);
        return all.Any(e => e is { Length: > 0 } && e.Length == expectedBytes
                            && CosineSimilarity(vector, ToFloats(e)) >= DuplicateThreshold);
    }

    // ── Helpers ───────────────────────────────────────────────────

    private static StoredMemory ToStoredMemory(MemoryEntry m) => new()
    {
        PointId = m.PointId,
        SessionId = m.SessionId,
        Project = m.Project,
        Summary = m.Summary,
        Solution = m.Solution,
        Approach = m.Approach,
        OutcomeLabel = m.OutcomeLabel,
        Tags = m.Tags,
        Language = m.Language,
        CreatedAt = m.CreatedAt
    };

    private static bool ValidateRequest(MemoryStoreRequest r, out string reason)
    {
        if (string.IsNullOrWhiteSpace(r.Summary)) { reason = "Summary is empty"; return false; }
        if (r.Summary.Length < MinSummaryLength) { reason = $"Summary too short ({r.Summary.Length} chars)"; return false; }
        if (r.Summary.Length > MaxSummaryLength) { reason = $"Summary too long ({r.Summary.Length} chars)"; return false; }
        if (r.SessionId <= 0) { reason = "Invalid session ID"; return false; }
        reason = "";
        return true;
    }

    private static string BuildEmbeddingText(MemoryStoreRequest r)
    {
        var parts = new List<string> { r.Summary };
        if (!string.IsNullOrEmpty(r.Solution)) parts.Add(r.Solution);
        if (!string.IsNullOrEmpty(r.Approach)) parts.Add(r.Approach);
        if (!string.IsNullOrEmpty(r.Tags)) parts.Add(r.Tags);
        return string.Join(" ", parts);
    }

    /// <summary>Cosine similarity in [0, 1]. Both vectors must be 768-dim.</summary>
    private static double CosineSimilarity(float[] a, float[] b)
    {
        if (a.Length == 0 || a.Length != b.Length) return 0;
        double dot = 0, normA = 0, normB = 0;
        for (int i = 0; i < a.Length; i++)
        {
            dot += a[i] * b[i];
            normA += a[i] * a[i];
            normB += b[i] * b[i];
        }
        if (normA == 0 || normB == 0) return 0;
        return dot / (Math.Sqrt(normA) * Math.Sqrt(normB));
    }

    private static byte[] ToBytes(float[] floats)
    {
        var bytes = new byte[floats.Length * sizeof(float)];
        Buffer.BlockCopy(floats, 0, bytes, 0, bytes.Length);
        return bytes;
    }

    private static float[] ToFloats(byte[] bytes)
    {
        var floats = new float[bytes.Length / sizeof(float)];
        Buffer.BlockCopy(bytes, 0, floats, 0, bytes.Length);
        return floats;
    }

    private static string Truncate(string s, int max) =>
        s.Length <= max ? s : s[..max] + "...";
}
