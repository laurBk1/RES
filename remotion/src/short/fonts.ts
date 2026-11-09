import { loadFont as anton } from "@remotion/google-fonts/Anton";
import { loadFont as caveat } from "@remotion/google-fonts/Caveat";
import { loadFont as inter } from "@remotion/google-fonts/Inter";

// latin-ext carries ă â î ș ț.
export const KEY_FONT = anton("normal", { weights: ["400"], subsets: ["latin", "latin-ext"] }).fontFamily;
export const BODY_FONT = inter("normal", { weights: ["700", "800", "900"], subsets: ["latin", "latin-ext"] }).fontFamily;
export const SCRIPT_FONT = caveat("normal", { weights: ["700"], subsets: ["latin", "latin-ext"] }).fontFamily;
