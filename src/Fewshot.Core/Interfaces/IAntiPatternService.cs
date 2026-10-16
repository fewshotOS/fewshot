using Fewshot.Core.Models;

namespace Fewshot.Core.Interfaces;

public interface IAntiPatternService
{
    Task<AntiPattern> CreateAsync(AntiPattern antiPattern);
    Task<List<AntiPattern>> GetByLanguageAsync(string? language = null);
    Task<List<AntiPattern>> GetAllAsync();
    Task<List<AntiPattern>> GetByProjectAsync(string? project);
    Task DeleteAsync(int antiPatternId);
}
