using System.Net.Http.Headers;
using Daily.Services;

namespace Daily.Services.Auth
{
    public class GoogleAuthHandler : DelegatingHandler
    {
        private readonly IAuthService _authService;

        public GoogleAuthHandler(IAuthService authService)
        {
            _authService = authService;
            InnerHandler = new HttpClientHandler();
        }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            // 1. Send Request
            var response = await base.SendAsync(request, cancellationToken);

            // 2. Check for 401
            if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            {
                Console.WriteLine("[GoogleAuthHandler] 401 Unauthorized. Attempting refresh...");

                // 3. Attempt Refresh
                var refreshed = await _authService.RefreshGoogleTokenAsync();

                if (refreshed)
                {
                    // 4. Get New Token
                    var newToken = _authService.GetProviderToken();
                    
                    if (!string.IsNullOrEmpty(newToken))
                    {
                        // 5. Retry Request with new Token
                        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", newToken);
                        
                        // We must recreate the request? 
                        // HttpClient request messages can usually be resent if content is not a stream that was consumed?
                        // GET requests are fine. POSTs might be tricky.
                        // YouTubeService mostly uses GET.
                        
                        // Note: You can't reuse the same HttpRequestMessage if it was already sent?
                        // Actually, in .NET it's often single-use. We might need to clone it.
                        // But for simple GETs usually re-sending works or we create a new one.
                        // Let's try Cloned/New request logic if needed, but for now simple retry.
                        // Actually, "The request message was already sent. Cannot send the same request message multiple times." is a common error.
                        
                        var newRequest = await CloneRequest(request);
                        newRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", newToken);
                        
                        response = await base.SendAsync(newRequest, cancellationToken);
                        Console.WriteLine($"[GoogleAuthHandler] Retry Result: {response.StatusCode}");
                    }
                }
            }

            return response;
        }

        private async Task<HttpRequestMessage> CloneRequest(HttpRequestMessage request)
        {
            var clone = new HttpRequestMessage(request.Method, request.RequestUri);
            clone.Version = request.Version;
            
            foreach (var header in request.Headers)
                clone.Headers.TryAddWithoutValidation(header.Key, header.Value);

            if (request.Content != null)
            {
                // We'd need to copy content, but YouTube Service GETs don't have content.
                // Keeping it simple for GETs.
            }
            
            return clone;
        }
    }
}
