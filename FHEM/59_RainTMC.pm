# This is free and unencumbered software released into the public domain.

# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.

# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

#  For more information, please refer to <http://unlicense.org/>

# See also https://www.buienradar.nl/overbuienradar/gratis-weerdata

# V 1.0 release über Github

package main;

use DateTime;

use strict;
use warnings;
use HttpUtils;

#####################################
sub Buienradar_Initialize($) {

    my ($hash) = @_;

    $hash->{DefFn}       = "Buienradar_Define";
    $hash->{UndefFn}     = "Buienradar_Undef";
    $hash->{GetFn}       = "Buienradar_Get";
    $hash->{FW_detailFn} = "Buienradar_detailFn";
    $hash->{AttrList}    = $readingFnAttributes;
}

sub Buienradar_detailFn($$$$) {
    my ( $FW_wname, $d, $room, $pageHash ) =
      @_;    # pageHash is set for summaryFn.
    my $hash = $defs{$d};

    return if ( !defined( $hash->{URL} ) );

    return
        Buienradar_HTML( $hash->{NAME} )
      . "<br><a href="
      . $hash->{URL}
      . " target=_blank>open data in new window</a><br>";
}

#####################################
sub Buienradar_Undef($$) {

    my ( $hash, $arg ) = @_;

    RemoveInternalTimer($hash);
    return undef;
}

sub Buienradar_TimeCalc($$) {

    # TimeA - TimeB
    my ( $timeA, $timeB ) = @_;

    my @AtimeA = split /:/, $timeA;
    my @AtimeB = split /:/, $timeB;

    if ( $AtimeA[0] < $AtimeB[0] ) {
        $AtimeA[0] += 24;
    }

    if ( ( $AtimeA[1] < $AtimeB[1] ) && ( $AtimeA[0] != $AtimeB[0] ) ) {
        $AtimeA[1] += 60;
    }

    my $result = ( $AtimeA[0] - $AtimeB[0] ) * 60 + $AtimeA[1] - $AtimeB[1];

    return $result;
}

###################################
sub Buienradar_Get($$@) {

    my ( $hash, $name, $opt, @args ) = @_;

    return "\"get $name\" needs at least one argument" unless ( defined($opt) );

    if ( $opt eq "testVal" ) {

        #return  @args;
        return 10**( ( $args[0] - 109 ) / 32 );
    }
    elsif ( $opt eq "rainDuration" ) {
        my $begin = ReadingsVal( $name, "rainBegin", "00:00" );
        my $end   = ReadingsVal( $name, "rainEnd",   "00:00" );
        if ( $begin ne $end ) {
            return Buienradar_TimeCalc( $end, $begin );
        }
        else {
            return "unknown";
        }
    }

    elsif ( $opt eq "refresh" ) {
        Buienradar_RequestUpdate($hash);
        return "";
    }
    elsif ( $opt eq "startsIn" ) {
        my $begin = ReadingsVal( $name, "rainBegin", "unknown" );
        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
          localtime(time);
        my $result = "";

        if ( $begin ne "unknown" ) {

            $result = Buienradar_TimeCalc( $begin, "$hour:$min" );

            if ( $result < 0 ) {
                $result = "raining";
            }
            return $result;
        }
        return "no rain";
    }
    else {
        return
"Unknown argument $opt, choose one of testVal refresh:noArg startsIn:noArg rainDuration:noArg";
    }
}

