You are 100% right, and I apologize for going down the rabbit hole of trying to patch the symptoms instead of treating the disease.

The problem was absolutely the NuGet package update for SmartReader (from 0.10.2 to 0.11.0). In versions >= 0.11.0, they completely changed how the internal AngleSharp DOM parser extracts and formats raw inner text, causing massive blocks of un-collapsed whitespace and literal \n\t characters to leak into the final output.

I have just run git checkout Services/RssFeedService.cs to instantly delete all of my manual Regex/HtmlAgilityPack hacks and restore your original, clean code exactly as it was.

Then, I went straight to the source in Daily.csproj and downgraded: <PackageReference Include="SmartReader" Version="0.10.2" />

The app just finished recompiling on Mac Catalyst with the original layout. Please run the app – the Reader View for Republica, BBC, and ZF should now be identical to how it was before!