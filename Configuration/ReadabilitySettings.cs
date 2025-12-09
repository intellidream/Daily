using System.Text;

namespace Daily.Configuration
{
    public static class ReadabilitySettings
    {
        public static string GetCss(bool isDesktop)
        {
            if (!isDesktop) return string.Empty;

            return @"
                /* Optimal Reading Standards */
                .reader-content {
                    max-width: 68ch;         /* 1. Optimal Line Length: ~65-75 characters */
                    margin: 0 auto;          /* Centering */
                    font-size: 1.25rem;      /* Larger font for comfort (~20px) */
                    line-height: 1.75;       /* Generous Leading */
                    padding: 2rem 1rem;      /* Sufficient Breathing Room */
                    font-family: 'Segoe UI', SYSTEM-UI, sans-serif; /* Clean Sans-Serif */
                    /* background-color: transparent; Removed global transparency to allow theme overrides */
                }
                
                .reader-content img {
                    border-radius: 8px;
                    margin: 2rem auto;
                    display: block;
                    max-width: 100%;
                    height: auto;            /* Prevent vertical distortion */
                    object-fit: contain;     /* fallback */
                }

                /* Prevent overflows for embedded content */
                .reader-content iframe, 
                .reader-content video, 
                .reader-content embed, 
                .reader-content object {
                    max-width: 100%;
                    margin: 2rem auto;
                    display: block;
                    border-radius: 8px;
                }

                .reader-content h1 { font-size: 2.5rem; line-height: 1.2; margin-bottom: 1.5rem; }
                .reader-content h2 { font-size: 2rem; margin-top: 3rem; margin-bottom: 1rem; }
                .reader-content h3 { font-size: 1.75rem; margin-top: 2rem; margin-bottom: 1rem; }
                .reader-content p { margin-bottom: 1.5rem; }
                
                /* Dark Mode handling for WebView (Blazor handles its own) */
                @media (prefers-color-scheme: dark) {
                    .reader-content { color: #E0E0E0; background-color: transparent; }
                    .reader-content a { color: #8ab4f8; }
                }
                @media (prefers-color-scheme: light) {
                    .reader-content { color: #202124; background-color: #F2FFFFFF; }
                    .reader-content a { color: #1a73e8; }
                }

                /* App-driven Theme Overrides (Higher Specificity) */
                body[data-theme='dark'] .reader-content,
                body.reader-content[data-theme='dark'] { 
                    color: #E0E0E0; 
                    background-color: transparent; 
                }
                
                body[data-theme='dark'] .reader-content a,
                body.reader-content[data-theme='dark'] a { color: #8ab4f8; }

                body[data-theme='light'] .reader-content,
                body.reader-content[data-theme='light'] { 
                    color: #202124; 
                    background-color: #F2FFFFFF; 
                }
                
                body[data-theme='light'] .reader-content a,
                body.reader-content[data-theme='light'] a { color: #1a73e8; }
            ";
        }
    }
}