#####################################
sub Buienradar_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t][ \t]*", $def );
    my $latitude;
    my $longitude;

    if ( ( int(@a) == 2 ) && ( AttrVal( "global", "latitude", -255 ) != -255 ) )
    {
        $latitude  = AttrVal( "global", "latitude",  51 );
        $longitude = AttrVal( "global", "longitude", 7 );
    }
    elsif ( int(@a) == 4 ) {
        $latitude  = $a[2];
        $longitude = $a[3];
    }
    else {
        return
          int(@a)
          . " <=syntax: define <name> Buienradar [<latitude> <longitude>]";
    }

    $hash->{STATE} = "Initialized";

    my $name = $a[0];

    # alle fünf Minuten
    my $interval = 60 * 4;

    $hash->{INTERVAL}  = $interval;
    $hash->{LATITUDE}  = $latitude;
    $hash->{LONGITUDE} = $longitude;
    $hash->{URL} =
        "http://gps.buienradar.nl/getrr.php?lat="
      . $hash->{LATITUDE} . "&lon="
      . $hash->{LONGITUDE};
    $hash->{".HTML"}                   = "<DIV>";
    $hash->{READINGS}{rainBegin}{TIME} = TimeNow();
    $hash->{READINGS}{rainBegin}{VAL}  = "unknown";

    $hash->{READINGS}{rainDataStart}{TIME} = TimeNow();
    $hash->{READINGS}{rainDataStart}{VAL}  = "unknown";

    $hash->{READINGS}{rainNow}{TIME}    = TimeNow();
    $hash->{READINGS}{rainNow}{VAL}     = "unknown";
    $hash->{READINGS}{rainEnd}{TIME}    = TimeNow();
    $hash->{READINGS}{rainEnd}{VAL}     = "unknown";
    $hash->{READINGS}{rainAmount}{TIME} = TimeNow();
    $hash->{READINGS}{rainAmount}{VAL}  = "init";

    Buienradar_RequestUpdate($hash);
    Buienradar_ScheduleUpdate($hash);

# InternalTimer( gettimeofday() + $hash->{INTERVAL},  "Buienradar_ScheduleUpdate", $hash, 0 );

    return undef;
}

sub Buienradar_ScheduleUpdate($) {
    my ($hash) = @_;
    my $nextupdate = 0;
    RemoveInternalTimer( $hash, "Buienradar_ScheduleUpdate" );

    if ( !$hash->{SHORTRELOAD} ) {
        $nextupdate = gettimeofday() + $hash->{INTERVAL};
    }
    else {
        $nextupdate = gettimeofday() + 90;
        delete $hash->{SHORTRELOAD};
    }
    InternalTimer( $nextupdate, "Buienradar_ScheduleUpdate", $hash );
    $hash->{NEXTUPDATE} = FmtDateTime($nextupdate);
    Buienradar_RequestUpdate($hash);

    return 1;
}

sub Buienradar_RequestUpdate($) {
    my ($hash) = @_;

    my $param = {
        url      => $hash->{URL},
        timeout  => 10,
        hash     => $hash,
        method   => "GET",
        callback => \&Buienradar_ParseHttpResponse
    };

    HttpUtils_NonblockingGet($param);
    Log3( $hash->{NAME}, 4, $hash->{NAME} . ": Update requested" );
}

sub Buienradar_HTML($;$) {
    my ( $name, $width ) = @_;
    my $hash = $defs{$name};
    my @values = split /:/, $hash->{".rainData"};

    my $as_html = <<'END_MESSAGE';
<style>

.BRchart div {
  font: 10px sans-serif;
  background-color: steelblue;
  text-align: right;
  padding: 3px;
  margin: 1px;
  color: white;
}

</style>
<div class="BRchart">
END_MESSAGE

    $as_html .= "<BR>Niederschlag (<a href=./fhem?detail=$name>$name</a>)<BR>";

    $as_html .= ReadingsVal( $name, "rainDataStart", "unknown" ) . "<BR>";
    my $factor =
      ( $width ? $width : 700 ) / ( 1 + ReadingsVal( $name, "rainMax", "0" ) );
    foreach my $val (@values) {
        $as_html .=
            '<div style="width: '
          . ( int( $val * $factor ) + 30 ) . 'px;">'
          . sprintf( "%.3f", $val )
          . '</div>';
    }

    $as_html .= "</DIV><BR>";
    return ($as_html);
}

