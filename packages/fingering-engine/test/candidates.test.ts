import { describe, expect, it } from "vitest";
import { enumeratePositions, STANDARD_TUNING } from "../src";

describe("enumeratePositions", () => {
  it("enumerates every standard-tuning position for E4", () => {
    expect(enumeratePositions(64, STANDARD_TUNING, 24)).toEqual([
      { string: 1, fret: 0, midi: 64 },
      { string: 2, fret: 5, midi: 64 },
      { string: 3, fret: 9, midi: 64 },
      { string: 4, fret: 14, midi: 64 },
      { string: 5, fret: 19, midi: 64 },
      { string: 6, fret: 24, midi: 64 },
    ]);
  });

  it("omits negative and above-limit frets", () => {
    expect(enumeratePositions(60)).toEqual([
      { string: 2, fret: 1, midi: 60 },
      { string: 3, fret: 5, midi: 60 },
      { string: 4, fret: 10, midi: 60 },
      { string: 5, fret: 15, midi: 60 },
      { string: 6, fret: 20, midi: 60 },
    ]);
  });

  it("returns no candidates below the guitar range", () => {
    expect(enumeratePositions(39)).toEqual([]);
  });
});
