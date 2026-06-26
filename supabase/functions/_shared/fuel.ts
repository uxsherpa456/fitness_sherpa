// The fuel engine — calorie + macro targets from bodyweight, goal, and training day.
// Same logic the Today "What to eat today" card shows, so the coach and the card agree.

export interface FuelInput {
  bodyweight_lb?: number;
  goal?: "lose" | "maintain" | "gain";
  training_day?: "rest" | "easy" | "quality" | "long";
}

export interface Fuel {
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  deficit: number;       // kcal vs maintenance (negative = deficit)
  maintenance: number;
  training_day: string;
  goal: string;
  rationale: string;
}

export function computeFuel(o: FuelInput, base: Required<FuelInput>): Fuel {
  const w = o.bodyweight_lb ?? base.bodyweight_lb;
  const goal = o.goal ?? base.goal;
  const day = o.training_day ?? base.training_day;

  const dayFactor: Record<string, number> = { rest: 13.5, easy: 14.5, quality: 15.5, long: 16.5 };
  const maintenance = Math.round(w * (dayFactor[day] ?? 15));
  const adj = goal === "lose" ? -500 : goal === "gain" ? 300 : 0;   // ~1 lb/week loss
  const calories = Math.round((maintenance + adj) / 10) * 10;

  const protein_g = Math.round(w * 0.95);  // ~1 g/lb — protect strength in a deficit
  const fat_g = Math.round(w * 0.32);
  const carbs_g = Math.max(0, Math.round((calories - protein_g * 4 - fat_g * 9) / 4));

  return {
    calories, protein_g, carbs_g, fat_g,
    deficit: adj, maintenance, training_day: day, goal,
    rationale: `${goal === "lose" ? Math.abs(adj) + " kcal deficit" : goal === "gain" ? "surplus" : "maintenance"} on a ${day} day; protein held at ${protein_g} g (~1 g/lb) to protect strength`,
  };
}
