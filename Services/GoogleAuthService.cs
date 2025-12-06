using System;
using System.Threading.Tasks;
using Microsoft.Maui.Authentication;
using Microsoft.Maui.Storage;
using Microsoft.Maui.ApplicationModel;
using System.Text.RegularExpressions;
using System.Collections.Generic;

namespace Daily.Services
{
    public class GoogleAuthService : IGoogleAuthService
    {
        // Android (iOS Type Client ID)
        // Credentials moved to Configuration/Secrets.cs (git-ignored)

#if WINDOWS
        private const string ClientId = Daily.Configuration.Secrets.WindowsClientId;
        // RedirectUri for Windows is dynamic (http://127.0.0.1:{port})
#else
        private const string ClientId = Daily.Configuration.Secrets.AndroidClientId;
        private const string RedirectUri = "com.intellidream.daily:/oauth2redirect";
#endif
        
        // Scopes: YouTube ReadOnly
        private const string Scope = "https://www.googleapis.com/auth/youtube.readonly";
        private const string AuthorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth";
        private const string TokenEndpoint = "https://oauth2.googleapis.com/token";

        private string? _accessToken;
        public bool IsAuthenticated => !string.IsNullOrEmpty(_accessToken);

        public async Task<(string? AccessToken, string? Error)> LoginAsync()
        {
            try
            {
                // PKCE: Generate Code Verifier and Challenge
                var codeVerifier = GenerateCodeVerifier();
                var codeChallenge = GenerateCodeChallenge(codeVerifier);

#if WINDOWS
                // Windows: Manual HttpListener Flow
                var listener = new System.Net.HttpListener();
                
                // Use random free port on loopback
                var port = GetRandomUnusedPort();
                var redirectUri = $"http://127.0.0.1:{port}/";
                
                listener.Prefixes.Add(redirectUri);
                listener.Start();

                var authUrl = new Uri($"{AuthorizationEndpoint}?response_type=code" +
                                      $"&client_id={ClientId}" +
                                      $"&redirect_uri={Uri.EscapeDataString(redirectUri)}" +
                                      $"&scope={Uri.EscapeDataString(Scope)}" +
                                      $"&code_challenge={codeChallenge}" +
                                      $"&code_challenge_method=S256");

                // Open Browser
                await Launcher.OpenAsync(authUrl);

                // Wait for request
                var context = await listener.GetContextAsync();
                var request = context.Request;
                
                // Parse code using Regex
                string? code = null;
                if (request.Url?.Query != null)
                {
                    var match = Regex.Match(request.Url.Query, "code=([^&]+)");
                    if (match.Success)
                    {
                        code = match.Groups[1].Value;
                        // IMPORTANT: Url decode the code, otherwise it gets double-encoded in the token request
                        code = Uri.UnescapeDataString(code);
                    }
                }
                
                // Send response to browser
                var response = context.Response;
                var responseString = "<html><body style='background:#121212;color:white;font-family:sans-serif;text-align:center;padding-top:50px;'><h2>Login Successful</h2><p>You can close this window now.</p><script>window.close();</script></body></html>";
                var buffer = System.Text.Encoding.UTF8.GetBytes(responseString);
                response.ContentLength64 = buffer.Length;
                var output = response.OutputStream;
                output.Write(buffer, 0, buffer.Length);
                output.Close();
                listener.Stop();
#else
                // Android: WebAuthenticator Flow
                var authUrl = new Uri($"{AuthorizationEndpoint}?response_type=code" +
                                      $"&client_id={ClientId}" +
                                      $"&redirect_uri={RedirectUri}" +
                                      $"&scope={Uri.EscapeDataString(Scope)}" +
                                      $"&code_challenge={codeChallenge}" +
                                      $"&code_challenge_method=S256");

                var callbackUrl = new Uri(RedirectUri);
                var result = await WebAuthenticator.AuthenticateAsync(authUrl, callbackUrl);
                var code = result?.Properties.ContainsKey("code") == true ? result.Properties["code"] : null;
#endif

                if (string.IsNullOrEmpty(code)) return (null, "No code received from Google.");

                // Exchange Code for Token (Pass the specific redirect URI used)
#if WINDOWS
                return await ExchangeCodeForTokenAsync(code, codeVerifier, redirectUri);
#else
                return await ExchangeCodeForTokenAsync(code, codeVerifier, RedirectUri);
#endif
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Auth Error: {ex.Message}");
                return (null, ex.Message);
            }
        }

        private int GetRandomUnusedPort()
        {
            var listener = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
            listener.Start();
            var port = ((System.Net.IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            return port;
        }

        private async Task<(string? AccessToken, string? Error)> ExchangeCodeForTokenAsync(string code, string codeVerifier, string redirectUrl)
        {
            using var client = new System.Net.Http.HttpClient();
            var paramsDict = new Dictionary<string, string>
            {
                { "client_id", ClientId },
                { "code", code },
                { "redirect_uri", redirectUrl },
                { "grant_type", "authorization_code" },
                { "code_verifier", codeVerifier }
            };

#if WINDOWS
            if (!string.IsNullOrEmpty(Daily.Configuration.Secrets.WindowsClientSecret))
            {
                 paramsDict.Add("client_secret", Daily.Configuration.Secrets.WindowsClientSecret);
            }
#endif

            var content = new System.Net.Http.FormUrlEncodedContent(paramsDict);

            var response = await client.PostAsync(TokenEndpoint, content);
            if (response.IsSuccessStatusCode)
            {
                var json = await response.Content.ReadAsStringAsync();
                var node = System.Text.Json.Nodes.JsonNode.Parse(json);
                _accessToken = node?["access_token"]?.ToString();
                
                if (!string.IsNullOrEmpty(_accessToken))
                {
                    await SecureStorage.SetAsync("google_access_token", _accessToken);
                    return (_accessToken, null);
                }
                return (null, "Parsed token was empty.");
            }
            
            var errorBody = await response.Content.ReadAsStringAsync();
            Console.WriteLine($"Token Exchange Failed: {response.StatusCode} {errorBody}");
            return (null, $"Error {response.StatusCode}: {errorBody}");
        }

        private string GenerateCodeVerifier()
        {
            // Random 32 bytes -> Base64Url
            var bytes = new byte[32];
            using (var rng = System.Security.Cryptography.RandomNumberGenerator.Create())
            {
                rng.GetBytes(bytes);
            }
            return Base64UrlEncode(bytes);
        }

        private string GenerateCodeChallenge(string codeVerifier)
        {
            // SHA256(Verifier) -> Base64Url
            using var sha256 = System.Security.Cryptography.SHA256.Create();
            var challengeBytes = sha256.ComputeHash(System.Text.Encoding.ASCII.GetBytes(codeVerifier));
            return Base64UrlEncode(challengeBytes);
        }

        private string Base64UrlEncode(byte[] bytes)
        {
            return Convert.ToBase64String(bytes)
                .Replace("+", "-")
                .Replace("/", "_")
                .Replace("=", "");
        }

        public async Task LogoutAsync()
        {
            _accessToken = null;
            SecureStorage.Remove("google_access_token");
        }

        public async Task<string?> GetAccessTokenAsync()
        {
            if (_accessToken != null) return _accessToken;

            // Try to restore
            _accessToken = await SecureStorage.GetAsync("google_access_token");
            return _accessToken;
        }
    }
}
