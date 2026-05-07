import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Constants
const YAHOO_FINANCE_URL = "https://query1.finance.yahoo.com/v7/finance/quote?symbols=";

serve(async (req) => {
  try {
    // Check method
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 });
    }

    // Parse symbols from body
    const body = await req.json();
    const symbols: string[] = body.symbols;
    
    if (!symbols || symbols.length === 0) {
      return new Response(JSON.stringify({ error: 'No symbols provided' }), { status: 400 });
    }

    console.log(`Fetching quotes for: ${symbols.join(',')}`);

    // 1. Fetch from Yahoo Finance
    const response = await fetch(`${YAHOO_FINANCE_URL}${symbols.join(',')}`);
    if (!response.ok) {
      throw new Error(`Yahoo Finance API error: ${response.status}`);
    }
    
    const data = await response.json();
    const results = data.quoteResponse?.result || [];

    // 2. Initialize Supabase Client (Service Role for Bypassing RLS if necessary, or Anon for regular)
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 3. Map to our DB schema
    const quotesToUpsert = results.map((q: any) => ({
      symbol: q.symbol,
      name: q.shortName || q.longName || q.symbol,
      type: q.quoteType?.toLowerCase() || 'stock',
      exchange: q.exchange || 'US',
      currency: q.currency || 'USD',
      last_price: q.regularMarketPrice,
      last_updated_at: new Date().toISOString()
    }));

    if (quotesToUpsert.length > 0) {
        // 4. Cache in Supabase
        const { error } = await supabaseClient
            .from('securities')
            .upsert(quotesToUpsert, { onConflict: 'symbol' });
            
        if (error) {
            console.error('Supabase Upsert Error:', error);
        }
    }

    // Return the fresh data to the client
    return new Response(JSON.stringify({ success: true, data: quotesToUpsert }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: any) {
    console.error("Function Error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    });
  }
});
