/**
 * Console harness for the food data layer.
 *
 *   npm run food -- almond
 *   npm run food -- "greek yogurt" 3
 *
 * Node 22.18+ strips TypeScript without a flag, so this needs no build step and
 * no dev dependency. See engines.node in package.json.
 *
 * Put FDC_API_KEY in .env to avoid DEMO_KEY's 30 req/hour limit. Node does not
 * read .env on its own, hence the explicit load below.
 */

import { FdcError, searchWithServings } from '../src/lib/food/index.ts';

try {
  process.loadEnvFile();
} catch {
  // No .env — fall through to DEMO_KEY.
}

const [, , query, limitArg] = process.argv;

if (!query) {
  console.error('usage: npm run food -- <query> [limit]');
  process.exit(1);
}

const limit = limitArg === undefined ? 5 : Number(limitArg);

if (!Number.isSafeInteger(limit) || limit < 1) {
  console.error(`limit must be a positive integer, got "${limitArg}"`);
  process.exit(1);
}

function fmt(value: number | null, unit: string): string {
  return value === null ? '—' : `${value}${unit}`;
}

const foods = await searchWithServings(query, limit).catch((err: unknown) => {
  if (err instanceof FdcError) {
    console.error(`\n  ${err.message}\n`);
    process.exit(1);
  }
  throw err;
});

if (foods.length === 0) {
  console.log(`\n  No results for "${query}".\n`);
  process.exit(0);
}

console.log(`\n  ${foods.length} match(es) for "${query}"\n`);

for (const food of foods) {
  const serving = food.portion
    ? `${food.portion.label} · ${Math.round(food.portion.grams)} g`
    : 'no serving listed';
  const n = food.perServing ?? food.per100g;

  console.log(`  ${food.name}`);
  console.log(`    ${serving}${food.perServing ? '' : '  (figures are per 100 g)'}`);
  console.log(
    `    ${fmt(n.kcal, ' kcal')}   ${fmt(n.proteinG, ' g')} protein   ${fmt(n.fibreG, ' g')} fibre`,
  );
  console.log(`    ${food.dataType} · fdcId ${food.fdcId}`);
  console.log();
}
