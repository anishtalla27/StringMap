"""Encode StringMap's own guitar arrangements. Historical-source review is separate.
Pitch tokens are sounding pitches; durations are in quarter-note units.
Do not regenerate independent review references from this script.
"""
from pathlib import Path
import json, xml.etree.ElementTree as E
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'apps/ios/StringMap/Resources/Songbook'
# Compact authoring notation: pitch/duration, | measures. Partial pickup/final bars
# are explicitly marked implicit in MusicXML, never padded with invented silence.
SONGS=[]
def song(slug,title,composer,bpm,meter,key,melody,harmony,source,edition):
    SONGS.append(dict(id=slug,title=title,composer=composer,tempo=bpm,meter=meter,key=key,melody=melody,harmony=harmony,sourceURL=source,sourceEdition=edition))

song('amazing-grace','Amazing Grace','Traditional · New Britain',84,(3,4),1,
'D3/1 | G3/2 B3/0.5 G3/0.5 | B3/2 A3/1 | G3/2 E3/1 | D3/2 D3/1 | G3/2 B3/0.5 G3/0.5 | B3/2 A3/0.5 B3/0.5 | D4/2 A3/0.5 B3/0.5 | D4/2 B3/0.5 A3/0.5 | G3/2 E3/0.5 D3/0.5 | G3/2 E3/0.5 D3/0.5 | D3/2 D3/1 | G3/2 B3/0.5 G3/0.5 | B3/2 A3/1 | G3/3',
'G G G C G G G D G C C G G D G',
'https://www.ccel.org/ccel/walker/harmony.html','New Britain, The Southern Harmony (1847 edition), p.8, tenor melody. Historical fourteen-bar setting with pickup, one pass using the final ending. New G-major guitar harmony; no hymn text included.')
song('auld-lang-syne','Auld Lang Syne','Traditional Scottish',88,(4,4),1,
'D3/1 | G3/1.5 G3/.5 G3/1 B3/1 | A3/1.5 G3/.5 A3/1 B3/1 | G3/1 G3/1 B3/1 D4/1 | E4/3 G4/1 | D4/1.5 B3/.5 B3/1 G3/1 | A3/1.5 G3/.5 A3/1 B3/1 | G3/1.5 E3/.5 E3/1 D3/1 | G3/3 E4/1 | D4/.5 B3/1.5 B3/1 G3/1 | A3/1.5 G3/.5 A3/1 B3/1 | D4/.5 B3/1.5 B3/1 D4/1 | E4/3 G4/1 | D4/1.5 B3/.5 B3/1 G3/1 | A3/1.5 G3/.5 A3/1 B3/1 | G3/.5 E3/1.5 E3/1 D3/1 | G3/3',
'G G D G C G D C G G D G C G D C G',
'https://deriv.nls.uk/dcn23/9041/90414454.23.pdf','Traditional familiar tune, one verse and chorus from The Popular Songs of Scotland (1887), pp.240–241, retaining its Scotch snaps. Note values doubled for quarter-note counting; new guitar harmony.')
song('greensleeves','Greensleeves','Traditional English',90,(6,8),0,
'A3/.5 | C4/1 D4/.5 E4/.75 F4/.25 E4/.5 | D4/1 B3/.5 G3/.75 A3/.25 B3/.5 | C4/1 A3/.5 A3/.75 G#3/.25 A3/.5 | B3/1 G#3/.5 E3/1 A3/.5 | C4/1 D4/.5 E4/.75 F4/.25 E4/.5 | D4/1 B3/.5 G3/.75 A3/.25 B3/.5 | C4/.75 B3/.25 A3/.5 G#3/.75 F#3/.25 G#3/.5 | A3/1 A3/.5 A3/1 R/.5 | G4/1.5 G4/.75 F#4/.25 E4/.5 | D4/1 B3/.5 G3/.75 A3/.25 B3/.5 | C4/1 A3/.5 A3/.75 G#3/.25 A3/.5 | B3/1 G#3/.5 E3/1.5 | G4/1.5 G4/.75 F#4/.25 E4/.5 | D4/1 B3/.5 G3/.75 A3/.25 B3/.5 | C4/.75 B3/.25 A3/.5 G#3/.75 F#3/.25 G#3/.5 | A3/1.5 A3/1.5',
'Am Am G Am E Am G E Am C G Am E C G E Am',
'https://en.wikisource.org/wiki/A_Dictionary_of_Music_and_Musicians/Greensleeves','Historical Greensleeves tune documented by Chappell; own A-minor guitar setting.')
song('sweet-afton','Flow Gently, Sweet Afton','Jonathan E. Spilman',84,(3,4),1,
'D3/1 | G3/1 G3/1 B3/.5 A3/.5 | G3/1 G3/1 D3/1 | E3/1 G3/1 E3/1 | D3/2 D3/1 | G3/1 G3/1 A3/1 | B3/1 B3/1 D4/1 | C4/1 A3/1 F#3/1 | G3/2 D3/1 | G3/1 G3/1 B3/.5 A3/.5 | G3/1 G3/1 D3/1 | E3/1 C4/1 E3/1 | D3/2 D3/1 | G3/1 G3/1 A3/1 | B3/1 D4/1 C4/1 | D3/1 D3/1 F#3/1 | G3/1 R/1 F#3/.5 G3/.5 | A3/1 A3/1 D4/1 | A3/1 A3/1 F#3/.5 G3/.5 | A3/1 G3/1 E3/1 | D3/2 F#3/.5 G3/.5 | A3/1 A3/1 D4/1 | A3/1 A3/1 F#3/1 | G3/.5 F#3/.5 G3/.5 A3/.5 B3/.5 C#4/.5 | D4/2 E4/1 | D4/1 B3/1 B3/.5 A3/.5 | G3/1 G3/1 D3/1 | E3/1 C4/1 E3/1 | D3/2 D3/1 | G3/1 G3/1 A3/1 | B3/1 D4/1 C4/1 | D3/1 D3/1 F#3/1 | G3/2',
'G G G C G G G D G G G C G G G D G D D D G D D A D G G C G G G D G',
'https://levysheetmusic.mse.jhu.edu/collection/063/040','George Willig, Philadelphia (1838), Levy collection 063/040. Complete vocal tune once in G; piano introduction/postlude and small ornaments omitted, final rest trimmed. New guitar harmony; no lyrics or source images bundled.')
song('ash-grove','The Ash Grove','Traditional Welsh',84,(3,4),1,
'G3/1 B3/1 D4/1 | B3/1 G3/1 G3/1 | A3/.75 B3/.25 C4/1 A3/1 | F#3/1 D3/1 D3/1 | G3/1 B3/.5 G3/.5 A3/.5 F#3/.5 | G3/1 E3/1 C3/1 | D3/1 G3/1 F#3/1 | G3/3 | A3/1 A3/.5 B3/.5 C4/.5 D4/.5 | C4/1 B3/1 A3/1 | G3/.5 A3/.5 B3/.5 C4/.5 B3/.5 C4/.5 | B3/1 A3/1 G3/1 | F#3/.5 G3/.5 A3/.5 B3/.5 A3/.5 B3/.5 | A3/1 G3/1 F#3/1 | E3/1 D4/1 C#4/1 | D4/2 R/1 | G4/1.5 F#4/.5 E4/.5 G4/.5 | D4/1 B3/1 G3/1 | A3/1 C4/.5 A3/.5 B3/.5 G3/.5 | A3/1 F#3/1 D3/1 | G3/.75 A3/.25 B3/.5 G3/.5 A3/.5 F#3/.5 | G3/1 E3/1 C3/1 | D3/1 G3/1 F#3/1 | G3/3',
'G G C D G C D G C C G G D D A D G G C D G C D G',
'https://archive.org/details/The_Bardic_Museum','Llwyn-onn, The Bardic Museum (1802), p.83. Complete 24-bar principal tune once, including its developed middle section; small ornaments and subsequent variation omitted. New guitar accompaniment.')
song('blue-bells','The Blue Bells of Scotland','Traditional Scottish',88,(4,4),0,
'G3/1 | C4/2 B3/1 A3/1 | G3/2 A3/1 C4/1 | E3/1 E3/1 F3/1 D3/1 | C3/2 R/1 G3/1 | C4/2 B3/1 A3/1 | G3/2 A3/1 C4/1 | E3/1 E3/1 F3/1 D3/1 | C3/2 R/1 G3/1 | E3/1 C3/1 E3/1 G3/1 | C4/2 A3/1 C4/1 | B3/1 G3/1 A3/1 F#3/1 | G3/2 G3/1 G3/1 | C4/2 B3/1 A3/1 | G3/2 A3/1 C4/1 | E3/1 E3/1 F3/1 D3/1 | C3/2 R/1',
'C C G C C C G C C F F G C C G C C',
'https://levysheetmusic.mse.jhu.edu/collection/031/034','The Blue Bell of Scotland, G. Willig, Philadelphia, circa 1800–1801, Levy 031/034. Early vocal version: first strain twice, second strain once; introduction/postlude and small ornaments excluded. New guitar harmony.')
song('home-sweet-home','Home, Sweet Home','Henry R. Bishop',84,(2,4),0,
'C3/.375 D3/.125 | E3/.75 F3/.25 F3/.75 G3/.25 | G3/.75 E3/.25 E3/1 | F3/.75 E3/.25 F3/.5 D3/.5 | E3/1.5 C3/.25 D3/.25 | E3/.75 F3/.25 F3/.75 G3/.25 | G3/1 E3/.5 G3/.5 | F3/.75 E3/.25 F3/.5 D3/.5 | C3/1 R/.5 G3/.5 | C4/.75 B3/.25 A3/.75 G3/.25 | G3/1 E3/.5 G3/.5 | F3/.75 E3/.25 F3/.5 D3/.5 | E3/1.5 G3/.5 | C4/.75 B3/.25 A3/.75 G3/.25 | G3/1 E3/.5 G3/.5 | G3/.5 F3/1 D3/.5 | C3/2 | G3/2 | F3/1 D3/1 | C3/.5 R/.5 D3/.5 R/.5 | E3/1 R/.5 G3/.5 | C4/.75 B3/.25 A3/.75 G3/.25 | G3/1 E3/.5 G3/.5 | F3/.75 E3/.25 F3/.5 D3/.5 | C3/2',
'C C C G C C C G C F C G C F C G C C G G C F C G C',
'https://www.gutenberg.org/files/21566/21566-h/images/home.pdf','Bishop’s Clari melody (1823), compared with the vocal staff in the McKinley edition, circa 1914. One complete verse and refrain; piano introduction and postlude excluded. Melody transposed F to C, new guitar accompaniment.')
song('long-long-ago','Long, Long Ago','Thomas Haynes Bayly',88,(4,4),0,
'C3/1 C3/.5 D3/.5 E3/1 E3/.5 F3/.5 | G3/1 A3/.5 G3/.5 E3/1 R/1 | G3/1 F3/.5 E3/.5 D3/1 R/1 | F3/1 E3/.5 D3/.5 C3/1 R/1 | C3/1 C3/.5 D3/.5 E3/1 E3/.5 F3/.5 | G3/1 A3/.5 G3/.5 E3/1 R/1 | G3/1 F3/.5 E3/.5 D3/1 E3/.5 D3/.5 | C3/2 R/2 | G3/.5 F3/.5 F3/.5 E3/.5 D3/1 G2/.5 G2/.5 | E3/.5 D3/.5 D3/.5 C3/.5 B2/1 R/1 | G3/.5 F3/.5 F3/.5 E3/.5 D3/1 G2/.5 G2/.5 | E3/.5 D3/.5 D3/.5 C3/.5 B2/1 R/1 | C3/1 C3/.5 D3/.5 E3/1 E3/.5 F3/.5 | G3/1 A3/.5 G3/.5 E3/1 R/1 | G3/1 F3/.5 E3/.5 D3/1 E3/.5 D3/.5 | C3/2 R/2',
'C C G C C C G C G C G C C C G C',
'https://imslp.org/wiki/Long%2C_Long_Ago_(Bayly%2C_Thomas_Haynes)','Cramer, Addison & Beale edition (circa 1839); Bayly died 1839.')
song('oh-susanna','Oh! Susanna','Stephen Foster',100,(2,4),0,
'C3/0.25 D3/0.25 | E3/0.5 G3/0.5 G3/0.5 A3/0.5 | G3/0.5 E3/0.5 C3/0.75 D3/0.25 | E3/0.5 E3/0.5 D3/0.5 C3/0.5 | D3/1.5 C3/0.25 D3/0.25 | E3/0.5 G3/0.5 G3/0.75 A3/0.25 | G3/0.5 E3/0.5 C3/0.75 D3/0.25 | E3/0.5 E3/0.5 D3/0.5 D3/0.5 | C3/1.5 C3/0.25 D3/0.25 | E3/0.5 G3/0.5 G3/0.5 A3/0.5 | G3/0.5 E3/0.5 C3/0.75 D3/0.25 | E3/0.5 E3/0.5 D3/0.5 C3/0.5 | D3/1.5 C3/0.25 D3/0.25 | E3/0.5 G3/0.5 G3/0.5 A3/0.5 | G3/0.5 E3/0.5 C3/0.75 D3/0.25 | E3/0.5 E3/0.5 D3/0.5 D3/0.5 | C3/1 R/1 | F3/1 F3/1 | A3/0.5 A3/1 A3/0.5 | G3/0.5 G3/0.5 E3/0.5 C3/0.5 | D3/1.5 C3/0.25 D3/0.25 | E3/0.5 G3/0.5 G3/0.5 A3/0.5 | G3/0.5 E3/0.5 C3/0.75 D3/0.25 | E3/0.5 E3/0.5 D3/0.5 D3/0.5 | C3/1 R/1',
'C C C C G C C G C C C C G C C G C F F C G C C G C',
'https://archive.org/details/OhSusannaOriginal1848SheetMusic','Oh! Susanna, 1848 engraved edition, vocal staff pp.2–4. Complete 16-bar verse and 8-bar chorus with pickup; piano material excluded. Original C-major guitar accompaniment.')
song('home-on-range','Home on the Range','Traditional · Daniel E. Kelley',90,(6,8),1,
'D3/.5 | D3/.5 G3/.5 A3/.5 B3/1 G3/.25 F#3/.25 | E3/.75 C4/.25 C4/.5 C4/1 C4/.25 C4/.25 | D4/1 G3/.375 G3/.125 G3/.75 F#3/.25 G3/.5 | A3/2.5 D3/.5 | D3/.5 G3/.5 A3/.5 B3/1 G3/.25 F#3/.25 | E3/.75 C4/.25 C4/.5 C4/1 C4/.25 C4/.25 | B3/.75 A3/.25 G3/.5 F#3/.75 G3/.25 A3/.5 | G3/3 | D4/1.5 C4/.5 B3/.75 A3/.25 | B3/2.5 D3/.25 D3/.25 | D3/.5 G3/.75 G3/.25 G3/.5 F#3/.5 G3/.5 | A3/2.5 A3/.5 | D3/.5 G3/.5 A3/.5 B3/1 G3/.25 F#3/.25 | E3/.5 C4/.5 C4/.5 C4/1 C4/.375 C4/.125 | B3/.75 A3/.25 G3/.5 F#3/.75 G3/.25 A3/.5 | G3/3',
'G G C G D G C D G G G G D G C D G',
'https://www.gutenberg.org/ebooks/21300','Cowboy Songs and Other Frontier Ballads, John A. Lomax (1910), A Home on the Range. Complete verse and refrain in its historical six-eight rhythm, transposed E-flat to G; new guitar accompaniment. Held ties are rendered without a second attack.')
song('ode-to-joy','Ode to Joy — theme','Ludwig van Beethoven',96,(4,4),0,
'E3/1 E3/1 F3/1 G3/1 | G3/1 F3/1 E3/1 D3/1 | C3/1 C3/1 D3/1 E3/1 | E3/1.5 D3/0.5 D3/2 | E3/1 E3/1 F3/1 G3/1 | G3/1 F3/1 E3/1 D3/1 | C3/1 C3/1 D3/1 E3/1 | D3/1.5 C3/0.5 C3/2 | D3/1 D3/1 E3/1 C3/1 | D3/1 E3/0.5 F3/0.5 E3/1 C3/1 | D3/1 E3/0.5 F3/0.5 E3/1 D3/1 | C3/1 D3/1 G2/2 | E3/1 E3/1 F3/1 G3/1 | G3/1 F3/1 E3/1 F3/0.5 D3/0.5 | C3/1 C3/1 D3/1 E3/1 | D3/1.5 C3/0.5 C3/2',
'C G C G C G C C G G G G C G C C',
'https://www.hymnologyarchive.com/joyful-joyful-we-adore-thee','Beethoven’s joy theme (1824), complete sixteen-bar melody as printed in The Hymnal (Presbyterian Board, 1911), no.115. Original C-major guitar setting; Amen and hymn accompaniment excluded.')
song('fur-elise','Für Elise — opening theme','Ludwig van Beethoven',72,(3,8),0,
'E4/.25 D#4/.25 | E4/.25 D#4/.25 E4/.25 B3/.25 D4/.25 C4/.25 | A3/.5 R/.25 C3/.25 E3/.25 A3/.25 | B3/.5 R/.25 E3/.25 G#3/.25 B3/.25 | C4/.5 R/.25 E3/.25 E4/.25 D#4/.25 | E4/.25 D#4/.25 E4/.25 B3/.25 D4/.25 C4/.25 | A3/.5 R/.25 C3/.25 E3/.25 A3/.25 | B3/.5 R/.25 E3/.25 C4/.25 B3/.25 | A3/1',
'E E Am E Am E Am E Am',
'https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=931','WoO 59, complete opening eight-bar theme once, including pickup and first ending. Breitkopf & Härtel (1888), compared with the public-domain Mutopia transcription by Stelios Samelis; right-hand line lowered one octave, new guitar accompaniment.')
song('minuet-g','Minuet in G','Christian Petzold',96,(3,4),1,
'D4/1 G3/.5 A3/.5 B3/.5 C4/.5 | D4/1 G3/1 G3/1 | E4/1 C4/.5 D4/.5 E4/.5 F#4/.5 | G4/1 G3/1 G3/1 | C4/1 D4/.5 C4/.5 B3/.5 A3/.5 | B3/1 C4/.5 B3/.5 A3/.5 G3/.5 | F#3/1 G3/.5 A3/.5 B3/.5 G3/.5 | A3/3 | D4/1 G3/.5 A3/.5 B3/.5 C4/.5 | D4/1 G3/1 G3/1 | E4/1 C4/.5 D4/.5 E4/.5 F#4/.5 | G4/1 G3/1 G3/1 | C4/1 D4/.5 C4/.5 B3/.5 A3/.5 | B3/1 C4/.5 B3/.5 A3/.5 G3/.5 | A3/1 B3/.5 A3/.5 G3/.5 F#3/.5 | G3/3 | B4/1 G4/.5 A4/.5 B4/.5 G4/.5 | A4/1 D4/.5 E4/.5 F#4/.5 D4/.5 | G4/1 E4/.5 F#4/.5 G4/.5 D4/.5 | C#4/1 B3/.5 C#4/.5 A3/1 | A3/.5 B3/.5 C#4/.5 D4/.5 E4/.5 F#4/.5 | G4/1 F#4/1 E4/1 | F#4/1 A3/1 C#4/1 | D4/3 | D4/1 G3/.5 F#3/.5 G3/1 | E4/1 G3/.5 F#3/.5 G3/1 | D4/1 C4/1 B3/1 | A3/.5 G3/.5 F#3/.5 G3/.5 A3/1 | D3/.5 E3/.5 F#3/.5 G3/.5 A3/.5 B3/.5 | C4/1 B3/1 A3/1 | B3/.5 D4/.5 G3/1 F#3/1 | G3/3',
'G G C G C G D D G G C G C G D G G D Em A D Em A D G C G D D C D G',
'https://imslp.org/wiki/Minuet_in_G_major,_BWV_Anh.114_(Pezold,_Christian)','Anna Magdalena Bach notebook (1725), BWV Anh. 114. Complete two-section upper voice once; ornaments omitted in this guitar setting. Compared with Bach-Gesellschaft via Allen Garvin’s public-domain Mutopia transcription.')
song('brahms-lullaby','Brahms’ Lullaby','Johannes Brahms',78,(3,4),0,
'E3/.5 E3/.5 | G3/1.5 E3/.5 E3/1 | G3/1 R/1 E3/.5 G3/.5 | C4/1 B3/1.5 A3/.5 | A3/1 G3/1 D3/.5 E3/.5 | F3/1 D3/1 D3/.5 E3/.5 | F3/1 R/1 D3/.5 F3/.5 | B3/.5 A3/.5 G3/1 B3/1 | C4/1 R/1 C3/.5 C3/.5 | C4/2 A3/.5 F3/.5 | G3/2 E3/.5 C3/.5 | F3/1 G3/1 A3/1 | G3/2 C3/.5 C3/.5 | C4/2 A3/.5 F3/.5 | G3/2 E3/.5 C3/.5 | F3/1 E3/1 D3/1 | C3/2',
'C C C F G Dm Dm G C F C F C F C G C',
'https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=1037','Wiegenlied, Op.49 No.4 (1868). Complete vocal melody once, transposed E-flat to C; introductory rests and small grace ornaments omitted. Compared with the public-domain voice/piano transcription; new guitar accompaniment.')
song('twinkle','Twinkle, Twinkle, Little Star','Traditional French melody',96,(4,4),0,
'C3/1 C3/1 G3/1 G3/1 | A3/1 A3/1 G3/2 | F3/1 F3/1 E3/1 E3/1 | D3/1 D3/1 C3/2 | G3/1 G3/1 F3/1 F3/1 | E3/1 E3/1 E3/1 D3/1 | G3/1 G3/1 F3/1 F3/1 | E3/1 E3/1 E3/1 D3/1 | C3/1 C3/1 G3/1 G3/1 | A3/1 A3/1 G3/2 | F3/1 F3/1 E3/1 E3/1 | D3/1 D3/1 C3/2',
'C F C C C G C G C F C C',
'https://www.gutenberg.org/ebooks/42711','Ah! vous dirai-je, maman, historical French melody from Vieilles chansons pour les petits enfants (1883). The middle cadence follows that edition. Original guitar harmonization; no Widor accompaniment copied.')
song('frere-jacques','Frère Jacques','Traditional French',100,(4,4),0,
'C3/1 D3/1 E3/1 C3/1 | C3/1 D3/1 E3/1 C3/1 | E3/1 F3/1 G3/2 | E3/1 F3/1 G3/2 | G3/.5 A3/.5 G3/.5 F3/.5 E3/1 C3/1 | G3/.5 A3/.5 G3/.5 F3/.5 E3/1 C3/1 | C3/1 G2/1 C3/2 | C3/1 G2/1 C3/2',
'C C C C C C G C',
'https://www.gutenberg.org/ebooks/42711','Vieilles chansons pour les petits enfants (1883), Frère Jacques; melody only, not Widor’s accompaniment.')
song('mary-lamb','Mary Had a Little Lamb','Traditional · Hobart version',72,(2,4),0,
'E3/.75 D3/.25 C3/.5 D3/.5 | E3/.5 E3/.5 E3/1 | D3/.5 D3/.5 D3/1 | E3/.5 E3/.5 E3/1 | E3/.75 D3/.25 C3/.5 D3/.5 | E3/.5 E3/.5 E3/.5 E3/.5 | D3/.5 D3/.5 E3/.75 D3/.25 | C3/1.5 R/.5',
'C C G C C C G C',
'https://archive.org/details/carminacollegens00wait','Carmina Collegensia (1876 expanded edition), supplement p.55, Hobart version. First complete verse only, retaining its dotted rhythm; later medley excluded. Original guitar harmony, no lyrics.')
song('london-bridge','London Bridge','Traditional English',100,(4,4),0,
'G3/1.5 A3/0.5 G3/1 F3/1 | E3/1 F3/1 G3/2 | D3/1 E3/1 F3/2 | E3/1 F3/1 G3/2 | G3/1.5 A3/0.5 G3/1 F3/1 | E3/1 F3/1 G3/2 | D3/2 E3/1.5 D3/0.5 | D3/1 C3/2 R/1',
'C C G C C C G C',
'https://en.wikisource.org/wiki/Page:Singing_games.djvu/14','Singing Games, Josephine Pollard (1890), p.100. Complete familiar eight-bar tune in its historical cadence variant. Note values doubled into 4/4; original guitar accompaniment.')
song('row-your-boat','Row, Row, Row Your Boat','Traditional · Eliphalet Oram Lyte tune',96,(6,8),0,
'C3/1.5 C3/1.5 | C3/1 D3/0.5 E3/1.5 | E3/1 E3/0.5 E3/1 F3/0.5 | G3/3 | C4/0.5 C4/0.5 C4/0.5 G3/0.5 G3/0.5 G3/0.5 | E3/0.5 E3/0.5 E3/0.5 C3/0.5 C3/0.5 C3/0.5 | G3/1 F3/0.5 E3/1 D3/0.5 | C3/3',
'C C C C C C G C',
'https://archive.org/details/franklinsquares04mccagoog/page/n73/mode/1up','Franklin Square Song Collection (1881), p.69, E. O. Lyte round. One complete voice; historical 6/8 version with repeated third-degree notes in bar 3. Original guitar harmony.')
song('drink-to-me','Drink to Me Only with Thine Eyes','Traditional English',84,(6,8),1,
'B3/.5 B3/.5 B3/.5 C4/1 C4/.5 | D4/.5 C4/.5 B3/.5 A3/.5 B3/.5 C4/.5 | D4/.5 G3/.5 C4/.5 B3/1 A3/.5 | G3/3 | B3/.5 B3/.5 B3/.5 C4/1 C4/.5 | D4/.5 C4/.5 B3/.5 A3/.5 B3/.5 C4/.5 | D4/.5 G3/.5 C4/.5 B3/1 A3/.5 | G3/2.5 D4/.5 | D4/.5 B3/.5 D4/.5 G4/1 D4/.5 | D4/.5 B3/.5 D4/.5 D4/1 D4/.5 | E4/1 D4/.5 C4/1 B3/.5 | B3/1.5 A3/1.5 | B3/.5 B3/.5 B3/.5 C4/1 C4/.5 | D4/.5 C4/.5 B3/.5 A3/.5 B3/.5 C4/.5 | D4/.5 G3/.5 C4/.5 B3/1 A3/.5 | G3/3',
'G C D G G C D G G G C D G C D G',
'https://levysheetmusic.mse.jhu.edu/collection/038/040','Anonymous eighteenth-century glee melody, complete tune with its two initial endings. Compared with the historical Carr edition and Cambridge source transcription. New guitar harmony; no existing glee parts or lyrics included.')

