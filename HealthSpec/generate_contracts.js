const fs = require('fs');
const path = require('path');

const registryPath = path.join(__dirname, 'metric_registry.json');
const registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
const metrics = registry.metrics;

// Helper: pascalCase
function toPascalCase(str) {
  return str.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join('');
}

// Helper: camelCase
function toCamelCase(str) {
  const pc = toPascalCase(str);
  return pc.charAt(0).toLowerCase() + pc.slice(1);
}

// Build deduplicated alias maps
// 1. Case-sensitive for TS and Kotlin
const uniqueAliases = new Map();
for (const [k, m] of Object.entries(metrics)) {
  uniqueAliases.set(k, k);
  for (const a of m.aliases) {
    if (!uniqueAliases.has(a)) {
      uniqueAliases.set(a, k);
    }
  }
}

// 2. Case-insensitive for C# (StringComparer.OrdinalIgnoreCase)
const csharpAliases = new Map();
for (const [k, m] of Object.entries(metrics)) {
  const lowerK = k.toLowerCase();
  if (!csharpAliases.has(lowerK)) {
    csharpAliases.set(lowerK, { key: k, metric: toPascalCase(k) });
  }
  for (const a of m.aliases) {
    const lowerA = a.toLowerCase();
    if (!csharpAliases.has(lowerA)) {
      csharpAliases.set(lowerA, { key: a, metric: toPascalCase(k) });
    }
  }
}

// 3. Swift aliases (distinct from rawValue)
const swiftAliases = new Map();
for (const [k, m] of Object.entries(metrics)) {
  for (const a of m.aliases) {
    if (a !== k && !swiftAliases.has(a)) {
      swiftAliases.set(a, toCamelCase(k));
    }
  }
}

// --- 1. Generate TypeScript contract ---
let ts = `// AUTO-GENERATED from HealthSpec/metric_registry.json - DO NOT EDIT MANUALLY
// Generated at: ${new Date().toISOString()}

export type HealthMetricType =
${Object.keys(metrics).map(k => `  | '${k}'`).join('\n')};

export interface MetricDefinition {
  canonicalKey: HealthMetricType;
  displayName: string;
  category: string;
  canonicalUnit: string;
  semantics: 'spot' | 'interval_delta' | 'cumulative_daily' | 'session_stage';
  aggregationRule: 'sum' | 'mean' | 'latest' | 'min' | 'max_of_cumulative';
  attributionWindow: 'calendar_day' | 'sleep_window';
  aliases: string[];
}

export const METRIC_REGISTRY: Record<HealthMetricType, MetricDefinition> = {
${Object.entries(metrics).map(([k, m]) => `  '${k}': {
    canonicalKey: '${k}',
    displayName: ${JSON.stringify(m.display_name)},
    category: ${JSON.stringify(m.category)},
    canonicalUnit: ${JSON.stringify(m.canonical_unit)},
    semantics: ${JSON.stringify(m.semantics)},
    aggregationRule: ${JSON.stringify(m.aggregation_rule)},
    attributionWindow: ${JSON.stringify(m.attribution_window)},
    aliases: ${JSON.stringify(m.aliases)}
  }`).join(',\n')}
};

export const ALIAS_TO_CANONICAL: Record<string, HealthMetricType> = {
${Array.from(uniqueAliases.entries()).map(([alias, canonical]) => `  ${JSON.stringify(alias)}: '${canonical}'`).join(',\n')}
};

export function normalizeMetricType(raw: string): HealthMetricType | null {
  return ALIAS_TO_CANONICAL[raw] || null;
}
`;

fs.writeFileSync(path.join(__dirname, 'canonicalHealthMetrics.ts'), ts);
console.log('Generated TypeScript contract: HealthSpec/canonicalHealthMetrics.ts');