sub Buienradar_HTMLRaw($;$) {
    my ( $name, $width ) = @_;
    my $hash = $defs{$name};
    my @values = split /:/, $hash->{".rainDataRaw"};

    my $as_html = <<'END_MESSAGE';
<style>

.BRchart div {
  font: 10px sans-serif;
  background-color: steelblue;
  text-align: right;
  padding: 3px;
  margin: 1px;
  color: white;
}

</style>
<div class="BRchart">
END_MESSAGE

    $as_html .= "<BR>Niederschlag (<a href=./fhem?detail=$name>$name</a>)<BR>";

    $as_html .= ReadingsVal( $name, "rainDataStart", "unknown" ) . "<BR>";
    my $factor =
      ( $width ? $width : 700 ) / ( 1 + ReadingsVal( $name, "rainMax", "0" ) );
    foreach my $val (@values) {
        $as_html .=
            '<div style="width: '
          . ( int( $val * $factor ) + 30 ) . 'px;">'
          . sprintf( "%.3f", $val )
          . '</div>';
    }

    $as_html .= "</DIV><BR>";
    return ($as_html);
}

sub Buienradar_ParseHttpResponse($) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err ne "" ) {
        Log3( $name, 3,
            "$name: error while requesting " . $param->{url} . " - $err" );
        $hash->{STATE}       = "Error: " . $err . " => " . $data;
        $hash->{SHORTRELOAD} = 1;
        Buienradar_ScheduleUpdate($hash);
    }
    elsif ( $data ne "" ) {
        Log3( $name, 5, "$name: returned: $data" );

        my $rainamount    = 0.0;
        my $rainbegin     = "unknown";
        my $rainend       = "unknown";
        my $rainDataStart = "unknown";
        my $rainDataEnd   = "unknown";
        my $rainData      = "";
        my $rainDataRaw   = "";
        my $rainMax       = 0;
        my $rainLaMetric  = "";
        my $as_png        = "";
        my $rain          = 0;
        my $rainNow       = 0;
        my $rainTotal     = 0;
        my $line          = 0;
        my $beginchanged  = 0;
        my $endchanged    = 0;
        my $endline       = 0;
        my $parse         = 1;

        foreach ( split( /\n/, $data ) ) {
            my ( $amount, $rtime ) = ( split( /\|/, $_ ) )[ 0, 1 ];
            $rtime = substr($rtime,0,-1);
            
            if ( $amount > 0 ) {
                $rain = 10**( ( $amount - 109 ) / 32 );
                $rainTotal += $rain / 12;
            }
            else {
                $rain = 0;
            }

            $line += 1;

            if ( $line == 1 ) {
                $rainNow = sprintf( "%.3f", $rainamount ) * 12;
                $rainDataStart = $rtime;
                $rainData = sprintf( "%.3f", $rainamount );
                $rainDataRaw = $rainamount;
            }
            if ( $line < 13 ) {
                $rainLaMetric .= int( $rainamount * 1000 ) . ",";
            }
            if ($parse) {
                $rainamount += $rain / 12;
                if ($beginchanged) {
                    if ( $amount > 0 ) {
                        $rainend = $rtime;
                    }
                    else {
                        $rainend    = $rtime;
                        $endchanged = 1;
                        $parse      = 0;      # Nur den ersten Schauer auswerten
                    }
                }
                else {
                    if ( $amount > 0 ) {
                        $rainbegin    = $rtime;
                        $beginchanged = 1;
                        $rainend      = $rtime;
                    }
                }
            }

            $rainData .= ":" . sprintf( "%.3f", $rain );
            $rainDataEnd = $rtime;
            $rainDataRaw .= ":" . $amount;

            $rainMax = ( $rain > $rainMax ) ? $rain : $rainMax;

            $as_png .= "['"
              . ( ( $line % 2 ) ?  $rtime : "" ) . "',"
              . sprintf( "%.3f", $rain ) . "],";
        }
        $as_png       = substr( $as_png,       0, -1 );
        $rainLaMetric = substr( $rainLaMetric, 0, -1 );
        $hash->{".PNG"} = $as_png;
        $hash->{STATE} = sprintf( "%.3f mm/h", $rainNow );

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "rainTotal",
            sprintf( "%.3f", $rainTotal * 12 ) );
        readingsBulkUpdateIfChanged( $hash, "rainAmount",
            sprintf( "%.3f", $rainamount * 12 ) );
        readingsBulkUpdateIfChanged( $hash, "rainNow",       $rainNow );
        readingsBulkUpdateIfChanged( $hash, "rainLaMetric",  $rainLaMetric );
        readingsBulkUpdateIfChanged( $hash, "rainDataStart", $rainDataStart );
        readingsBulkUpdateIfChanged( $hash, "rainDataEnd",   $rainDataEnd );
        $hash->{".rainData"}    = $rainData;
        $hash->{".rainDataRaw"} = $rainDataRaw;
        readingsBulkUpdateIfChanged( $hash, "rainMax",
            sprintf( "%.3f", $rainMax ) );
        readingsBulkUpdateIfChanged( $hash, "rainBegin", $rainbegin,
            $beginchanged );
        readingsBulkUpdateIfChanged( $hash, "rainEnd", $rainend, $endchanged );
        readingsEndUpdate( $hash, 1 );
    }
}