OPEN={1:64,2:59,3:55,4:50,5:45,6:40}
# Independent authored guitar grips: string/fret/fretting finger.
GRIPS={'C':[(5,3,3),(4,2,2),(3,0,0),(2,1,1),(1,0,0)],'G':[(6,3,2),(5,2,1),(4,0,0),(3,0,0),(2,0,0),(1,3,3)],'D':[(4,0,0),(3,2,1),(2,3,3),(1,2,2)],'Am':[(5,0,0),(4,2,2),(3,2,3),(2,1,1),(1,0,0)],'Em':[(6,0,0),(5,2,2),(4,2,3),(3,0,0),(2,0,0),(1,0,0)],'E':[(6,0,0),(5,2,2),(4,2,3),(3,1,1),(2,0,0),(1,0,0)],'A':[(5,0,0),(4,2,1),(3,2,2),(2,2,3),(1,0,0)],'F':[(4,3,3),(3,2,2),(2,1,1),(1,1,1)],'Dm':[(4,0,0),(3,2,2),(2,3,3),(1,1,1)]}
def sub(p,t,v=None,**a):
 n=E.SubElement(p,t,{k:str(v) for k,v in a.items()})
 if v is not None:n.text=str(v)
 return n
def pitch(token):
 if token=='R':return None
 return 12*(int(token[-1])+1)+{'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[token[0]]+(1 if '#' in token else -1 if 'b' in token else 0)
def position(midi):
 candidates=[(s,midi-o) for s,o in OPEN.items() if 0<=midi-o<=12]
 s,f=min(candidates,key=lambda x:(max(0,x[1]-4)*4+x[1],x[0]))
 # Above first position, use a fifth-position hand rather than claiming that
 # every high fret is played with the little finger.
 return s,f,(0 if f==0 else f if f<=4 else min(f-4,4))
def main():
 OUT.mkdir(parents=True,exist_ok=True);catalog=[]
 expected={item['id']+'-'+kind+'.musicxml' for item in SONGS for kind in ['melody','chords']}
 for old in OUT.glob('*.musicxml'):
  if old.name not in expected:old.unlink()
 for item in SONGS:
  bars=[[ (p,float(d)) for p,d in (token.split('/') for token in b.split())] for b in item['melody'].split('|')]
  chords=item['harmony'].split(); assert len(chords)==len(bars),(item['id'],len(chords),len(bars))
  normal=item['meter'][0]*4/item['meter'][1]
  for i,b in enumerate(bars):assert sum(d for p,d in b)==normal or i in [0,len(bars)-1],(item['id'],i,sum(d for p,d in b),normal)
  songdata={k:item[k] for k in ['id','title','composer','sourceURL','sourceEdition']};songdata['difficulty']='Developing' if item['id'] in ['minuet-g','fur-elise','greensleeves'] else 'Beginner';songdata['arrangements']=[]
  for kind in ['melody','chords']:
   resource=item['id']+'-'+kind;root=E.Element('score-partwise',version='4.0')
   sub(sub(root,'work'),'work-title',item['title']+' · '+kind.title());sub(sub(root,'identification'),'creator',item['composer'],type='composer')
   sub(sub(sub(root,'part-list'),'score-part',id='P1'),'part-name','Guitar');part=sub(root,'part',id='P1')
   positions={};fingers={};events=[];labels=[];globalq=0
   for mi,bar in enumerate(bars):
    length=sum(d for p,d in bar);m=sub(part,'measure',number=str(mi+1),**({'implicit':'yes'} if length!=normal else {}));a=sub(m,'attributes');sub(a,'divisions',8);sub(sub(a,'key'),'fifths',item['key']);t=sub(a,'time');sub(t,'beats',item['meter'][0]);sub(t,'beat-type',item['meter'][1]);c=sub(a,'clef');sub(c,'sign','G');sub(c,'line',2);tr=sub(a,'transpose');sub(tr,'diatonic',0);sub(tr,'chromatic',0);sub(tr,'octave-change',-1)
    if mi==0:sub(sub(m,'direction'),'sound',tempo=item['tempo'])
    sequence=[(pitch(p),d,False,None) for p,d in bar]
    if kind=='chords':
     chord=chords[mi]; labels.append(dict(onset=globalq,duration=length,root={'C':0,'D':2,'E':4,'F':5,'G':7,'A':9}[chord[0]],quality='m' if chord.endswith('m') else ''))
     sequence=[]
     # One measured chord attack per bar: beginner whole-bar strumming.
     for ci,(s,f,finger) in enumerate(GRIPS[chord]):sequence.append((OPEN[s]+f,length,ci>0,(s,f,finger)))
    onset=0;last=0
    for ni,(midi,d,chord,grip) in enumerate(sequence):
     identity=f'{resource}-m{mi+1}-n{ni+1}';n=sub(m,'note',id=identity)
     if chord:sub(n,'chord')
     if midi is None:sub(n,'rest')
     else:
      pc=midi%12;step,alter=[('C',0),('C',1),('D',0),('D',1),('E',0),('F',0),('F',1),('G',0),('G',1),('A',0),('A',1),('B',0)][pc]
      p=sub(n,'pitch');sub(p,'step',step)
      if alter:sub(p,'alter',alter)
      sub(p,'octave',midi//12) # sounding octave +1
      s,f,finger=grip or position(midi);positions[identity]=dict(string=s,fret=f,physicalFret=f,midi=midi);fingers[identity]=finger
     sub(n,'duration',round(d*8));sub(n,'voice',1)
     typ={.125:'32nd',.375:'16th',.25:'16th',.5:'eighth',.75:'eighth',1:'quarter',1.5:'quarter',2:'half',3:'half',4:'whole'}.get(d)
     if typ:sub(n,'type',typ)
     if d in [.375,.75,1.5,3]:sub(n,'dot')
     # Authored guitar positions and fingers live in the versioned catalog.
     start=last if chord else onset
     events.append(dict(id=identity,measureIndex=mi,onsetQuarters=globalq+start,durationQuarters=d,midi=midi))
     if not chord:last=onset;onset+=d
    globalq+=length
   E.indent(root);(OUT/(resource+'.musicxml')).write_bytes(E.tostring(root,encoding='utf-8',xml_declaration=True))
   songdata['arrangements'].append(dict(id=resource,kind=kind,resource=resource,positions=positions,fingers=fingers,chords=labels,durationQuarters=globalq,events=events))
  catalog.append(songdata)
 (OUT/'catalog.json').write_text(json.dumps(dict(version=1,songs=catalog),indent=2)+'\n')
 print('Encoded',len(catalog),'songs and',sum(len(s['arrangements']) for s in catalog),'arrangements; source verification remains required')
if __name__=='__main__':main()
