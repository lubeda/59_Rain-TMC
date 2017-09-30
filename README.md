# 59_RainTMC

Niederschlagsvorhersage auf Basis von Wetterdaten von [The Meteo Company](https://www.themeteocompany.com/)

##    Define
    
`define <name> RainTMC <Logitude> <Latitude>`

Die Geokoordinaten können weg gelassen werden falls es eine entsprechende Definition im `global` Device gibt.

## Get

* `rainDuration` Die voraussichtliche Dauer des nächsten Schauers in Minuten
* `startsIn` Der Regen beginnt in x Minuten
* `refresh` Neue Daten werde nonblocking abgefragt

##    Readings

* `rainMax` Die maximale Regenmenge für ein 5 Min. Intervall auf Basis der vorliegenden Daten.
* `rainDataStart` Begin der aktuellen Regenvorhersage. Triggert das Update der Graphen
* `rainNow` Die vorhergesagte Regenmenge für das aktuelle 5 Min. Intervall in mm/m² pro Stunden
* `rainAmount` Die Regenmenge die im kommenden Regenschauer herunterkommen soll
* `rainBegin` Die Uhrzeit des kommenden Regenbegins oder "unknown"
* `rainEnd` Die Uhrzeit des kommenden Regenendes oder "unknown"

## Visualisierung
    
Zur Visualisierung gibt es drei Funktionen:
* `{RainTMC_HTML(<DEVICE>)}` also z.B. {RainTMC_HTML("R")} gibt einen HTML Balken mit einer farblichen Representation der Regenmenge aus.
* `{RainTMC_PNG(<DEVICE>)}` also z.B. {RainTMC_PNG("R")} gibt eine mit der google Charts API generierte Grafik zurück
* `{RainTMC_logProxy(<DEVICE>)}` also z.B. {RainTMC_logProxy("R")} kann in Verbindung mit einem Logproxy Device die typischen FHEM und FTUI Charts erstellen.