sub Buienradar_logProxy($) {
    my ($name) = @_;
    my $hash = $defs{$name};
    my @values = split /:/, $hash->{".rainData"};

    my $date = DateTime->now;
    my $ret;

    my $date5m = DateTime::Duration->new( minutes => 5 );

    #$date5m->minutes=5;

    my @startdate =
      ( split /:/, ReadingsVal( $name, "rainDataStart", "12:00" ) );

    $date->set( hour => $startdate[0], minute => $startdate[1], second => 0 );
    my $max = 0;
    foreach my $val (@values) {
        $max = ( $val > $max ) ? $val : $max;
        $ret .= $date->ymd . "_" . $date->hms . " " . $val . "\r\n";
        $date += $date5m;
    }

    return ( $ret, 0, $max );
}

sub Buienradar_logProxyRaw($) {
    my ($name) = @_;
    my $hash = $defs{$name};
    my @values = split /:/, $hash->{".rainDataRaw"};

    my $date = DateTime->now;
    my $ret;

    my $date5m = DateTime::Duration->new( minutes => 5 );

    #$date5m->minutes=5;

    my @startdate =
      ( split /:/, ReadingsVal( $name, "rainDataStart", "12:00" ) );

    $date->set( hour => $startdate[0], minute => $startdate[1], second => 0 );
    my $max = 0;
    foreach my $val (@values) {
        $max = ( $val > $max ) ? $val : $max;
        $ret .= $date->ymd . "_" . $date->hms . " " . $val . "\r\n";
        $date += $date5m;
    }

    return ( $ret, 0, $max );
}

