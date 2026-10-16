using Fewshot.Core.Interfaces;
using Fewshot.Core.Models;
using Fewshot.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace Fewshot.Infrastructure.Services;

public class AntiPatternService : IAntiPatternService
{
    private readonly FewshotDbContext _db;

    public AntiPatternService(FewshotDbContext db) => _db = db;

    public async Task<AntiPattern> CreateAsync(AntiPattern ap)
    {
        _db.AntiPatterns.Add(ap);
        await _db.SaveChangesAsync();
        return ap;
    }

    public async Task<List<AntiPattern>> GetByLanguageAsync(string? language = null)
    {
        var query = _db.AntiPatterns.AsQueryable();

        if (language != null)
            query = query.Where(a => a.Language == language || a.Language == null);

        return await query.OrderByDescending(a => a.CreatedAt).ToListAsync();
    }

    public async Task<List<AntiPattern>> GetByProjectAsync(string? project)
    {
        // SessionId == 0 = pack imports (global). Null session project = global.
        return await _db.AntiPatterns
            .Where(a => a.SessionId == 0 ||
                        _db.Sessions.Any(s => s.SessionId == a.SessionId &&
                                              (s.Project == project || s.Project == null)))
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();
    }

    public async Task<List<AntiPattern>> GetAllAsync()
    {
        return await _db.AntiPatterns
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();
    }

    public async Task DeleteAsync(int antiPatternId)
    {
        await _db.AntiPatterns
            .Where(a => a.AntiPatternId == antiPatternId)
            .ExecuteDeleteAsync();
    }
}
