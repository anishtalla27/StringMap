import { describe, expect, it } from "vitest";
import { optimizeFingering } from "../src";

const melody = (midis: number[]) => midis.map((midi, index) => ({ id: `n${index}`, midi }));

describe("optimizeFingering", () => {
  it("chooses a smooth single-string path for a small scale", () => {
    const result = optimizeFingering(melody([64, 66, 67, 69]), { profile: "balanced" });
    expect(result.steps.map((step) => [step.position.string, step.position.fret])).toEqual([
      [1, 0],
      [1, 2],
      [1, 3],
      [1, 5],
    ]);
    expect(result.steps.every((step) => step.candidateCount > 0)).toBe(true);
  });

  it("changes behavior through profile weights", () => {
    const notes = melody([40, 43, 59]);
    const beginner = optimizeFingering(notes, { profile: "beginner" });
    const balanced = optimizeFingering(notes, { profile: "balanced" });

    expect(beginner.steps.at(-1)?.position).toMatchObject({ string: 2, fret: 0 });
    expect(balanced.steps.at(-1)?.position).toMatchObject({ string: 3, fret: 4 });
  });

  it("preserves the source position for a tied destination", () => {
    const result = optimizeFingering([
      { id: "start", midi: 64 },
      { id: "stop", midi: 64, tieStop: true },
    ]);
    expect(result.steps[1]?.position).toEqual(result.steps[0]?.position);
  });

  it("returns an auditable component breakdown whose totals reconcile", () => {
    const result = optimizeFingering(melody([60, 62, 64]));
    const final = result.steps.at(-1)!;
    const componentTotal = result.steps.reduce((sum, step) => sum + step.incrementalCost, 0);

    expect(componentTotal).toBeCloseTo(result.totalCost);
    expect(final.transition).toEqual(expect.objectContaining({
      fretMovement: expect.any(Number),
      positionShift: expect.any(Number),
      stringChange: expect.any(Number),
      largeStretch: expect.any(Number),
    }));
  });

  it("fails clearly for an unplayable note", () => {
    expect(() => optimizeFingering(melody([30]))).toThrow(/outside this guitar's playable range/);
  });
});
