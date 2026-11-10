# Touchline 5

Touchline 5 ist ein eigenständiges 3D-Fußballspiel für Windows. In der ersten Alpha spielst du im Dockpark mit dem SV Hafenstrom oder den Rotfalken 05 gegen die KI. Beide Teams stellen vier Feldspieler und einen Torwart.

## Starten

Lade die Windows-x64-ZIP aus den [GitHub-Releases](https://github.com/adyhdc/FifaFootball/releases) und entpacke sie vollständig. Starte im entpackten Ordner `Touchline5.exe`. Die mitgelieferte `Touchline5.pck` muss neben der EXE liegen. Für das Spiel brauchst du keinen Godot-Editor.

## Spielen

Schließe den DualSense für den ersten Test per USB an. Im Menü navigierst du mit dem linken Stick oder Steuerkreuz. Kreuz bestätigt. Die Steuerung lässt sich in der Teamauswahl und im Pausenmenü nachschlagen.

| Aktion | DualSense | Tastatur |
| --- | --- | --- |
| Laufen und zielen | Linker Stick | WASD oder Pfeiltasten |
| Kurzpass | Kreuz | J |
| Steilpass | Dreieck | I |
| Schuss | Kreis halten und loslassen | K halten und loslassen |
| Sprint | R2 | Umschalt |
| Zweikampf | Kreis ohne Ball oder Quadrat | Leertaste |
| Feldspieler wechseln | L1 | Q |
| Pause | Options | Esc |

Ziele mit dem Stick oder den Richtungstasten. Beim Pass wählt das Spiel einen Mitspieler in der gewünschten Richtung. Der Steilpass spielt in den Lauf. Bei eigenen Spielfortsetzungen zielst du auf dieselbe Weise und löst sie mit Pass, Steilpass oder Schuss aus. Beim Einwurf wirft auch die Schusstaste zu einem Mitspieler.

Zwei Halbzeiten dauern jeweils drei Minuten laufender Spielzeit. Die Anzeige rechnet sie auf je 45 Fußballminuten hoch. Nach der Pause tauschen die Teams die Seiten. Nach dem Abpfiff kannst du mit demselben Verein eine Revanche starten oder zurück zur Teamauswahl gehen.

Die Alpha prüft die Position der Feldspieler bei der Ballabgabe anhand ihrer Position auf dem Spielfeld. Ein Eingreifen liegt bei Ballkontakt, einem engen Duell um den Ball oder beim Verdecken der Sicht des Torwarts vor. Einwurf, Ecke und Abstoß sind beim direkten Zuspiel ausgenommen. Bei einem klaren Zweikampf von hinten oder ohne Zugriff auf den Ball gibt es Freistoß oder Elfmeter. Das Modell verwendet vereinfachte Körper- und Kontaktgeometrie sowie verkürzte Abstände bei Spielfortsetzungen. [IFAB, Regel 11](https://www.theifab.com/laws/latest/offside/)

## Tests und Build

Das Repo verwendet Godot 4.6.3 mit GDScript und dem Compatibility-Renderer. Modelle, Stadion, Trikots und Audio werden aus Projektcode erzeugt. Mit Godot und den passenden Windows-Exportvorlagen kann der Build auch per Kommandozeile erzeugt werden.

```sh
godot --headless --editor --import
godot --headless --script res://tests/match_test.gd
godot --headless -- --smoke
mkdir -p build
godot --headless --export-release "Windows Desktop" build/Touchline5.exe
```

GitHub Actions prüft die Matchregeln, exportiert für Windows x64 und startet die aus der ZIP entpackte Windows-EXE. Der Starttest öffnet die Teamauswahl, startet ein Match und führt den Anstoß mit synthetischen Gamepad-Ereignissen aus. Die Bedienung mit einem physischen DualSense ist eine eigene Abnahme. Die ZIP enthält die Lizenz- und Copyright-Hinweise der Engine.

Beim ersten Spieltest sind die Stick-Totzone, L1-Spielerwechsel, Kurzpass-Zielwahl, Sprinttempo, Schusskraft und die Lesbarkeit von Ball und Spielern in der TV-Kamera besonders wichtig.
