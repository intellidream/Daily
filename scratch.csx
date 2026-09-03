using System;
using System.Net.Http;
using System.Threading.Tasks;
using System.IO;
using System.Text.RegularExpressions;

var key = Regex.Match(File.ReadAllText("ZeppOS/app-side/index.js"), "SUPABASE_ANON_KEY = '([^']+)'").Groups[1].Value;
var url = "https://akkfouifxztnfwwiclwg.supabase.co/rest/v1/habits_logs?select=id,created_at,updated_at,logged_at&order=logged_at.desc&limit=10";
var client = new HttpClient();
client.DefaultRequestHeaders.Add("apikey", key);
client.DefaultRequestHeaders.Add("Authorization", "Bearer " + key);
var res = await client.GetAsync(url);
Console.WriteLine(await res.Content.ReadAsStringAsync());
