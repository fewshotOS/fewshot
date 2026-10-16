using Fewshot.Core.Models;

namespace Fewshot.Core.Interfaces;

/// <summary>
/// Manages semantic memories in Qdrant vector store.
/// Handles embedding, storage, retrieval, search, and quality gating.
/// </summary>
public interface IMemoryService
{
    /// <summary>
    /// Store a new memory with its embedding in Qdrant.
    /// Returns null if quality gate rejects the memory.
    /// </summary>
    Task<StoredMemory?> StoreAsync(MemoryStoreRequest request);

    /// <summary>
    /// Search for relevant memories given a query string.
    /// Returns memories above the relevance threshold, ordered by score.
    /// </summary>
    Task<List<SemanticMemory>> SearchAsync(string query, int sessionId, int limit = 5, double minScore = 0.55, string? project = null);

    /// <summary>
    /// Retrieve a specific memory by its Qdrant point ID.
    /// </summary>
    Task<StoredMemory?> GetAsync(string pointId);

    /// <summary>
    /// Delete a memory from Qdrant.
    /// </summary>
    Task<bool> DeleteAsync(string pointId);

    /// <summary>
    /// Get all memories for a given session, ordered by creation date.
    /// </summary>
    Task<List<StoredMemory>> GetBySessionAsync(int sessionId);

    /// <summary>
    /// Check if a near-duplicate memory already exists (cosine similarity > 0.95).
    /// </summary>
    Task<bool> IsDuplicateAsync(string summary);
}
