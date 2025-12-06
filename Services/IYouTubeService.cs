using Daily.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface IYouTubeService
    {
        Task<(List<VideoItem> Videos, string NextPageToken)> GetRecommendationsAsync(string accessToken, string? pageToken = null, string? category = null);
    }
}