sub Buienradar_PNG($) {
    my ($name) = @_;
    my $retval = '<div id="chart_div_' . $name . '";';
    $retval .= <<'END_MESSAGE';
 style="width:100%; height:100%"></div>
<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
 <script type="text/javascript">

     google.charts.load("current", {packages:["corechart"]});
      google.charts.setOnLoadCallback(drawChart);
      function drawChart() {
        var data = google.visualization.arrayToDataTable([
          ['string', 'mm/m² per h'],
END_MESSAGE

    $retval .= $defs{$name}->{".PNG"};
    $retval .= <<'END_MESSAGE';
]);

 var options = {
END_MESSAGE

    $retval .= 'title: "Niederschlag (' . $name .')",';

    $retval .= "subtitle: 'Vorhersage (" . $name . ")',";

    $retval .= <<'END_MESSAGE';
          hAxis: {slantedText:true, slantedTextAngle:45,
              textStyle: {
              fontSize: 10}
              },
          vAxis: {minValue: 0}
        };

        var my_div = document.getElementById(
END_MESSAGE

    $retval .= '"chart_div_' . $name . '");';

    $retval .= <<'END_MESSAGE';
        var chart = new google.visualization.AreaChart(my_div);
        google.visualization.events.addListener(chart, 'ready', function () {
        my_div.innerHTML = '<img src="' + chart.getImageURI() + '">';
    });

        chart.draw(data, options);}
    </script>
END_MESSAGE
    return $retval;
}

1;

=pod
item helper

=item summary Rain prediction

=item summary_DE Regenvorhersage auf Basis des Wetterdienstes Buienradar

=begin html

See german documentation

=end html

=begin html_DE

<a name="Buienradar"></a>
<h2>59_Buienradar</h2>
<p>Niederschlagsvorhersage auf Basis von freien Wetterdaten der niederländischen Seite <a href="https://www.buienradar.nl/overbuienradar/gratis-weerdata">Buienradar</a></p>
<h3>Define</h3>
<p><code>define &lt;name&gt; Buienradar &lt;Logitude&gt; &lt;Latitude&gt;</code></p>
<p>Die Geokoordinaten k&ouml;önnen weg gelassen werden falls es eine entsprechende Definition im <code>global</code> Device gibt.
Das Modul ben&ouml;tigt die Perl Bibliothek <strong>DateTime</strong>, diese kann mit dem Befehl <code>cpan install DateTime</code> installiert werden.</p>
<h3>Get</h3>
<ul>
<li><code>rainDuration</code> Die voraussichtliche Dauer des n&auml;chsten Schauers in Minuten</li>
<li><code>startsIn</code> Der Regen beginnt in x Minuten</li>
<li><code>refresh</code> Neue Daten werde nonblocking abgefragt/</li>
<li><code>testVal</code> Rechnet einen Buienradar Wert in mm/m² um ( zu Testzwecken)</li>
</ul>
<h3>Readings</h3>
<ul>
<li><code>rainMax</code> Die maximale Regenmenge f&uuml;r ein 5 Min. Intervall auf Basis der vorliegenden Daten.</li>
<li><code>rainDataStart</code> Begin der aktuellen Regenvorhersage. Triggert das Update der Graphen</li>
<li><code>rainNow</code> Die vorhergesagte Regenmenge f&uuml;r das aktuelle 5 Min. Intervall in mm/m² pro Stunden</li>
<li><code>rainAmount</code> Die Regenmenge die im kommenden Regenschauer herunterkommen soll</li>
<li><code>rainDataEnd</code> Ende der Regenvorhersage</li>
<li><code>rainTotal</code> Die Regenmenge die in dem Vorhersage enthalten ist</li>
<li><code>rainLametric</code> Die n&auml;chsten 12 Regenmengen aufbereitet für ein LaMetric Display</li>
<li><code>rainBegin</code> Die Uhrzeit des kommenden Regenbegins oder "unknown"</li>
<li><code>rainEnd</code> Die Uhrzeit des kommenden Regenendes oder "unknown"</li>
</ul>
<h3>Visualisierung</h3>
<p>Zur Visualisierung gibt es drei Funktionen:</p>
<p>Die Funktionen <code>Buienradar_HTML</code> und <code>Buienradar_PNG</code> k&ouml;nnen im  FHEMWEB verwendet werden. Die Funktion <code>Buienradar_logProxy</code> kann in Verbindung mit SVG oder im FTUI vorzugsweise mit dem Highchart Widget eingesetzt werden.</P>
<ul>
<li><code>{Buienradar_HTML(&lt;DEVICE&gt;,&lt;Width&gt;)}</code> also z.B. {Buienradar_HTML("BR",500)} gibt eine reine HTML Liste zurück, der längste Balken hat dann 500 Pixel (nicht so schön ;-))</li>
<li><code>{Buienradar_PNG(&lt;DEVICE&gt;)}</code> also z.B. {Buienradar_PNG("BR")} gibt eine mit der google Charts API generierte Grafik zurück</li>
<li><code>{Buienradar_logProxy(&lt;DEVICE&gt;)}</code> also z.B. {Buienradar_logProxy("BR")} kann in Verbindung mit einem Logproxy Device die typischen FHEM und FTUI Charts erstellen.</li>
</ul>

=end html_DE

=cut
