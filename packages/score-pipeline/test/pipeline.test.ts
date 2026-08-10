import { describe, expect, it } from "vitest";
import { generateAlphaTex, parseMusicXml, runStructuredScorePipeline, scoreNotes } from "../src";
import { SIMPLE_MUSIC_XML } from "./fixture";

describe("MusicXML normalization", () => {
  it("normalizes pitch, rhythm, metadata, and rests", () => {
    const score = parseMusicXml(SIMPLE_MUSIC_XML);
    expect(score).toMatchObject({ title: "Known melody", partName: "Lead", tempo: 88 });
    expect(score.measures).toHaveLength(2);
    expect(score.measures[0]?.timeSignature).toEqual({ beats: 3, beatType: 4 });
    expect(scoreNotes(score).map((note) => [note.pitch, note.midi])).toEqual([
      ["C4", 60],
      ["D4", 62],
      ["E4", 64],
      ["F#4", 66],
      ["G4", 67],
    ]);
    expect(score.measures[1]?.events[0]).toMatchObject({ kind: "rest", durationQuarters: 0.5 });
  });

  it("accepts flat accidentals", () => {
    const flatXml = SIMPLE_MUSIC_XML.replace(
      "<step>C</step><octave>4</octave>",
      "<step>B</step><alter>-1</alter><octave>3</octave>",
    );
    expect(scoreNotes(parseMusicXml(flatXml))[0]).toMatchObject({ pitch: "A#3", midi: 58 });
  });

  it("rejects polyphonic chord input explicitly", () => {
    const chordXml = SIMPLE_MUSIC_XML.replace(
      "<note><pitch><step>D</step>",
      "<note><chord/><pitch><step>D</step>",
    );
    expect(() => parseMusicXml(chordXml)).toThrow(/only monophonic MusicXML/);
  });
});

describe("structured score pipeline", () => {
  it("produces candidates, an optimized path, and playable alphaTex", () => {
    const result = runStructuredScorePipeline(SIMPLE_MUSIC_XML, { profile: "balanced" });
    expect(Object.values(result.candidates).every((positions) => positions.length > 0)).toBe(true);
    expect(result.fingering.steps).toHaveLength(5);
    expect(result.alphaTex).toContain("\\staff{score tabs}");
    expect(result.alphaTex).toContain("\\ts 3 4");
    expect(result.alphaTex).toMatch(/\d+\.\d+\.4/);
    expect(result.alphaTex).toContain("r.8");
  });

  it("generates a tie marker for a tied destination", () => {
    const tiedXml = SIMPLE_MUSIC_XML
      .replace("<note><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration></note>",
        "<note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><tie type=\"stop\"/></note>")
      .replace("<note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>",
        "<note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><tie type=\"start\"/></note>");
    const result = runStructuredScorePipeline(tiedXml);
    expect(generateAlphaTex(result.score, result.fingering)).toContain("{t}");
  });
});