// --- 2. Generate Swift contract ---
let swift = `// AUTO-GENERATED from HealthSpec/metric_registry.json - DO NOT EDIT MANUALLY
// Generated at: ${new Date().toISOString()}

import Foundation

public enum CanonicalHealthMetric: String, CaseIterable, Codable, Sendable {
${Object.keys(metrics).map(k => `    case ${toCamelCase(k)} = "${k}"`).join('\n')}

    public var displayName: String {
        switch self {
${Object.entries(metrics).map(([k, m]) => `        case .${toCamelCase(k)}: return "${m.display_name}"`).join('\n')}
        }
    }

    public var canonicalUnit: String {
        switch self {
${Object.entries(metrics).map(([k, m]) => `        case .${toCamelCase(k)}: return "${m.canonical_unit}"`).join('\n')}
        }
    }

    public static func from(alias: String) -> CanonicalHealthMetric? {
        if let direct = CanonicalHealthMetric(rawValue: alias) {
            return direct
        }
        switch alias {
${Array.from(swiftAliases.entries()).map(([alias, enumCase]) => `        case "${alias}": return .${enumCase}`).join('\n')}
        default:
            return nil
        }
    }
}
`;

const swiftTarget = path.join(__dirname, '../DailyCore/Sources/DailyCore/Models/CanonicalHealthMetrics.swift');
fs.writeFileSync(swiftTarget, swift);
console.log('Generated Swift contract:', swiftTarget);

// --- 3. Generate Kotlin contract ---
let kotlin = `// AUTO-GENERATED from HealthSpec/metric_registry.json - DO NOT EDIT MANUALLY
// Generated at: ${new Date().toISOString()}

package com.intellidream.daily.model

enum class CanonicalHealthMetric(
    val key: String,
    val displayName: String,
    val canonicalUnit: String,
    val semantics: String,
    val aggregationRule: String
) {
${Object.entries(metrics).map(([k, m]) => 
  `    ${toPascalCase(k).toUpperCase()}("${k}", "${m.display_name}", "${m.canonical_unit}", "${m.semantics}", "${m.aggregation_rule}")`
).join(',\n')};

    companion object {
        private val aliasMap: Map<String, CanonicalHealthMetric> = buildMap {
${Array.from(uniqueAliases.entries()).map(([alias, canonical]) => `            put("${alias}", ${toPascalCase(canonical).toUpperCase()})`).join('\n')}
        }

        fun fromAlias(raw: String): CanonicalHealthMetric? = aliasMap[raw]
    }
}
`;

const kotlinTarget = path.join(__dirname, '../Android/core-model/src/main/java/com/intellidream/daily/model/CanonicalHealthMetrics.kt');
fs.writeFileSync(kotlinTarget, kotlin);
console.log('Generated Kotlin contract:', kotlinTarget);

// --- 4. Generate C# contract ---
let csharp = `// AUTO-GENERATED from HealthSpec/metric_registry.json - DO NOT EDIT MANUALLY
// Generated at: ${new Date().toISOString()}

using System;
using System.Collections.Generic;

namespace Daily.Models.Health
{
    public enum CanonicalHealthMetric
    {
${Object.keys(metrics).map(k => `        ${toPascalCase(k)}`).join(',\n')}
    }

    public static class HealthMetricRegistry
    {
        private static readonly Dictionary<string, CanonicalHealthMetric> AliasMap = new(StringComparer.OrdinalIgnoreCase)
        {
${Array.from(csharpAliases.values()).map(item => `            { "${item.key}", CanonicalHealthMetric.${item.metric} }`).join(',\n')}
        };

        public static bool TryResolve(string alias, out CanonicalHealthMetric metric)
        {
            if (string.IsNullOrWhiteSpace(alias))
            {
                metric = default;
                return false;
            }
            return AliasMap.TryGetValue(alias.Trim(), out metric);
        }

        public static string ToKey(this CanonicalHealthMetric metric) => metric switch
        {
${Object.keys(metrics).map(k => `            CanonicalHealthMetric.${toPascalCase(k)} => "${k}"`).join(',\n')},
            _ => metric.ToString().ToLowerInvariant()
        };
    }
}
`;

const csharpTarget = path.join(__dirname, '../Models/Health/CanonicalHealthMetrics.cs');
fs.writeFileSync(csharpTarget, csharp);
console.log('Generated C# contract:', csharpTarget);

console.log('All contracts generated and deduplicated successfully!');
