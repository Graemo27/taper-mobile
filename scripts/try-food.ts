/**
 * Console harness for the food data layer.
 *
 *   node scripts/try-food.ts almond
 *   node scripts/try-food.ts "greek yogurt" 3
 *
 * Node 22.6+ strips TypeScript natively, so this needs no build step and no
 * dev dependency. Set FDC_API_KEY to avoid DEMO_KEY's 30 req/hour limit.
 */

import { FdcError, searchWithServings } from '../src/lib/food/index.ts';

const [, , query, limitArg] = process.argv;

if (!query) {
  console.error('usage: node scripts/try-food.ts <query> [limit]');
  process.exit(1);
}

const limit = limitArg ? Number(limitArg) : 5;

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
