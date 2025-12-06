using Daily.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface IYouTubeService
    {
        Task<List<VideoItem>> GetRecommendationsAsync(string accessToken);
    }
}
