/**
 * Search results — the card of foods a query matched.
 *
 * The card and the row live in `food-card.tsx`, shared with the recent foods on
 * the empty search screen. What is here is what makes a result a result: the
 * hand-off of the resolved food before navigating, so Food detail has nothing
 * to fetch.
 */

import { router } from 'expo-router';
import { Keyboard } from 'react-native';

import { FoodCard, FoodCardRow } from '@/components/food-card';
import { servingSummary } from '@/lib/food/format';
import { selectFood } from '@/lib/food/selection';
import { useFavourites } from '@/lib/supabase/favourites';
import type { Food } from '@/lib/food/types';

export function FoodList({ foods }: { foods: Food[] }) {
  const favourites = useFavourites();

  return (
    <FoodCard>
      {foods.map((food) => {
        const nutrients = food.perServing ?? food.per100g;

        return (
          <FoodCardRow
            key={food.fdcId}
            name={food.name}
            serving={servingSummary(food.portion)}
            kcal={nutrients.kcal === null ? null : `${Math.round(nutrients.kcal)} kcal`}
            favourite={favourites.has(food.fdcId)}
            onPress={() => {
              // The field is autoFocused, and the router marks the screen behind
              // it aria-hidden on push — leaving focus inside a hidden subtree.
              // Also just correct on native: the keyboard should not survive the
              // screen it belongs to.
              Keyboard.dismiss();
              selectFood(food);
              router.push(`/food/${food.fdcId}`);
            }}
          />
        );
      })}
    </FoodCard>
  );
}
