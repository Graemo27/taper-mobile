/**
 * Recent — the foods you have logged before, offered before you type.
 *
 * The board puts this on the empty search screen, and the reason is in the
 * research: eating repeats. Retyping "eggs, scrambled" every morning is the
 * friction that stops people recording, so the second time a food is logged
 * should not cost a search.
 *
 * Rows carry no `Food` to hand over — a journal entry stores what was shown,
 * not the nutrient table behind it — so a tap navigates on the id alone and
 * Food detail fetches it.
 */

import { router } from 'expo-router';
import { Keyboard, StyleSheet, Text, View } from 'react-native';

import { FoodCard, FoodCardRow } from '@/components/food-card';
import { useFavourites } from '@/lib/supabase/favourites';
import type { RecentFood } from '@/lib/supabase/journal';
import { colors, fontFamily, fontSize, spacing } from '@/theme';

export function RecentFoods({ foods }: { foods: RecentFood[] }) {
  const favourites = useFavourites();
  if (foods.length === 0) return null;

  return (
    <View style={styles.section}>
      <Text style={styles.heading}>Recent</Text>

      <FoodCard>
        {foods.map((food) => (
          <FoodCardRow
            key={food.fdcId}
            name={food.name}
            // What the entry recorded, not a fresh reading of the food. It is
            // the serving that was actually logged, which is the one worth
            // offering again.
            serving={food.servingLabel ?? ''}
            kcal={food.kcal === null ? null : `${food.kcal} kcal`}
            favourite={favourites.has(food.fdcId)}
            onPress={() => {
              Keyboard.dismiss();
              router.push(`/food/${food.fdcId}`);
            }}
          />
        ))}
      </FoodCard>
    </View>
  );
}

const styles = StyleSheet.create({
  section: { gap: spacing['2.5'] },
  // Heavier and darker than the "5 matches" line above results: that one
  // reports on a search, this one titles a list.
  heading: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.textPrimary,
  },
});
